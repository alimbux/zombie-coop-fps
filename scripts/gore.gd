extends RefCounted
## Кровь и расчленение: брызги, пятна на полу и стенах по направлению выстрела,
## отлетающие части тела с кровавым следом и короткая пауза (hit-stop) на убийстве.

const MAX_STAINS := 300
const MAX_DEBRIS := 80
const WORLD_MASK := 1
const DEBRIS_LAYER := 16

static var _blood_mat: StandardMaterial3D
static var _stain_mesh: CylinderMesh
static var _drop_mesh: BoxMesh
static var _stains: Array = []
static var _debris: Array = []


static func blood_material() -> StandardMaterial3D:
	if _blood_mat == null:
		_blood_mat = StandardMaterial3D.new()
		_blood_mat.albedo_color = Color(0.9, 0.0, 0.03)
		_blood_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _blood_mat


## Небольшое попадание: брызги по направлению пули и пятно на стене за целью.
static func splash(world: Node3D, point: Vector3, dir: Vector3, amount: int) -> void:
	_particles(world, point, dir, amount, 4.0)
	_stain_ray(world, point, point + dir.normalized() * 4.0, randf_range(0.12, 0.3))
	_stain_ray(world, point, point + Vector3.DOWN * 3.0, randf_range(0.1, 0.25))


## Отрыв или смерть: много крови, несколько пятен вокруг.
static func burst(world: Node3D, point: Vector3, dir: Vector3, amount: int) -> void:
	_particles(world, point, dir + Vector3.UP * 0.6, amount, 6.0)
	if dir.normalized().y < 0.7:
		_stain_ray(world, point, point + dir.normalized() * 5.0, randf_range(0.3, 0.6))
	for i in 3:
		var spread := Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		_stain_ray(world, point + spread * 0.5, point + spread + Vector3.DOWN * 3.0, randf_range(0.2, 0.5))


## Превращает часть тела в отдельный физический объект, который отлетает от импульса.
static func detach(world: Node3D, part: MeshInstance3D, impulse: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = DEBRIS_LAYER
	rb.collision_mask = WORLD_MASK | DEBRIS_LAYER
	rb.mass = 2.0
	var copy: MeshInstance3D = part.duplicate()
	for child in copy.get_children():
		if child is Area3D:
			copy.remove_child(child)
			child.free()
	copy.transform = Transform3D.IDENTITY
	rb.add_child(copy)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = (part.mesh as BoxMesh).size
	col.shape = shape
	rb.add_child(col)
	world.add_child(rb)
	rb.global_transform = part.global_transform
	rb.apply_central_impulse(impulse)
	rb.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	_blood_trail(world, rb)
	_track(_debris, rb, MAX_DEBRIS)
	return rb


## Короткое замедление времени на фатальном попадании.
static func hit_stop(tree: SceneTree, duration: float) -> void:
	Engine.time_scale = 0.05
	await tree.create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


static func _particles(world: Node3D, point: Vector3, dir: Vector3, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = maxi(amount, 1)
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.direction = dir.normalized()
	p.spread = 35.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.mesh = _drop()
	world.add_child(p)
	p.global_position = point
	p.emitting = true
	world.get_tree().create_timer(1.5).timeout.connect(p.queue_free)


static func _blood_trail(world: Node3D, rb: RigidBody3D) -> void:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.6
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0, -14, 0)
	p.mesh = _drop()
	rb.add_child(p)
	p.emitting = true
	world.get_tree().create_timer(1.2).timeout.connect(func():
		if is_instance_valid(p):
			p.emitting = false
	)


static func _stain_ray(world: Node3D, from: Vector3, to: Vector3, radius: float) -> void:
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var normal: Vector3 = hit["normal"]
	var stain := MeshInstance3D.new()
	stain.mesh = _stain()
	world.add_child(stain)
	stain.global_transform = Transform3D(_basis_from_up(normal), hit["position"] + normal * 0.006)
	stain.scale = Vector3(radius * randf_range(0.6, 1.6), 1.0, radius * randf_range(0.6, 1.6))
	_track(_stains, stain, MAX_STAINS)


static func _basis_from_up(up: Vector3) -> Basis:
	var y := up.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _stain() -> CylinderMesh:
	if _stain_mesh == null:
		_stain_mesh = CylinderMesh.new()
		_stain_mesh.top_radius = 1.0
		_stain_mesh.bottom_radius = 1.0
		_stain_mesh.height = 0.004
		_stain_mesh.radial_segments = 9
		_stain_mesh.rings = 1
		_stain_mesh.material = blood_material()
	return _stain_mesh


static func _drop() -> BoxMesh:
	if _drop_mesh == null:
		_drop_mesh = BoxMesh.new()
		_drop_mesh.size = Vector3.ONE * 0.05
		_drop_mesh.material = blood_material()
	return _drop_mesh


static func _track(list: Array, node: Node, limit: int) -> void:
	list.append(node)
	while list.size() > limit:
		var old = list.pop_front()
		if is_instance_valid(old):
			old.queue_free()
