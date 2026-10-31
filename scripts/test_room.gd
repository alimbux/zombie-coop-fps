extends RefCounted
## Тестовая комната для прототипа: тёмный зал 24×24 м с колоннами, ящиками и редкими лампами.
## Позже её место займёт процедурный генератор этажей.

const SIZE := 24.0
const HEIGHT := 3.5


static func build(world: Node3D) -> Dictionary:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.06
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color.BLACK
	env.fog_density = 0.04
	env_node.environment = env
	world.add_child(env_node)

	var half := SIZE / 2.0
	_box(world, Vector3(SIZE, 1.0, SIZE), Vector3(0, -0.5, 0), 0.3)
	_box(world, Vector3(SIZE, 0.5, SIZE), Vector3(0, HEIGHT + 0.25, 0), 0.15)
	_box(world, Vector3(SIZE, HEIGHT, 0.5), Vector3(0, HEIGHT / 2.0, -half), 0.55)
	_box(world, Vector3(SIZE, HEIGHT, 0.5), Vector3(0, HEIGHT / 2.0, half), 0.55)
	_box(world, Vector3(0.5, HEIGHT, SIZE), Vector3(-half, HEIGHT / 2.0, 0), 0.55)
	_box(world, Vector3(0.5, HEIGHT, SIZE), Vector3(half, HEIGHT / 2.0, 0), 0.55)

	for p in [Vector2(-6, -6), Vector2(6, -6), Vector2(-6, 6), Vector2(6, 6)]:
		_box(world, Vector3(1.0, HEIGHT, 1.0), Vector3(p.x, HEIGHT / 2.0, p.y), 0.7)
	for p in [Vector2(-2, 3), Vector2(3, -1), Vector2(-8, 1), Vector2(8, -3), Vector2(0, -7)]:
		_box(world, Vector3(1.2, 1.2, 1.2), Vector3(p.x, 0.6, p.y), 0.8, randf_range(0.0, PI))

	for p in [Vector3(0, HEIGHT - 0.3, 0), Vector3(-8, HEIGHT - 0.3, 8), Vector3(8, HEIGHT - 0.3, -8)]:
		var lamp := OmniLight3D.new()
		lamp.omni_range = 9.0
		lamp.light_energy = 1.2
		lamp.shadow_enabled = true
		world.add_child(lamp)
		lamp.position = p
		var fixture := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.6, 0.08, 0.6)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.WHITE
		mat.emission_enabled = true
		mat.emission = Color.WHITE
		mat.emission_energy_multiplier = 3.0
		mesh.material = mat
		fixture.mesh = mesh
		world.add_child(fixture)
		fixture.position = p + Vector3.UP * 0.25

	return {
		"player_starts": [Vector3(-1, 0.1, 8), Vector3(1, 0.1, 8), Vector3(-3, 0.1, 8), Vector3(3, 0.1, 8)],
		"zombie_spawns": [Vector3(-10, 0.1, -10), Vector3(10, 0.1, -10), Vector3(-10, 0.1, -2), Vector3(10, 0.1, -2)],
	}


static func _box(world: Node3D, size: Vector3, pos: Vector3, shade: float, rot_y := 0.0) -> void:
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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(shade, shade, shade)
	mat.roughness = 0.95
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)
	world.add_child(body)
	body.position = pos
	body.rotation.y = rot_y
