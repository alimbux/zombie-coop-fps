extends CharacterBody3D
## Игрок от первого лица. Игрок 1 играет на клавиатуре и мыши (и на геймпаде, если
## геймпадов хватает на всех), остальные — на своих геймпадах.
## Камера живёт в своей части экрана и следует за телом.

const Sfx := preload("res://scripts/sfx.gd")
const Weapons := preload("res://scripts/weapons.gd")
const PlayerModel := preload("res://scripts/player_model.gd")
const Kit := preload("res://scripts/mesh_kit.gd")

const SPEED := 4.5
const GRAVITY := 18.0
const EYE_HEIGHT := 1.6
const DOWNED_EYE_HEIGHT := 0.5
const MOUSE_SENSITIVITY := 0.0025
const PAD_LOOK_SPEED := 2.8
const PAD_DEADZONE := 0.18
const AIM_ASSIST_SLOWDOWN := 0.45
const RAY_MASK := 1 | 4
const REVIVE_TIME := 3.0
const REVIVE_RANGE := 1.6
const MAX_HP := 100.0
const MAX_PLAYERS := 4
const BODY_LAYER_BIT := 10
const WEAPON_LAYER_BIT := 14

var index := 0
## Номер геймпада игрока; -1 — только клавиатура и мышь.
var pad := 0
var camera: Camera3D
var hud: Control
var hp := MAX_HP
var downed := false
var revive_progress := 0.0
var reload_left := 0.0
var fire_cooldown := 0.0
var yaw := 0.0
var pitch := 0.0
var kills := 0

var owned: Array = ["knife"]
var current := "knife"
var mag := {}
var reserve := {}

var _shake := 0.0
var _kick := 0.0
var _fire_was_pressed := false
var _next_was_pressed := false
var _share_was_pressed := false
var _muzzle: OmniLight3D
var _weapon: Node3D
var _model: Node3D
var _gun_mat: StandardMaterial3D
var _blade_mat: StandardMaterial3D


func setup(player_index: int, pad_index: int, cam: Camera3D, hud_node: Control) -> void:
	index = player_index
	pad = pad_index
	camera = cam
	hud = hud_node
	for w in Weapons.ORDER:
		mag[w] = 0
		reserve[w] = 0


func _ready() -> void:
	add_to_group("players")
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_build_body()
	_build_camera_rig()
	_build_weapon_model()


# --- Снаряжение -------------------------------------------------------------

func get_loadout() -> Dictionary:
	return {"owned": owned.duplicate(), "current": current, "mag": mag.duplicate(), "reserve": reserve.duplicate(), "kills": kills}


func set_loadout(data: Dictionary) -> void:
	if data.is_empty():
		return
	owned = data["owned"].duplicate()
	mag = data["mag"].duplicate()
	reserve = data["reserve"].duplicate()
	kills = data.get("kills", 0)
	switch_to(data["current"])


## Подобрал оружие: если его не было — берёт в руки, патроны идут в запас.
func give_weapon(weapon: String, ammo: int) -> bool:
	var is_new := not owned.has(weapon)
	if is_new:
		owned.append(weapon)
		owned.sort_custom(func(a, b): return Weapons.ORDER.find(a) < Weapons.ORDER.find(b))
		mag[weapon] = mini(ammo, Weapons.stat(weapon, "mag"))
		ammo -= mag[weapon]
	var added := give_ammo(weapon, ammo)
	if is_new:
		switch_to(weapon)
	return is_new or added


func give_ammo(weapon: String, ammo: int) -> bool:
	var cap: int = Weapons.stat(weapon, "max_reserve")
	if reserve[weapon] >= cap:
		return false
	reserve[weapon] = mini(cap, reserve[weapon] + ammo)
	return true


func heal(amount: float) -> bool:
	if downed or hp >= MAX_HP:
		return false
	hp = minf(MAX_HP, hp + amount)
	return true


func switch_to(weapon: String) -> void:
	if not owned.has(weapon) or weapon == current and _weapon and _weapon.get_child_count() > 0:
		return
	current = weapon
	reload_left = 0.0
	fire_cooldown = 0.25
	_build_weapon_model()


func cycle_weapon(step: int) -> void:
	var i := owned.find(current)
	switch_to(owned[posmod(i + step, owned.size())])


func add_mouse_look(relative: Vector2) -> void:
	yaw -= relative.x * MOUSE_SENSITIVITY
	pitch = clampf(pitch - relative.y * MOUSE_SENSITIVITY, -1.4, 1.4)


func take_damage(amount: float) -> void:
	if downed:
		return
	hp -= amount
	_shake = 0.3
	Sfx.play_flat(self, "hurt", -3.0)
	if hud:
		hud.flash_damage()
	if hp <= 0.0:
		hp = 0.0
		downed = true
		revive_progress = 0.0


