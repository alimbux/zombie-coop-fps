extends RefCounted
## Процедурный этаж: комнаты на сетке, двери между соседними, выход в самой дальней
## от старта комнате. Чем выше этаж, тем больше комнат и зомби.
## Зомби стоят по комнатам и не знают об игроках, пока не заметят или не услышат.

const Zombie := preload("res://scripts/zombie.gd")
const Pickup := preload("res://scripts/pickup.gd")

const CELL := 9.0
const HEIGHT := 3.2
const WALL := 0.3
const DOOR := 2.2
const DOOR_HEIGHT := 2.4
const MAX_ZOMBIES := 150
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var rng := RandomNumberGenerator.new()
var cells: Array = []
var links := {}
var start_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
var exit_position := Vector3.ZERO
var distance_from_start := {}
var _next_hop := {}
var _materials := {}


static func room_count(floor_number: int) -> int:
	return mini(5 + 2 * floor_number, 45)


static func zombies_per_room(floor_number: int, players: int) -> float:
	return (2.0 + 0.3 * floor_number) * players * 0.75


## Строит этаж в мире. Возвращает точки старта игроков.
func build(world: Node3D, floor_number: int, players: int, seed_value: int) -> Dictionary:
	rng.seed = seed_value
	_layout(room_count(floor_number))
	_compute_paths()
	var far := 0
	for c in cells:
		if distance_from_start[c] > far:
			far = distance_from_start[c]
			exit_cell = c
	exit_position = center(exit_cell)
	_build_geometry(world)
	_populate(world, floor_number, players)
	var starts: Array = []
	for offset in [Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(-1, 0, -1), Vector3(1, 0, -1)]:
		starts.append(center(start_cell) + offset + Vector3.UP * 0.1)
	return {"player_starts": starts}


func center(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL, 0.0, c.y * CELL)


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / CELL), roundi(pos.z / CELL))


## Куда идти из точки from, чтобы добраться до точки to: в ту же комнату — прямо,
## в другую — к двери в следующую комнату по кратчайшему пути.
func next_waypoint(from: Vector3, to: Vector3) -> Vector3:
	var a := cell_of(from)
	var b := cell_of(to)
	if a == b or not _next_hop.has(b) or not _next_hop[b].has(a):
		return to
	var n: Vector2i = _next_hop[b][a]
	var dir := Vector3(n.x - a.x, 0.0, n.y - a.y)
	var door := (center(a) + center(n)) / 2.0
	# Сначала выйти на линию двери, потом пройти сквозь проём.
	var side := Vector3(dir.z, 0.0, dir.x).abs()
	var off := (from - door) * side
	if off.length() > 0.5 and absf((from - door).dot(dir)) > 1.0:
		return door - dir * 1.0
	return door + dir * 1.0


# --- Планировка -------------------------------------------------------------

func _layout(count: int) -> void:
	cells = [Vector2i.ZERO]
	links = {Vector2i.ZERO: []}
	var guard := 0
	while cells.size() < count and guard < 10000:
		guard += 1
		var from: Vector2i = cells[rng.randi_range(maxi(0, cells.size() - 4), cells.size() - 1)] if rng.randf() < 0.6 else cells[rng.randi() % cells.size()]
		var next: Vector2i = from + DIRS[rng.randi() % 4]
		if links.has(next):
			continue
		cells.append(next)
		links[next] = [from]
		links[from].append(next)
	# Лишние двери дают кольца и пути отступления.
	for c in cells:
		for d in DIRS:
			var nb: Vector2i = c + d
			if links.has(nb) and not links[c].has(nb) and rng.randf() < 0.15:
				links[c].append(nb)
				links[nb].append(c)


