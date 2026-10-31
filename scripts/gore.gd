extends RefCounted
## Кровь и расчленение: брызги, пятна на полу и стенах по направлению выстрела,
## отлетающие части тела с кровавым следом и короткая пауза (hit-stop) на убийстве.

const BloodStains := preload("res://scripts/blood_stains.gd")
const MAX_STAINS := 400
const MAX_DEBRIS := 80
const WORLD_MASK := 1
const DEBRIS_LAYER := 16

static var _blood_mat: StandardMaterial3D
static var _brain_mat: StandardMaterial3D
static var _layer := 0
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
	var d := dir.normalized()
	# За целью — потёк, вытянутый по полёту пули; под ней — россыпь капель.
	_stain_ray(world, point, point + d * 4.0, randf_range(0.18, 0.35), "streak", d)
	_stain_ray(world, point, point + Vector3.DOWN * 3.0, randf_range(0.15, 0.3), ["drops", "drops", "splat"].pick_random(), d)


## Отрыв или смерть: много крови, несколько пятен вокруг.
static func burst(world: Node3D, point: Vector3, dir: Vector3, amount: int) -> void:
	_particles(world, point, dir + Vector3.UP * 0.6, amount, 6.0)
	var d := dir.normalized()
	if d.y < 0.7:
		_stain_ray(world, point, point + d * 5.0, randf_range(0.35, 0.65), "splat", d)
	# Под телом лужа, вокруг — кляксы и длинные потёки по направлению удара.
	_stain_ray(world, point, point + Vector3.DOWN * 3.0, randf_range(0.4, 0.7), "pool")
	for i in 3:
		var spread := Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5)) + Vector3(d.x, 0, d.z)
		var kind: String = ["splat", "streak", "drops"].pick_random()
		_stain_ray(world, point + spread * 0.5, point + spread + Vector3.DOWN * 3.0, randf_range(0.2, 0.5), kind, spread)


