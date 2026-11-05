extends RefCounted
## Ночной город из небоскрёбов вокруг этажа, тающий в темноте.
## Башни — по одному MultiMeshInstance3D на оттенок, окна — по одному на яркость,
## без теней и коллизий. Все случайности идут из своего генератора по seed.

const TOWER_COUNT_MIN := 100
const TOWER_COUNT_MAX := 150
## Минимальный зазор между краем этажа и основанием башни.
const GAP := 25.0
## Башни ставятся не дальше этого расстояния от края этажа.
const RING_OUTER := 250.0
const FOOT_MIN := 12.0
const FOOT_MAX := 40.0
const BOTTOM_Y := -400.0
## Мы высоко: большинство крыш ниже этажа, над горизонтом торчат только отдельные башни.
const TOP_MIN := -160.0
const TOP_MAX := 90.0
const BELOW_SHARE := 0.65
const MAX_ATTEMPTS := 60000
const SHADES := [0.05, 0.08, 0.11]
const WINDOW_BRIGHTNESS := [0.35, 0.6, 0.95]
const WINDOW_SIZE := Vector2(1.2, 1.6)
const WINDOW_PITCH_X := 3.0
const WINDOW_PITCH_Y := 3.5
const WINDOW_FIRST_Y := -154.25
const LIT_CHANCE := 0.07
## Зарево над городом: кольцо далеко за башнями, светлее у горизонта. Башни в тумане
## чернеют и проступают на нём силуэтами. Нуар-фильтр поднимает контраст, поэтому
## яркость зарева выше, чем кажется: тёмные тона ниже ~0,12 он уводит в чёрный.
const GLOW_RADIUS := 600.0
const GLOW_PEAK := 0.3
const GLOW_PEAK_Y := -40.0
const GLOW_BOTTOM_Y := -320.0
const GLOW_TOP_Y := 260.0
const MAX_WINDOWS := 6000
const FACE_DOT := 0.25
const ROOF_SLAB_HEIGHT := 1.2
const ANTENNA_MIN := 6.0
const ANTENNA_MAX := 25.0