func _compute_paths() -> void:
	_next_hop = {}
	for target in cells:
		var hop := {}
		var queue: Array = [target]
		var seen := {target: true}
		var dist := {target: 0}
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			for nb in links[cur]:
				if seen.has(nb):
					continue
				seen[nb] = true
				hop[nb] = cur
				dist[nb] = dist[cur] + 1
				queue.append(nb)
		_next_hop[target] = hop
		if target == start_cell:
			distance_from_start = dist


# --- Геометрия ------------------------------------------------------------

func _build_geometry(world: Node3D) -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color.BLACK
	env.fog_density = 0.045
	env_node.environment = env
	world.add_child(env_node)

	for c in cells:
		var base := center(c)
		_box(world, Vector3(CELL, 0.5, CELL), base + Vector3(0, -0.25, 0), 0.28)
		_box(world, Vector3(CELL, 0.4, CELL), base + Vector3(0, HEIGHT + 0.2, 0), 0.12)
		for d in DIRS:
			var nb: Vector2i = c + d
			var shared := links.has(nb)
			# Общую стену строит только одна из двух комнат.
			if shared and (d.x < 0 or d.y < 0):
				continue
			_wall(world, c, d, links[c].has(nb))
		if c == start_cell or c == exit_cell or rng.randf() < 0.45:
			_lamp(world, base)
		if c != start_cell and c != exit_cell:
			_props(world, base)
	_exit_marker(world)


func _wall(world: Node3D, c: Vector2i, d: Vector2i, door: bool) -> void:
	var mid := center(c) + Vector3(d.x, 0, d.y) * CELL / 2.0 + Vector3.UP * HEIGHT / 2.0
	var along_z := d.x != 0
	var shade := rng.randf_range(0.45, 0.65)
	if not door:
		_box(world, Vector3(WALL, HEIGHT, CELL) if along_z else Vector3(CELL, HEIGHT, WALL), mid, shade)
		return
	var seg := (CELL - DOOR) / 2.0
	var shift := DOOR / 2.0 + seg / 2.0
	for sign in [-1.0, 1.0]:
		var offset := Vector3(0, 0, shift * sign) if along_z else Vector3(shift * sign, 0, 0)
		_box(world, Vector3(WALL, HEIGHT, seg) if along_z else Vector3(seg, HEIGHT, WALL), mid + offset, shade)
	var lintel_h := HEIGHT - DOOR_HEIGHT
	var lintel_pos := Vector3(mid.x, DOOR_HEIGHT + lintel_h / 2.0, mid.z)
	_box(world, Vector3(WALL, lintel_h, DOOR) if along_z else Vector3(DOOR, lintel_h, WALL), lintel_pos, shade)


## Мебель по углам комнаты, чтобы проходы между дверями оставались свободными.
func _props(world: Node3D, base: Vector3) -> void:
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	corners.shuffle()
	var inset := CELL / 2.0 - 1.3
	for i in rng.randi_range(1, 3):
		var p: Vector2 = corners[i] * inset
		var pos := base + Vector3(p.x, 0, p.y)
		match rng.randi() % 3:
			0:
				var s := rng.randf_range(0.9, 1.3)
				_box(world, Vector3(s, s, s), pos + Vector3.UP * s / 2.0, 0.8, rng.randf_range(0, PI))
			1:
				_box(world, Vector3(1.6, 0.9, 0.9), pos + Vector3.UP * 0.45, 0.7, rng.randf_range(-0.3, 0.3))
			2:
				_box(world, Vector3(0.7, 2.1, 1.3), pos + Vector3.UP * 1.05, 0.6, 0.0)


func _lamp(world: Node3D, base: Vector3) -> void:
	var lamp := OmniLight3D.new()
	lamp.omni_range = 8.0
	lamp.light_energy = 1.1
	world.add_child(lamp)
	lamp.position = base + Vector3.UP * (HEIGHT - 0.4)
	var fixture := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6, 0.06, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	fixture.mesh = mesh
	world.add_child(fixture)
	fixture.position = base + Vector3.UP * (HEIGHT - 0.03)