## Превращает часть тела в отдельный физический объект, который отлетает от импульса.
## Часть — меш или шарнир с несколькими мешами; размер куска берётся из меты hit_size.
static func detach(world: Node3D, part: Node3D, impulse: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = DEBRIS_LAYER
	rb.collision_mask = WORLD_MASK | DEBRIS_LAYER
	rb.mass = 2.0
	var copy: Node3D = part.duplicate()
	_strip(copy)
	copy.transform = Transform3D(Basis.from_scale(part.scale), Vector3.ZERO)
	rb.add_child(copy)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	if part.has_meta("hit_size"):
		shape.size = part.get_meta("hit_size")
	elif part is MeshInstance3D and part.mesh is BoxMesh:
		shape.size = (part.mesh as BoxMesh).size
	else:
		shape.size = Vector3.ONE * 0.2
	col.shape = shape
	col.position = part.get_meta("hit_center", Vector3.ZERO)
	rb.add_child(col)
	world.add_child(rb)
	rb.global_transform = part.global_transform.orthonormalized()
	rb.apply_central_impulse(impulse)
	rb.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	_blood_trail(world, rb)
	_track(_debris, rb, MAX_DEBRIS)
	return rb


## Рана, из которой толчками бьёт кровь: брызги летят из точки на теле и падают на пол.
## local_pos и out — в координатах узла, к которому прикреплена рана.
static func bleed(holder: Node3D, local_pos: Vector3, out: Vector3, seconds: float, strength := 1.0) -> void:
	var p := CPUParticles3D.new()
	p.amount = int(18 * strength)
	p.lifetime = 0.7
	p.local_coords = false
	p.direction = out.normalized()
	p.spread = 20.0
	p.initial_velocity_min = 0.8 * strength
	p.initial_velocity_max = 2.2 * strength
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	p.mesh = _drop()
	p.position = local_pos
	holder.add_child(p)
	p.emitting = true
	# Кровь бьёт толчками, как пульс, и постепенно слабеет.
	var tween := p.create_tween().set_loops(maxi(1, int(seconds / 0.5)))
	tween.tween_property(p, "speed_scale", 1.6, 0.12)
	tween.tween_property(p, "speed_scale", 0.6, 0.38)
	_stop_later(p, seconds)


## Вскрытый череп: серо-розовые мозги наружу, они стекают по лицу и падают комками.
static func brains(head: Node3D, top: Vector3) -> void:
	var mat := brain_material()
	for offset in [Vector3(-0.045, 0.05, 0.0), Vector3(0.045, 0.055, -0.02), Vector3(0.0, 0.07, 0.03), Vector3(0.01, 0.045, -0.06), Vector3(-0.02, 0.03, 0.06)]:
		var lobe := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.06
		s.height = 0.09
		s.radial_segments = 8
		s.rings = 4
		lobe.mesh = s
		lobe.material_override = mat
		lobe.position = top + offset
		head.add_child(lobe)
	var rim := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 0.11
	ring.bottom_radius = 0.12
	ring.height = 0.03
	ring.material = blood_material()
	rim.mesh = ring
	rim.position = top + Vector3.UP * 0.02
	head.add_child(rim)
	# Струйка мозгов по щеке: медленно вытягивается вниз.
	var strand := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.03
	cap.height = 0.22
	strand.mesh = cap
	strand.material_override = mat
	strand.position = top + Vector3(0.08, -0.04, -0.06)
	strand.scale = Vector3(1, 0.15, 1)
	head.add_child(strand)
	var tween := strand.create_tween().set_parallel()
	tween.tween_property(strand, "scale:y", 1.0, 3.0)
	tween.tween_property(strand, "position:y", top.y - 0.13, 3.0)
	# Комки мозгов и кровь капают, пока зомби жив.
	var drip := CPUParticles3D.new()
	drip.amount = 8
	drip.lifetime = 1.0
	drip.local_coords = false
	drip.direction = Vector3(0, -1, -0.4)
	drip.spread = 45.0
	drip.initial_velocity_min = 0.2
	drip.initial_velocity_max = 0.8
	drip.gravity = Vector3(0, -9, 0)
	drip.scale_amount_min = 0.6
	drip.scale_amount_max = 1.4
	var chunk := SphereMesh.new()
	chunk.radius = 0.025
	chunk.height = 0.04
	chunk.radial_segments = 6
	chunk.rings = 3
	chunk.material = mat
	drip.mesh = chunk
	drip.position = top + Vector3(0, -0.02, -0.05)
	head.add_child(drip)
	drip.emitting = true
	bleed(head, top, Vector3(0, 1, -0.3), 6.0, 0.7)


static func brain_material() -> StandardMaterial3D:
	if _brain_mat == null:
		_brain_mat = StandardMaterial3D.new()
		# Слегка розоватые: фильтр оставляет им немного красного, но не как у крови.
		_brain_mat.albedo_color = Color(0.78, 0.5, 0.52)
		_brain_mat.roughness = 0.35
		_brain_mat.emission_enabled = true
		_brain_mat.emission = Color(0.12, 0.05, 0.05)
	return _brain_mat


## Выключает частицы через заданное время. Таймер живёт вместе с частицами,
## поэтому не ломается, если часть тела уже убрана со сцены.
static func _stop_later(p: CPUParticles3D, seconds: float) -> void:
	var t := p.create_tween()
	t.tween_interval(seconds)
	t.tween_property(p, "emitting", false, 0.0)


static func _strip(node: Node) -> void:
	for child in node.get_children():
		if child is Area3D or child is CPUParticles3D:
			node.remove_child(child)
			child.free()
		else:
			_strip(child)


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
	_stop_later(p, 1.2)


## Пятно там, куда луч от from к to упёрся в стену или пол. kind — форма из BloodStains,
## along — направление полёта крови: потёки и мазки вытягиваются вдоль него.
static func _stain_ray(world: Node3D, from: Vector3, to: Vector3, radius: float, kind := "splat", along := Vector3.ZERO) -> MeshInstance3D:
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var normal: Vector3 = hit["normal"]
	var basis := _basis_from_up(normal)
	# Ось Z квадрата — «вниз по текстуре»: разворачиваем её по направлению брызг,
	# на стене без направления кровь стекает вниз, на полу — случайный поворот.
	var flow := along - normal * along.dot(normal)
	if flow.length() < 0.05 and absf(normal.y) < 0.7:
		flow = Vector3.DOWN - normal * Vector3.DOWN.dot(normal)
	var angle := randf_range(0.0, TAU)
	if flow.length() > 0.05:
		var z := basis.z
		angle = atan2(z.cross(flow.normalized()).dot(normal), z.dot(flow.normalized()))
	basis = basis.rotated(normal, angle)
	var stain := MeshInstance3D.new()
	stain.mesh = BloodStains.mesh()
	stain.material_override = BloodStains.material(kind)
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(stain)
	# Каждое следующее пятно чуть выше прежних, чтобы наложенные не мерцали.
	_layer = (_layer + 1) % 40
	stain.global_transform = Transform3D(basis, hit["position"] + normal * (0.004 + _layer * 0.0002))
	var stretch := 1.0
	match kind:
		"streak":
			stretch = randf_range(1.6, 2.6)
		"smear":
			stretch = randf_range(1.2, 1.8)
	var w := radius * randf_range(0.8, 1.25)
	stain.scale = Vector3(w, 1.0, w * stretch * randf_range(0.9, 1.15))
	_track(_stains, stain, MAX_STAINS)
	return stain


## Пятно на полу под точкой (капли с ран, след ползущего).
static func floor_stain(world: Node3D, point: Vector3, kind: String, radius: float, along := Vector3.ZERO) -> MeshInstance3D:
	return _stain_ray(world, point + Vector3.UP * 0.3, point + Vector3.DOWN * 2.0, radius, kind, along)


static func _basis_from_up(up: Vector3) -> Basis:
	var y := up.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


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