# --- Каждый кадр ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	fire_cooldown -= delta
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			_finish_reload()
	_pad_look(delta)
	_move(delta)
	_try_revive(delta)
	_handle_weapon()
	_update_camera(delta)
	_model.rotation.y = yaw
	_model.animate(delta, Vector2(velocity.x, velocity.z).length(), pitch, downed)
	if hud:
		var melee: bool = Weapons.stat(current, "melee")
		var ammo_text := "" if melee else ("перезарядка" if reload_left > 0.0 else "%d / %d" % [mag[current], reserve[current]])
		hud.set_status(hp, Weapons.display_name(current), ammo_text, kills, downed, revive_progress / REVIVE_TIME)


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var input := Vector2.ZERO if downed else _move_input()
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	move_and_slide()


func _move_input() -> Vector2:
	var v := Vector2.ZERO
	if index == 0:
		v.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		v.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var stick := Vector2(_axis(JOY_AXIS_LEFT_X), _axis(JOY_AXIS_LEFT_Y))
	if stick.length() > PAD_DEADZONE:
		v += stick
	return v.limit_length(1.0)


func _pad_look(delta: float) -> void:
	var look := Vector2(_axis(JOY_AXIS_RIGHT_X), _axis(JOY_AXIS_RIGHT_Y))
	if look.length() < PAD_DEADZONE:
		return
	var speed := PAD_LOOK_SPEED
	# Мягкий aim assist: над зомби прицел замедляется, но никуда сам не тянет.
	if aim_zone() != "":
		speed *= AIM_ASSIST_SLOWDOWN
	yaw -= look.x * speed * delta
	pitch = clampf(pitch - look.y * speed * delta, -1.4, 1.4)


func _handle_weapon() -> void:
	var fire := _axis(JOY_AXIS_TRIGGER_RIGHT) > 0.5
	var reload := _button(JOY_BUTTON_X)
	var next := _button(JOY_BUTTON_Y)
	var share := _button(JOY_BUTTON_B)
	if index == 0:
		share = share or Input.is_physical_key_pressed(KEY_G)
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			fire = true
		reload = reload or Input.is_physical_key_pressed(KEY_R)
		next = next or Input.is_physical_key_pressed(KEY_Q)
		for i in Weapons.ORDER.size():
			if Input.is_physical_key_pressed(KEY_1 + i):
				switch_to(Weapons.ORDER[i])
	if next and not _next_was_pressed:
		cycle_weapon(1)
	_next_was_pressed = next
	if share and not _share_was_pressed:
		share_ammo()
	_share_was_pressed = share

	var melee: bool = Weapons.stat(current, "melee")
	if reload and not melee:
		_start_reload()
	var auto: bool = Weapons.stat(current, "auto")
	var trigger := fire and (auto or not _fire_was_pressed)
	_fire_was_pressed = fire
	if not trigger or fire_cooldown > 0.0 or reload_left > 0.0:
		return
	if melee or mag[current] > 0:
		shoot()
	elif reserve[current] > 0:
		_start_reload()
	else:
		fire_cooldown = 0.4
		Sfx.play_flat(self, "click", -6.0)
		if hud:
			hud.show_message("НЕТ ПАТРОНОВ", 1.0)


## Удар ножом или выстрел из текущего оружия. Возвращает первую задетую зону тела.
func shoot() -> String:
	var stats: Dictionary = Weapons.STATS[current]
	fire_cooldown = stats["interval"]
	_kick = 1.0
	if stats["melee"]:
		Sfx.play_flat(self, "slash", -4.0)
	else:
		mag[current] -= 1
		_shake = maxf(_shake, 0.12 + 0.1 * float(stats["pellets"] > 1))
		_muzzle.light_energy = 6.0
		var pitch_scale := 1.0
		if current == "smg":
			pitch_scale = 1.25
		elif current == "shotgun":
			pitch_scale = 0.7
		Sfx.play_flat(self, "shot", -2.0 if current != "smg" else -5.0, pitch_scale)
		_alert_zombies(stats["noise"])
	var first := ""
	var hit_zombies := {}
	for p in int(stats["pellets"]):
		var dir := -camera.global_transform.basis.z
		var spread: float = stats["spread"]
		dir = (dir + camera.global_transform.basis.x * randf_range(-spread, spread)
			+ camera.global_transform.basis.y * randf_range(-spread, spread)).normalized()
		var hit := _ray(dir, stats["range"])
		if hit.is_empty() or not (hit["collider"] is Area3D) or not hit["collider"].has_meta("zone"):
			continue
		var zone: String = hit["collider"].get_meta("zone")
		var zombie = hit["collider"].get_meta("zombie")
		if not is_instance_valid(zombie) or zombie.dead:
			continue
		var loud := not hit_zombies.has(zombie)
		hit_zombies[zombie] = true
		if zombie.take_hit(zone, stats["damage"], hit["position"], dir, loud):
			kills += 1
		if first == "":
			first = zone
	if first != "" and hud:
		hud.flash_hit(first == "head")
	return first