## Выход: светящийся проём лестницы вниз и надпись.
func _exit_marker(world: Node3D) -> void:
	var glow := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.4, 0.04, 2.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 2.5
	mesh.material = mat
	glow.mesh = mesh
	world.add_child(glow)
	glow.position = exit_position + Vector3.UP * 0.02
	var label := Label3D.new()
	label.text = "ВЫХОД"
	label.font_size = 96
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	world.add_child(label)
	label.position = exit_position + Vector3.UP * 2.2
	var light := OmniLight3D.new()
	light.omni_range = 6.0
	light.light_energy = 2.0
	world.add_child(light)
	light.position = exit_position + Vector3.UP * 1.0


# --- Зомби и предметы -------------------------------------------------------

func _populate(world: Node3D, floor_number: int, players: int) -> void:
	var per_room := zombies_per_room(floor_number, players)
	var total := 0
	var rooms := cells.duplicate()
	rooms.shuffle()
	for c in rooms:
		if c == start_cell:
			continue
		var count := int(per_room + rng.randf())
		# Соседние со стартом комнаты спокойнее, чтобы было время осмотреться.
		if distance_from_start[c] == 1:
			count = int(count / 2.0)
		for i in count:
			if total >= MAX_ZOMBIES:
				break
			var z = Zombie.new()
			z.level = self
			z.aware = false
			world.add_child(z)
			var offset := Vector3(rng.randf_range(-2.5, 2.5), 0.1, rng.randf_range(-2.5, 2.5))
			var near: bool = distance_from_start[c] == 1
			if near:
				# У дальней стены, чтобы не заметили игроков в первую же секунду.
				var away := Vector2(c - start_cell).normalized()
				offset += Vector3(away.x, 0, away.y) * 3.0
				offset.x = clampf(offset.x, -3.2, 3.2)
				offset.z = clampf(offset.z, -3.2, 3.2)
			z.global_position = center(c) + offset
			z.rotation.y = rng.randf_range(0, TAU)
			total += 1

	# На первом этаже в стартовой комнате по пистолету на каждого.
	if floor_number == 1:
		for i in players:
			_pickup(world, "weapon", "pistol", center(start_cell) + Vector3(-1.5 + i, 0, -2.0))
	var deeper := clampf((floor_number - 1) / 6.0, 0.0, 1.0)
	# Аптечки редкие: не больше одной на 5 комнат, чтобы лечение было ценным.
	var medkits_left := maxi(1, int(cells.size() / 5.0))
	for c in cells:
		if c == start_cell:
			continue
		var roll := rng.randf()
		var spot := center(c) + Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-2.0, 2.0))
		if roll < 0.5:
			_pickup(world, "ammo", _random_gun(deeper), spot)
		elif roll < 0.68:
			_pickup(world, "weapon", _random_gun(deeper), spot)
		elif roll < 0.8 and medkits_left > 0:
			medkits_left -= 1
			_pickup(world, "medkit", "", spot)


## Чем глубже этаж, тем чаще попадаются автомат и дробовик.
func _random_gun(deeper: float) -> String:
	var r := rng.randf()
	if r < 0.5 - 0.25 * deeper:
		return "pistol"
	if r < 0.78 - 0.1 * deeper:
		return "smg"
	return "shotgun"


func _pickup(world: Node3D, kind: String, weapon: String, pos: Vector3) -> void:
	var p = Pickup.new()
	p.kind = kind
	p.weapon = weapon
	world.add_child(p)
	p.global_position = pos


func _box(world: Node3D, size: Vector3, pos: Vector3, shade: float, rot_y := 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _material(shade)
	body.add_child(mesh_inst)
	world.add_child(body)
	body.position = pos
	body.rotation.y = rot_y


func _material(shade: float) -> StandardMaterial3D:
	var key := snappedf(shade, 0.05)
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(key, key, key)
		mat.roughness = 0.95
		_materials[key] = mat
	return _materials[key]
