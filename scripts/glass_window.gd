extends Node3D
## Окно во всю наружную стену этажа: тёмная рама и 2–4 стеклянные секции.
## Пуля трескает стекло (трещина остаётся на месте попадания), после нескольких попаданий
## секция разлетается осколками, и в проём можно пройти. Нож и удар ногой стекло не бьют.
## Локальные оси окна: X — вдоль стены, Z — наружу из здания.

signal broken(section)

const Sfx := preload("res://scripts/sfx.gd")

const CELL := 9.0
const HEIGHT := 3.2
const FRAME_DEPTH := 0.24
const FRAME_BAR := 0.08
const GLASS_THICKNESS := 0.04
const SECTION_HP := 60.0
const MIN_SHARDS := 20
const MAX_SHARDS := 30
## Полоса за разбитой секцией, где тело, перешагнувшее плоскость стекла, падает вниз.
const FALL_DEPTH := 1.5

static var _glass_mat: StandardMaterial3D
static var _frame_mat: StandardMaterial3D
static var _crack_mat: StandardMaterial3D
static var _sheen: ImageTexture

## Куда смотрит окно (шаг по сетке от комнаты к улице).
var dir := Vector2i(0, 1)
## Наружу из здания.
var outward := Vector3.BACK
var sections: Array = []
## Зоны падения за разбитыми секциями.
var _fall_zones: Array = []


## Секция стекла: сама служит телом для пуль (слой 1) и кладёт на себя трещины и кровь.
class Section extends StaticBody3D:
	var window
	var hp := 60.0
	var broken := false
	var width := 1.0
	var height := 1.0
	var outward := Vector3.BACK
	## Центр секции в мире.
	var center: Vector3:
		get:
			return global_position
	var glass_mesh: MeshInstance3D
	var shape: CollisionShape3D

	## Попадание пули: трещина, а когда прочность кончилась — осколки.
	func hit(damage: float, point: Vector3, hit_dir: Vector3) -> void:
		if broken:
			return
		hp -= damage
		window.on_section_hit(self, point, hit_dir)


## Строит окно в направлении d (до добавления в мир).
func setup(d: Vector2i) -> void:
	dir = d
	outward = Vector3(d.x, 0.0, d.y)
	rotation.y = atan2(d.x, d.y)
	var count: int = [2, 3, 4].pick_random()
	var inner_w := CELL - FRAME_BAR * (count + 1)
	var sw := inner_w / count
	var sh := HEIGHT - FRAME_BAR * 2.0
	var frame := StaticBody3D.new()
	frame.collision_layer = 1
	frame.collision_mask = 0
	add_child(frame)
	# Нижняя планка только для вида: в разбитый проём можно выпасть, не цепляясь за неё.
	_bar(frame, Vector3(CELL, FRAME_BAR, FRAME_DEPTH), Vector3(0, -HEIGHT / 2.0 + FRAME_BAR / 2.0, 0), false)
	_bar(frame, Vector3(CELL, FRAME_BAR, FRAME_DEPTH), Vector3(0, HEIGHT / 2.0 - FRAME_BAR / 2.0, 0))
	for i in count + 1:
		var x := -CELL / 2.0 + FRAME_BAR / 2.0 + i * (sw + FRAME_BAR)
		_bar(frame, Vector3(FRAME_BAR, sh, FRAME_DEPTH), Vector3(x, 0, 0))
	for i in count:
		var x := -CELL / 2.0 + FRAME_BAR + sw / 2.0 + i * (sw + FRAME_BAR)
		sections.append(_section(Vector3(x, 0, 0), sw, sh))


func _bar(frame: StaticBody3D, size: Vector3, pos: Vector3, solid := true) -> void:
	if solid:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.position = pos
		frame.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _frame_material()
	mi.position = pos
	frame.add_child(mi)


func _section(pos: Vector3, sw: float, sh: float) -> Section:
	var s := Section.new()
	s.window = self
	s.hp = SECTION_HP
	s.width = sw
	s.height = sh
	s.outward = outward
	s.collision_layer = 1
	s.collision_mask = 0
	s.set_meta("glass_section", s)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(sw, sh, GLASS_THICKNESS)
	col.shape = shape
	s.add_child(col)
	s.shape = col
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(sw, sh)
	mi.mesh = quad
	mi.material_override = _glass_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(mi)
	s.glass_mesh = mi
	s.position = pos
	add_child(s)
	return s


# --- Попадания --------------------------------------------------------------