## Передаёт половину запаса патронов ближайшему напарнику (до 2,5 м).
## Патроны того оружия, что в руках; с ножом в руках — того, которых больше всего.
## Возвращает, сколько патронов передано.
func share_ammo() -> int:
	var mate = null
	var best := 2.5
	for p in get_tree().get_nodes_in_group("players"):
		var d: float = p.global_position.distance_to(global_position)
		if p != self and d < best:
			best = d
			mate = p
	if mate == null:
		if hud:
			hud.show_message("ПОДОЙДИ К НАПАРНИКУ", 1.0)
		return 0
	var gun := current
	if Weapons.stat(gun, "melee"):
		for w in Weapons.ORDER:
			if reserve[w] > reserve[gun]:
				gun = w
	var amount := ceili(reserve[gun] / 2.0)
	var room: int = Weapons.stat(gun, "max_reserve") - mate.reserve[gun] if not Weapons.stat(gun, "melee") else 0
	amount = mini(amount, room)
	if amount <= 0:
		if hud:
			hud.show_message("НЕЧЕГО ПЕРЕДАТЬ", 1.0)
		return 0
	reserve[gun] -= amount
	mate.reserve[gun] += amount
	var what := "%s %d" % [Weapons.display_name(gun), amount]
	Sfx.play_flat(self, "pickup", -8.0)
	if hud:
		hud.show_message("ОТДАЛ ИГРОКУ %d: %s" % [mate.index + 1, what], 1.5)
	if mate.hud:
		mate.hud.show_message("ИГРОК %d ДАЛ ТЕБЕ: %s" % [index + 1, what], 1.5)
	return amount


## Зона тела под прицелом (нужна для aim assist).
func aim_zone() -> String:
	var hit := _ray(-camera.global_transform.basis.z, 60.0)
	if hit.is_empty() or not (hit["collider"] is Area3D):
		return ""
	return str(hit["collider"].get_meta("zone", ""))


func _ray(dir: Vector3, length: float) -> Dictionary:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * length, RAY_MASK)
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _alert_zombies(radius: float) -> void:
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.global_position.distance_to(global_position) < radius:
			z.alert()


func _start_reload() -> void:
	var size: int = Weapons.stat(current, "mag")
	if reload_left > 0.0 or mag[current] >= size or reserve[current] <= 0:
		return
	reload_left = Weapons.stat(current, "reload")
	Sfx.play_flat(self, "reload", -4.0)


func _finish_reload() -> void:
	var size: int = Weapons.stat(current, "mag")
	var take := mini(size - mag[current], reserve[current])
	mag[current] += take
	reserve[current] -= take


func _try_revive(delta: float) -> void:
	if not downed:
		return
	var helped := false
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and not p.downed and p.global_position.distance_to(global_position) < REVIVE_RANGE:
			helped = true
	revive_progress = revive_progress + delta if helped else 0.0
	if revive_progress >= REVIVE_TIME:
		downed = false
		hp = 50.0
		revive_progress = 0.0


func _axis(axis: JoyAxis) -> float:
	return Input.get_joy_axis(pad, axis) if pad >= 0 else 0.0


func _button(button: JoyButton) -> bool:
	return pad >= 0 and Input.is_joy_button_pressed(pad, button)


# --- Камера и модели --------------------------------------------------------

func _update_camera(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta)
	_kick = maxf(0.0, _kick - delta * 8.0)
	_muzzle.light_energy = maxf(0.0, _muzzle.light_energy - delta * 120.0)
	var eye := DOWNED_EYE_HEIGHT if downed else EYE_HEIGHT
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _shake * 0.06
	var recoil := 0.0 if current == "knife" else _kick * 0.03
	camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(pitch + recoil, yaw, 0.0)),
		global_position + Vector3.UP * eye + jitter)
	if current == "knife":
		# Взмах ножом: лезвие проходит справа налево.
		_weapon.position = Vector3(-_kick * 0.25, 0.0, -_kick * 0.15)
		_weapon.rotation = Vector3(0.0, _kick * 0.9, -_kick * 0.4)
	else:
		_weapon.position = Vector3(0.0, 0.0, _kick * 0.08)
		_weapon.rotation = Vector3(_kick * 0.25, 0.0, 0.0)


