extends CharacterBody3D
## Игрок от первого лица. Игрок 1 — клавиатура и мышь или геймпад 0,
## игрок 2 — геймпад 1. Камера живёт в своей половине экрана и следует за телом.

const Sfx := preload("res://scripts/sfx.gd")

const SPEED := 4.5
const GRAVITY := 18.0
const EYE_HEIGHT := 1.6
const DOWNED_EYE_HEIGHT := 0.5
const MOUSE_SENSITIVITY := 0.0025
const PAD_LOOK_SPEED := 2.8
const PAD_DEADZONE := 0.18
const AIM_ASSIST_SLOWDOWN := 0.45
const FIRE_INTERVAL := 0.22
const MAG_SIZE := 12
const RELOAD_TIME := 1.1
const DAMAGE := 34.0
const RAY_LENGTH := 60.0
const RAY_MASK := 1 | 4
const REVIVE_TIME := 3.0
const REVIVE_RANGE := 1.6
const MAX_PLAYERS := 4
const BODY_LAYER_BIT := 10
const WEAPON_LAYER_BIT := 14

var index := 0
var camera: Camera3D
var hud: Control
var hp := 100.0
var downed := false
var revive_progress := 0.0
var ammo := MAG_SIZE
var reload_left := 0.0
var fire_cooldown := 0.0
var yaw := 0.0
var pitch := 0.0
var kills := 0
var _shake := 0.0
var _kick := 0.0
var _fire_was_pressed := false
var _muzzle: OmniLight3D
var _weapon: Node3D


func setup(player_index: int, cam: Camera3D, hud_node: Control) -> void:
	index = player_index
	camera = cam
	hud = hud_node


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


func _physics_process(delta: float) -> void:
	fire_cooldown -= delta
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			ammo = MAG_SIZE
	_pad_look(delta)
	_move(delta)
	_try_revive(delta)
	_handle_weapon()
	_update_camera(delta)
	if hud:
		hud.set_status(hp, ammo, MAG_SIZE, reload_left > 0.0, kills, downed, revive_progress / REVIVE_TIME)


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
	var pad := Vector2(Input.get_joy_axis(index, JOY_AXIS_LEFT_X), Input.get_joy_axis(index, JOY_AXIS_LEFT_Y))
	if pad.length() > PAD_DEADZONE:
		v += pad
	return v.limit_length(1.0)


func _pad_look(delta: float) -> void:
	var look := Vector2(Input.get_joy_axis(index, JOY_AXIS_RIGHT_X), Input.get_joy_axis(index, JOY_AXIS_RIGHT_Y))
	if look.length() < PAD_DEADZONE:
		return
	var speed := PAD_LOOK_SPEED
	# Мягкий aim assist: над зомби прицел замедляется, но никуда сам не тянет.
	if aim_zone() != "":
		speed *= AIM_ASSIST_SLOWDOWN
	yaw -= look.x * speed * delta
	pitch = clampf(pitch - look.y * speed * delta, -1.4, 1.4)


func _handle_weapon() -> void:
	var fire := Input.get_joy_axis(index, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	var reload := Input.is_joy_button_pressed(index, JOY_BUTTON_X)
	if index == 0:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			fire = true
		if Input.is_physical_key_pressed(KEY_R):
			reload = true
	if reload and ammo < MAG_SIZE and reload_left <= 0.0:
		_start_reload()
	# Пистолет полуавтоматический: один выстрел на одно нажатие.
	if fire and not _fire_was_pressed and fire_cooldown <= 0.0 and reload_left <= 0.0:
		if ammo > 0:
			shoot()
		else:
			Sfx.play_flat(self, "click", -6.0)
			_start_reload()
	_fire_was_pressed = fire


## Выстрел из центра камеры. Возвращает зону попадания или пустую строку.
func shoot() -> String:
	ammo -= 1
	fire_cooldown = FIRE_INTERVAL
	_shake = maxf(_shake, 0.12)
	_kick = 1.0
	_muzzle.light_energy = 6.0
	Sfx.play_flat(self, "shot", -2.0)
	var hit := _aim_ray()
	if hit.is_empty() or not (hit["collider"] is Area3D):
		return ""
	var area: Area3D = hit["collider"]
	if not area.has_meta("zone"):
		return ""
	var zone: String = area.get_meta("zone")
	var zombie = area.get_meta("zombie")
	if not is_instance_valid(zombie):
		return ""
	var dir := -camera.global_transform.basis.z
	if zombie.take_hit(zone, DAMAGE, hit["position"], dir):
		kills += 1
	if hud:
		hud.flash_hit(zone == "head")
	return zone


func _start_reload() -> void:
	reload_left = RELOAD_TIME
	Sfx.play_flat(self, "reload", -4.0)


## Зона тела под прицелом (нужна для aim assist).
func aim_zone() -> String:
	var hit := _aim_ray()
	if hit.is_empty() or not (hit["collider"] is Area3D):
		return ""
	return str(hit["collider"].get_meta("zone", ""))


func _aim_ray() -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK)
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


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


func _update_camera(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta)
	_kick = maxf(0.0, _kick - delta * 8.0)
	_muzzle.light_energy = maxf(0.0, _muzzle.light_energy - delta * 120.0)
	var eye := DOWNED_EYE_HEIGHT if downed else EYE_HEIGHT
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _shake * 0.06
	camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(pitch + _kick * 0.03, yaw, 0.0)),
		global_position + Vector3.UP * eye + jitter)
	_weapon.position = Vector3(0.0, 0.0, _kick * 0.08)
	_weapon.rotation.x = _kick * 0.25


func _build_body() -> void:
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	mesh.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.97, 0.97)
	mesh.material_override = mat
	mesh.position.y = 0.9
	mesh.layers = 1 << (BODY_LAYER_BIT + index)
	add_child(mesh)
	# Номер над головой, чтобы напарник находил игрока в суматохе.
	var label := Label3D.new()
	label.text = str(index + 1)
	label.font_size = 96
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 2.2
	label.layers = 1 << (BODY_LAYER_BIT + index)
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
	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.22, 0.22, 0.22)
	gun_mat.roughness = 0.6
	# Лёгкое свечение, чтобы оружие не терялось в темноте.
	gun_mat.emission_enabled = true
	gun_mat.emission = Color(0.12, 0.12, 0.12)
	_add_gun_block(Vector3(0.06, 0.08, 0.26), Vector3(0.26, -0.25, -0.55), 0.0, gun_mat)
	_add_gun_block(Vector3(0.05, 0.13, 0.07), Vector3(0.26, -0.33, -0.48), 0.25, gun_mat)


func _add_gun_block(size: Vector3, pos: Vector3, tilt: float, mat: Material) -> void:
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