func on_section_hit(s: Section, point: Vector3, hit_dir: Vector3) -> void:
	if s.hp <= 0.0:
		_shatter(s, point, hit_dir)
		return
	_add_crack(s, s.to_local(point))
	Sfx.play_at(get_parent() if get_parent() else self, "glass_crack", point, -2.0)


func _shatter(s: Section, point: Vector3, hit_dir: Vector3) -> void:
	s.broken = true
	s.collision_layer = 0
	s.shape.set_deferred("disabled", true)
	s.glass_mesh.visible = false
	# Трещины и пятна крови, прилипшие к стеклу, исчезают вместе с ним.
	for child in s.get_children():
		if child != s.glass_mesh and child != s.shape:
			child.queue_free()
	var world := get_parent() if get_parent() else self
	_spawn_shards(world, s, point, hit_dir)
	_stubs(s)
	Sfx.play_at(world, "glass_break", point, 2.0)
	_add_fall_zone(s)
	broken.emit(s)


## Зона сразу за плоскостью разбитой секции. Тело, чей центр перешёл плоскость,
## вылетает наружу: у него вызывается fall_out(outward).
func _add_fall_zone(s: Section) -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2 | 8
	area.monitorable = false
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(s.width - 0.1, 0.1), s.height, FALL_DEPTH)
	col.shape = shape
	area.add_child(col)
	area.position = Vector3(s.position.x, s.position.y, FALL_DEPTH / 2.0)
	add_child(area)
	area.body_entered.connect(_check_fall)
	_fall_zones.append(area)
	set_physics_process(true)


func _ready() -> void:
	set_physics_process(false)


## Пока в зоне есть тело, смотрим, не перешёл ли его центр плоскость стекла.
func _physics_process(_delta: float) -> void:
	for area in _fall_zones:
		for body in area.get_overlapping_bodies():
			_check_fall(body)


func _check_fall(body: Node3D) -> void:
	if not is_instance_valid(body) or not body.has_method("fall_out"):
		return
	if (body.global_position - global_position).dot(outward) > 0.0:
		body.fall_out(outward)


func _spawn_shards(world: Node, s: Section, point: Vector3, hit_dir: Vector3) -> void:
	var push := hit_dir.normalized()
	for i in randi_range(MIN_SHARDS, MAX_SHARDS):
		var size := randf_range(0.05, 0.35)
		var local := Vector3(randf_range(-s.width / 2.0, s.width / 2.0) * 0.95, randf_range(-s.height / 2.0, s.height / 2.0) * 0.95, 0.0)
		var rb := RigidBody3D.new()
		# Осколки не попадают в лучи игрока и не мешают телам, только падают на пол.
		rb.collision_layer = 0
		rb.collision_mask = 1
		rb.mass = 0.2
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(size * 0.6, 0.02, size * 0.6)
		col.shape = shape
		rb.add_child(col)
		var mi := MeshInstance3D.new()
		mi.mesh = _triangle(size, randf_range(0.4, 1.0), randf_range(0.2, 0.8))
		mi.material_override = _glass_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(mi)
		world.add_child(rb)
		rb.global_position = s.to_global(local)
		rb.rotation = Vector3(randf_range(-0.6, 0.6), randf_range(0, TAU), randf_range(-0.6, 0.6))
		rb.linear_velocity = push * randf_range(1.0, 4.0) + Vector3(randf_range(-1.2, 1.2), randf_range(-0.2, 1.4), randf_range(-1.2, 1.2))
		rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		var tween := rb.create_tween()
		tween.tween_interval(randf_range(4.0, 6.0))
		tween.tween_callback(rb.queue_free)


## Острые обломки, торчащие из нижней и верхней планки (только для вида, без столкновений).
func _stubs(s: Section) -> void:
	for i in randi_range(3, 6):
		var up := i % 2 == 0
		var size := randf_range(0.06, 0.2)
		var mi := MeshInstance3D.new()
		mi.mesh = _triangle(size, randf_range(0.5, 1.0), randf_range(0.1, 0.9))
		mi.material_override = _glass_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var x := s.position.x + randf_range(-s.width / 2.0, s.width / 2.0) * 0.95
		var y := -s.height / 2.0 if up else s.height / 2.0
		mi.position = Vector3(x, y, randf_range(-0.01, 0.01))
		# Основание на планке, остриё вверх (у верхней планки — вниз).
		mi.rotation = Vector3(0, 0, randf_range(-0.3, 0.3) + (0.0 if up else PI))
		add_child(mi)