func _build_body() -> void:
	var layer := 1 << (BODY_LAYER_BIT + index)
	_model = PlayerModel.new()
	add_child(_model)
	_model.build(index, layer)
	# Номер над головой, чтобы напарник находил игрока в суматохе.
	var label := Label3D.new()
	label.text = str(index + 1)
	label.font_size = 96
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 2.25
	label.layers = layer
	add_child(label)


func _build_camera_rig() -> void:
	camera.fov = 80.0
	camera.near = 0.05
	var mask := (1 << 20) - 1
	mask &= ~(1 << (BODY_LAYER_BIT + index))
	for i in MAX_PLAYERS:
		if i != index:
			mask &= ~(1 << (WEAPON_LAYER_BIT + i))
	camera.cull_mask = mask

	var flashlight := SpotLight3D.new()
	flashlight.spot_range = 20.0
	flashlight.spot_angle = 26.0
	flashlight.light_energy = 5.0
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.15, -0.1, 0.0)
	camera.add_child(flashlight)

	_muzzle = OmniLight3D.new()
	_muzzle.omni_range = 7.0
	_muzzle.light_energy = 0.0
	_muzzle.position = Vector3(0.22, -0.15, -0.8)
	camera.add_child(_muzzle)

	_weapon = Node3D.new()
	camera.add_child(_weapon)
	_gun_mat = StandardMaterial3D.new()
	_gun_mat.albedo_color = Color(0.22, 0.22, 0.22)
	_gun_mat.roughness = 0.6
	# Лёгкое свечение, чтобы оружие не терялось в темноте.
	_gun_mat.emission_enabled = true
	_gun_mat.emission = Color(0.12, 0.12, 0.12)
	_blade_mat = StandardMaterial3D.new()
	_blade_mat.albedo_color = Color(0.9, 0.9, 0.9)
	_blade_mat.metallic = 0.6
	_blade_mat.roughness = 0.2
	_blade_mat.emission_enabled = true
	_blade_mat.emission = Color(0.25, 0.25, 0.25)


## Модель оружия в руках из нескольких блоков: узнаётся по силуэту.
func _build_weapon_model() -> void:
	if _weapon == null:
		return
	for c in _weapon.get_children():
		c.queue_free()
	if _model:
		_model.set_weapon(current)
		# Своя рука в рукаве того же тона, что одежда персонажа.
		var st: Dictionary = PlayerModel.STYLES[_model.style]
		_add_block(Vector3(0.07, 0.07, 0.3), Vector3(0.29, -0.38, -0.3), 0.3, Kit.shade(st["top"]))
		_add_block(Vector3(0.06, 0.07, 0.08), Vector3(0.27, -0.33, -0.47), 0.3, Kit.shade(st["skin"]))
	match current:
		"knife":
			_add_block(Vector3(0.03, 0.04, 0.12), Vector3(0.24, -0.27, -0.42), 0.4, _gun_mat)
			_add_block(Vector3(0.012, 0.05, 0.22), Vector3(0.24, -0.22, -0.58), 0.4, _blade_mat)
		"pistol":
			_add_block(Vector3(0.06, 0.08, 0.26), Vector3(0.26, -0.25, -0.55), 0.0, _gun_mat)
			_add_block(Vector3(0.05, 0.13, 0.07), Vector3(0.26, -0.33, -0.48), 0.25, _gun_mat)
		"smg":
			_add_block(Vector3(0.07, 0.1, 0.5), Vector3(0.24, -0.24, -0.6), 0.0, _gun_mat)
			_add_block(Vector3(0.04, 0.18, 0.06), Vector3(0.24, -0.36, -0.62), 0.15, _gun_mat)
			_add_block(Vector3(0.05, 0.12, 0.07), Vector3(0.24, -0.33, -0.44), 0.25, _gun_mat)
		"shotgun":
			_add_block(Vector3(0.08, 0.08, 0.75), Vector3(0.23, -0.23, -0.7), 0.0, _gun_mat)
			_add_block(Vector3(0.1, 0.07, 0.25), Vector3(0.23, -0.29, -0.62), 0.0, _blade_mat)
			_add_block(Vector3(0.07, 0.14, 0.2), Vector3(0.23, -0.3, -0.3), 0.3, _gun_mat)


func _add_block(size: Vector3, pos: Vector3, tilt: float, mat: Material) -> void:
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	block.mesh = box
	block.material_override = mat
	block.position = pos
	block.rotation.x = tilt
	block.layers = 1 << (WEAPON_LAYER_BIT + index)
	block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_weapon.add_child(block)