## Строит город вокруг прямоугольника этажа (bounds_min..bounds_max, XZ) и
## добавляет его в world. Возвращает узел City.
static func build(world: Node3D, bounds_min: Vector3, bounds_max: Vector3, seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bmin := Vector2(bounds_min.x, bounds_min.z)
	var bmax := Vector2(bounds_max.x, bounds_max.z)
	var center := (bmin + bmax) * 0.5

	var towers := _place_towers(rng, bmin, bmax, rng.randi_range(TOWER_COUNT_MIN, TOWER_COUNT_MAX))
	var boxes: Array = [[], [], []]
	var windows: Array = [[], [], []]
	for t in towers:
		_add_boxes(rng, t, boxes)
	var lit := 0
	for t in towers:
		lit = _add_windows(rng, t, center, windows, lit)

	var city := Node3D.new()
	city.name = "City"
	# Данные башен (центр, размеры, поворот) для проверок и отладки.
	city.set_meta("towers", towers)
	for i in SHADES.size():
		if boxes[i].is_empty():
			continue
		city.add_child(_multimesh_node("Towers%d" % i, BoxMesh.new(), boxes[i], _tower_material(SHADES[i])))
	for i in WINDOW_BRIGHTNESS.size():
		if windows[i].is_empty():
			continue
		var quad := QuadMesh.new()
		quad.size = WINDOW_SIZE
		city.add_child(_multimesh_node("Windows%d" % i, quad, windows[i], _window_material(WINDOW_BRIGHTNESS[i])))
	city.add_child(_glow((bmin + bmax) * 0.5))
	world.add_child(city)
	return city


## Кольцо зарева вокруг этажа: вертикальный градиент серого, не тонет в тумане.
static func _glow(center: Vector2) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := [[GLOW_BOTTOM_Y, 0.0], [GLOW_PEAK_Y - 60.0, GLOW_PEAK * 0.6], [GLOW_PEAK_Y, GLOW_PEAK], [GLOW_PEAK_Y + 40.0, GLOW_PEAK * 0.7], [GLOW_PEAK_Y + 110.0, GLOW_PEAK * 0.3], [GLOW_TOP_Y, 0.0]]
	var segments := 48
	for r in rows.size() - 1:
		for k in segments:
			var a0 := TAU * k / segments
			var a1 := TAU * (k + 1) / segments
			var p00 := Vector3(center.x + cos(a0) * GLOW_RADIUS, rows[r][0], center.y + sin(a0) * GLOW_RADIUS)
			var p10 := Vector3(center.x + cos(a1) * GLOW_RADIUS, rows[r][0], center.y + sin(a1) * GLOW_RADIUS)
			var p01 := Vector3(p00.x, rows[r + 1][0], p00.z)
			var p11 := Vector3(p10.x, rows[r + 1][0], p10.z)
			var c0 := Color(rows[r][1], rows[r][1], rows[r][1])
			var c1 := Color(rows[r + 1][1], rows[r + 1][1], rows[r + 1][1])
			for v in [[p00, c0], [p10, c0], [p11, c1], [p00, c0], [p11, c1], [p01, c1]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	var mi := MeshInstance3D.new()
	mi.name = "Glow"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Размещает башни кольцом вокруг этажа. Расстояние от центра башни до прямоугольника
## этажа: не меньше GAP + радиус основания (тогда основание целиком дальше GAP) и не больше RING_OUTER.
static func _place_towers(rng: RandomNumberGenerator, bmin: Vector2, bmax: Vector2, count: int) -> Array:
	var towers: Array = []
	var reach := Vector2(RING_OUTER + FOOT_MAX, RING_OUTER + FOOT_MAX)
	var lo := bmin - reach
	var hi := bmax + reach
	var attempts := 0
	while towers.size() < count and attempts < MAX_ATTEMPTS:
		attempts += 1
		var w := rng.randf_range(FOOT_MIN, FOOT_MAX)
		var d := rng.randf_range(FOOT_MIN, FOOT_MAX)
		var r := Vector2(w, d).length() * 0.5
		var p := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		var dist := _rect_distance(p, bmin, bmax)
		if dist < GAP + r or dist > RING_OUTER:
			continue
		var free := true
		for o in towers:
			if p.distance_to(o["pos"]) < r + o["r"] + 3.0:
				free = false
				break
		if not free:
			continue
		towers.append({
			"pos": p,
			"r": r,
			"w": w,
			"d": d,
			"yaw": rng.randf() * TAU,
			"top": rng.randf_range(TOP_MIN, -10.0) if rng.randf() < BELOW_SHARE else rng.randf_range(0.0, TOP_MAX),
			"shade": rng.randi() % SHADES.size(),
		})
	return towers


static func _dist_from(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)


static func _rect_distance(p: Vector2, bmin: Vector2, bmax: Vector2) -> float:
	var dx := maxf(maxf(bmin.x - p.x, 0.0), p.x - bmax.x)
	var dz := maxf(maxf(bmin.y - p.y, 0.0), p.y - bmax.y)
	return Vector2(dx, dz).length()


## Корпус башни, при необходимости крыша-плита и антенна (только для башен, торчащих над полом).
static func _add_boxes(rng: RandomNumberGenerator, t: Dictionary, boxes: Array) -> void:
	var pos: Vector2 = t["pos"]
	var w: float = t["w"]
	var d: float = t["d"]
	var top: float = t["top"]
	var basis := Basis(Vector3.UP, t["yaw"])
	var height := top - BOTTOM_Y
	boxes[t["shade"]].append(Transform3D(basis.scaled(Vector3(w, height, d)),
			Vector3(pos.x, (top + BOTTOM_Y) * 0.5, pos.y)))
	var roof_y := top
	if top > 0.0 and rng.randf() < 0.3:
		boxes[t["shade"]].append(Transform3D(basis.scaled(Vector3(w * 0.7, ROOF_SLAB_HEIGHT, d * 0.7)),
				Vector3(pos.x, top + ROOF_SLAB_HEIGHT * 0.5, pos.y)))
		roof_y += ROOF_SLAB_HEIGHT
	if top > 0.0 and rng.randf() < 0.25:
		var h := rng.randf_range(ANTENNA_MIN, ANTENNA_MAX)
		boxes[t["shade"]].append(Transform3D(Basis().scaled(Vector3(0.3, h, 0.3)),
				Vector3(pos.x, roof_y + h * 0.5, pos.y)))


## Освещённые окна на гранях, обращённых к этажу. Возвращает новое число освещённых окон.
static func _add_windows(rng: RandomNumberGenerator, t: Dictionary, center: Vector2, windows: Array, lit: int) -> int:
	var pos: Vector2 = t["pos"]
	var w: float = t["w"]
	var d: float = t["d"]
	var top: float = t["top"]
	var rot := Basis(Vector3.UP, t["yaw"])
	var to_center := Vector3(center.x - pos.x, 0.0, center.y - pos.y).normalized()
	var origin := Vector3(pos.x, 0.0, pos.y)
	for ln: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var world_n: Vector3 = rot * ln
		if world_n.dot(to_center) < FACE_DOT:
			continue
		var along_x: bool = ln.x != 0.0
		var face_w: float = d if along_x else w
		var tangent: Vector3 = Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
		var cols := int(floor((face_w - 2.0) / WINDOW_PITCH_X))
		if cols < 1:
			continue
		var y_c := WINDOW_FIRST_Y
		while y_c < top - 1.5:
			for i in cols:
				if lit >= MAX_WINDOWS:
					return lit
				if rng.randf() >= LIT_CHANCE:
					continue
				var tc := (i - (cols - 1) * 0.5) * WINDOW_PITCH_X
				# Дальние окна тусклее: туман на них не действует, гасим вручную.
				var far := clampf(1.15 - _dist_from(center, pos) / 300.0, 0.35, 1.0)
				var bright := rng.randf_range(0.3, 1.0) * far
				var bucket := 0 if bright < 0.5 else (1 if bright < 0.8 else 2)
				var local := Vector3(ln.x * (w * 0.5 + 0.05), y_c, ln.z * (d * 0.5 + 0.05)) + tangent * tc
				windows[bucket].append(Transform3D(Basis.looking_at(-world_n, Vector3.UP), origin + rot * local))
				lit += 1
			y_c += WINDOW_PITCH_Y
	return lit


static func _multimesh_node(node_name: String, mesh: Mesh, transforms: Array, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _tower_material(shade: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(shade, shade, shade)
	mat.roughness = 1.0
	return mat


static func _window_material(brightness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(brightness, brightness, brightness)
	mat.disable_fog = true
	return mat