## Плоский треугольник с основанием по X: острый осколок.
func _triangle(size: float, height_k: float, tip_k: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	st.add_vertex(Vector3(-size / 2.0, 0, 0))
	st.add_vertex(Vector3(size / 2.0, 0, 0))
	st.add_vertex(Vector3((tip_k - 0.5) * size, size * height_k, 0))
	return st.commit()


# --- Трещины ----------------------------------------------------------------

## Паутина трещин вокруг точки попадания: тёмная дырка, лучи и два неровных кольца.
func _add_crack(s: Section, at: Vector3) -> void:
	var hx := s.width / 2.0 - 0.01
	var hy := s.height / 2.0 - 0.01
	var c := Vector2(clampf(at.x, -hx, hx), clampf(at.y, -hy, hy))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hole := Color(0.03, 0.03, 0.03)
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		_tri(st, c, c + Vector2(cos(a0), sin(a0)) * 0.022, c + Vector2(cos(a1), sin(a1)) * 0.022, hole)
	var rays := randi_range(8, 11)
	var base := randf_range(0, TAU)
	var lengths: Array = []
	var angles: Array = []
	for k in rays:
		var a := base + TAU * k / rays + randf_range(-0.2, 0.2)
		var d := Vector2(cos(a), sin(a))
		var length := randf_range(0.3, 0.7)
		# Луч не выходит за край секции.
		if absf(d.x) > 0.001:
			length = minf(length, (hx - signf(d.x) * c.x) / absf(d.x))
		if absf(d.y) > 0.001:
			length = minf(length, (hy - signf(d.y) * c.y) / absf(d.y))
		length = maxf(length, 0.02)
		angles.append(d)
		lengths.append(length)
		_line(st, c + d * 0.02, c + d * length, 0.007, Color(0.92, 0.92, 0.92))
	for ring_r in [randf_range(0.07, 0.1), randf_range(0.16, 0.22)]:
		for k in rays:
			var k2 := (k + 1) % rays
			if lengths[k] < ring_r or lengths[k2] < ring_r:
				continue
			var p0: Vector2 = c + angles[k] * ring_r * randf_range(0.9, 1.1)
			var p1: Vector2 = c + angles[k2] * ring_r * randf_range(0.9, 1.1)
			_line(st, p0, p1, 0.005, Color(0.78, 0.78, 0.78))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _crack_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Чуть впереди стекла; материал двусторонний, поэтому видно с обеих сторон.
	mi.position = Vector3(0, 0, 0.006 + 0.0004 * (s.get_child_count() % 20))
	s.add_child(mi)


func _tri(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(Vector3(a.x, a.y, 0))
	st.set_color(color)
	st.add_vertex(Vector3(b.x, b.y, 0))
	st.set_color(color)
	st.add_vertex(Vector3(c.x, c.y, 0))


func _line(st: SurfaceTool, a: Vector2, b: Vector2, w: float, color: Color) -> void:
	var side := (b - a).orthogonal().normalized() * w * 0.5
	_tri(st, a - side, a + side, b + side, color)
	_tri(st, a - side, b + side, b - side, color)


# --- Материалы --------------------------------------------------------------

static func _glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.albedo_color = Color(0.7, 0.7, 0.7, 1.0)
		# Косые блики делают стекло заметным: без них оно сливается с тёмным городом.
		_glass_mat.albedo_texture = _sheen_texture()
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.roughness = 0.05
		_glass_mat.metallic = 0.3
		_glass_mat.metallic_specular = 1.0
		_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass_mat


## Прозрачная текстура с мягкими косыми полосами отражения разной ширины.
static func _sheen_texture() -> ImageTexture:
	if _sheen == null:
		var size := 128
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var bands := [[0.18, 0.05, 0.22], [0.3, 0.015, 0.16], [0.62, 0.09, 0.14], [0.8, 0.02, 0.2]]
		for y in size:
			for x in size:
				var t := fposmod((x + y * 0.6) / float(size), 1.0)
				var a := 0.07
				for b in bands:
					var d: float = absf(t - b[0]) / b[1]
					a += b[2] * exp(-d * d)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 0.4)))
		_sheen = ImageTexture.create_from_image(img)
	return _sheen


static func _frame_material() -> StandardMaterial3D:
	if _frame_mat == null:
		_frame_mat = StandardMaterial3D.new()
		_frame_mat.albedo_color = Color(0.17, 0.17, 0.17)
		_frame_mat.roughness = 0.7
		_frame_mat.metallic = 0.4
	return _frame_mat


static func _crack_material() -> StandardMaterial3D:
	if _crack_mat == null:
		_crack_mat = StandardMaterial3D.new()
		_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_crack_mat.vertex_color_use_as_albedo = true
		_crack_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _crack_mat
