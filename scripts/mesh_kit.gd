extends RefCounted
## Простые меши для фигур людей и зомби: капсулы, сферы, усечённые цилиндры, коробки.
## Меши одного размера переиспользуются, чтобы сотня зомби не плодила сотни копий.

static var _cache := {}
static var _materials := {}


## Матовый материал заданной яркости (мир чёрно-белый, цвет только у крови).
static func shade(value: float, roughness := 1.0) -> StandardMaterial3D:
	var key := "%.2f/%.2f" % [value, roughness]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(value, value, value)
		m.roughness = roughness
		_materials[key] = m
	return _materials[key]


static func capsule(radius: float, height: float) -> Mesh:
	var key := "c%.3f/%.3f" % [radius, height]
	if not _cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = maxf(height, radius * 2.0)
		m.radial_segments = 8
		m.rings = 2
		_cache[key] = m
	return _cache[key]


static func sphere(radius: float) -> Mesh:
	var key := "s%.3f" % radius
	if not _cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 10
		m.rings = 6
		_cache[key] = m
	return _cache[key]


static func cylinder(top: float, bottom: float, height: float) -> Mesh:
	var key := "y%.3f/%.3f/%.3f" % [top, bottom, height]
	if not _cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = 10
		m.rings = 1
		_cache[key] = m
	return _cache[key]


static func box(size: Vector3) -> Mesh:
	var key := "b%.3f/%.3f/%.3f" % [size.x, size.y, size.z]
	if not _cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_cache[key] = m
	return _cache[key]


## Добавляет меш в узел. scale задаёт вытягивание (например, сплюснутая грудь).
static func add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	parent.add_child(mi)
	return mi


## Шарнир (плечо, бедро, шея): узел, вокруг которого вращается часть тела.
static func joint(parent: Node3D, pos: Vector3, name := "") -> Node3D:
	var j := Node3D.new()
	if name != "":
		j.name = name
	j.position = pos
	parent.add_child(j)
	return j


## Ставит слой видимости всем мешам внутри узла (свой персонаж не виден своей камере).
static func set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		node.layers = layers
	for c in node.get_children():
		set_layers(c, layers)
