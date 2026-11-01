extends Node3D
## Фигура игрока, которую видят напарники. У каждого из четырёх свой силуэт,
## чтобы различать их в чёрно-белом мире без цвета:
## 1 — светлая куртка, кепка и рюкзак; 2 — тёмное длинное пальто и светлый хвост волос;
## 3 — широкий, в каске и жилете со светоотражающими полосами, с бородой;
## 4 — высокий, в капюшоне и с тёмной повязкой на лице.

const Kit := preload("res://scripts/mesh_kit.gd")

const STYLES := [
	{"width": 1.0, "height": 1.0, "top": 0.86, "pants": 0.2, "shoes": 0.95, "skin": 0.78},
	{"width": 0.92, "height": 0.98, "top": 0.12, "pants": 0.62, "shoes": 0.1, "skin": 0.82},
	{"width": 1.2, "height": 1.0, "top": 0.3, "pants": 0.45, "shoes": 0.08, "skin": 0.7},
	{"width": 0.95, "height": 1.06, "top": 0.52, "pants": 0.85, "shoes": 0.15, "skin": 0.76},
]

var style := 0
var _legs: Array = []
var _arms: Array = []
var _torso: Node3D
var _head: Node3D
var _gun: Node3D
var _phase := 0.0
var _down := 0.0


## Собирает фигуру. layers — слой видимости (своя камера его не рисует).
func build(index: int, layers: int) -> void:
	style = index % STYLES.size()
	var st: Dictionary = STYLES[style]
	var w: float = st["width"]
	scale = Vector3.ONE * float(st["height"])
	var top := lit(st["top"])
	var pants := lit(st["pants"])
	var skin := lit(st["skin"])
	var shoes := lit(st["shoes"])
	var dark := lit(0.06)

	for x in [-0.11 * w, 0.11 * w]:
		var leg := Kit.joint(self, Vector3(x, 0.9, 0))
		Kit.add(leg, Kit.capsule(0.08 * w, 0.48), pants, Vector3(0, -0.22, 0))
		Kit.add(leg, Kit.capsule(0.07 * w, 0.46), pants, Vector3(0, -0.64, 0))
		Kit.add(leg, Kit.box(Vector3(0.11, 0.08, 0.26)), shoes, Vector3(0, -0.87, -0.05))
		_legs.append(leg)

	_torso = Kit.joint(self, Vector3(0, 0.9, 0))
	Kit.add(_torso, Kit.cylinder(0.17 * w, 0.16 * w, 0.2), pants, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 1, 0.75))
	Kit.add(_torso, Kit.cylinder(0.21 * w, 0.17 * w, 0.52), top, Vector3(0, 0.33, 0), Vector3.ZERO, Vector3(1, 1, 0.72))
	Kit.add(_torso, Kit.capsule(0.08, 0.5 * w), top, Vector3(0, 0.56, 0), Vector3(0, 0, PI / 2))
	Kit.add(_torso, Kit.cylinder(0.05, 0.06, 0.12), skin, Vector3(0, 0.63, 0))

	_head = Kit.joint(_torso, Vector3(0, 0.64, 0))
	Kit.add(_head, Kit.sphere(0.12), skin, Vector3(0, 0.13, 0), Vector3.ZERO, Vector3(0.9, 1.05, 1.0))
	Kit.add(_head, Kit.box(Vector3(0.03, 0.05, 0.03)), skin, Vector3(0, 0.12, -0.12))
	for x in [-0.045, 0.045]:
		Kit.add(_head, Kit.sphere(0.017), dark, Vector3(x, 0.16, -0.103))
		Kit.add(_head, Kit.box(Vector3(0.02, 0.05, 0.035)), skin, Vector3(x * 2.4, 0.13, 0.0))

	for side in [-1.0, 1.0]:
		var arm := Kit.joint(_torso, Vector3(0.25 * w * side, 0.54, 0))
		Kit.add(arm, Kit.capsule(0.062 * w, 0.32), top, Vector3(0, -0.15, 0))
		Kit.add(arm, Kit.capsule(0.055 * w, 0.3), top, Vector3(0, -0.42, 0))
		Kit.add(arm, Kit.box(Vector3(0.07, 0.09, 0.05)), skin, Vector3(0, -0.6, 0))
		_arms.append(arm)

	# Фонарь на плече горит у живых: игрока видно в темноте издалека, зомби — нет.
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color.WHITE
	lamp.emission_enabled = true
	lamp.emission = Color.WHITE
	lamp.emission_energy_multiplier = 4.0
	Kit.add(_torso, Kit.cylinder(0.035, 0.035, 0.07), lit(0.1), Vector3(0.2 * w, 0.6, -0.1), Vector3(PI / 2, 0, 0))
	Kit.add(_torso, Kit.cylinder(0.03, 0.03, 0.01), lamp, Vector3(0.2 * w, 0.6, -0.14), Vector3(PI / 2, 0, 0))
	var glow := OmniLight3D.new()
	glow.omni_range = 1.4
	glow.light_energy = 0.5
	glow.position = Vector3(0.2 * w, 0.6, -0.3)
	_torso.add_child(glow)

	_gun = Node3D.new()
	_torso.add_child(_gun)
	_add_style_details(w, st)
	set_weapon("knife")
	Kit.set_layers(self, layers)


func _add_style_details(w: float, st: Dictionary) -> void:
	var dark := lit(0.08)
	var light := lit(0.96)
	match style:
		0:
			# Кепка козырьком вперёд и рюкзак.
			Kit.add(_head, Kit.sphere(0.125), dark, Vector3(0, 0.19, 0.0), Vector3.ZERO, Vector3(0.95, 0.55, 1.0))
			Kit.add(_head, Kit.box(Vector3(0.2, 0.02, 0.12)), dark, Vector3(0, 0.2, -0.15), Vector3(-0.1, 0, 0))
			Kit.add(_torso, Kit.box(Vector3(0.32, 0.38, 0.16)), lit(0.3), Vector3(0, 0.36, 0.2))
			Kit.add(_torso, Kit.box(Vector3(0.26, 0.14, 0.06)), lit(0.3), Vector3(0, 0.22, 0.3))
		1:
			# Длинное пальто до колен и светлый хвост волос.
			Kit.add(_torso, Kit.cylinder(0.2, 0.26, 0.5), lit(st["top"]), Vector3(0, -0.2, 0), Vector3.ZERO, Vector3(1, 1, 0.75))
			Kit.add(_torso, Kit.box(Vector3(0.04, 0.5, 0.02)), lit(0.4), Vector3(0, 0.2, -0.13))
			Kit.add(_head, Kit.sphere(0.128), light, Vector3(0, 0.17, 0.015), Vector3.ZERO, Vector3(0.95, 0.85, 1.0))
			Kit.add(_head, Kit.capsule(0.045, 0.3), light, Vector3(0, 0.02, 0.15), Vector3(0.3, 0, 0))
		2:
			# Каска с полями, жилет с полосами, борода.
			Kit.add(_head, Kit.sphere(0.135), light, Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1, 0.7, 1.05))
			Kit.add(_head, Kit.cylinder(0.17, 0.17, 0.02), light, Vector3(0, 0.17, 0))
			Kit.add(_head, Kit.box(Vector3(0.17, 0.1, 0.08)), dark, Vector3(0, 0.05, -0.08))
			for y in [0.22, 0.38]:
				Kit.add(_torso, Kit.cylinder(0.205 * w, 0.195 * w, 0.04), light, Vector3(0, y, 0), Vector3.ZERO, Vector3(1.02, 1, 0.74))
		3:
			# Капюшон и тёмная повязка на лице.
			Kit.add(_head, Kit.sphere(0.15), lit(0.3), Vector3(0, 0.15, 0.055), Vector3.ZERO, Vector3(1.0, 1.05, 1.0))
			Kit.add(_torso, Kit.sphere(0.14), lit(0.3), Vector3(0, 0.6, 0.1), Vector3.ZERO, Vector3(1.2, 0.6, 0.8))
			Kit.add(_head, Kit.box(Vector3(0.2, 0.08, 0.1)), dark, Vector3(0, 0.07, -0.07))
			Kit.add(_torso, Kit.box(Vector3(0.2, 0.12, 0.05)), lit(0.35), Vector3(0, 0.2, -0.14))


## Материал живого человека: чистый тон и лёгкое свечение, чтобы персонаж не сливался
## с серыми гниющими зомби даже в тёмной комнате.
static var _lit := {}

static func lit(value: float) -> StandardMaterial3D:
	var key := snappedf(value, 0.01)
	if not _lit.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(value, value, value)
		m.roughness = 0.7
		m.emission_enabled = true
		m.emission = Color(value, value, value) * 0.25 + Color(0.04, 0.04, 0.04)
		_lit[key] = m
	return _lit[key]


## Оружие в руках, видимое напарникам.
func set_weapon(weapon: String) -> void:
	if _gun == null:
		return
	for c in _gun.get_children():
		c.queue_free()
	var mat := Kit.shade(0.12, 0.5)
	var length: float = {"knife": 0.0, "pistol": 0.2, "smg": 0.45, "shotgun": 0.75}.get(weapon, 0.2)
	if length > 0.0:
		Kit.add(_gun, Kit.box(Vector3(0.06, 0.09, length)), mat, Vector3(0.14, 0.44, -0.45 - length * 0.3))
	if is_inside_tree():
		Kit.set_layers(_gun, _layers_of_body())


func _layers_of_body() -> int:
	for c in _torso.get_children():
		if c is VisualInstance3D:
			return c.layers
	return 1


## Ходьба, прицеливание и падение. speed — горизонтальная скорость, pitch — наклон взгляда.
## reload — доля пройденной перезарядки (0..1) или -1: оружие опускается и наклоняется,
## левая рука уходит к магазину.
func animate(delta: float, speed: float, pitch: float, downed: bool, reload := -1.0) -> void:
	_phase += delta * speed * 2.2
	var stride := clampf(speed / 4.5, 0.0, 1.0)
	var s := sin(_phase)
	for i in _legs.size():
		_legs[i].rotation.x = s * 0.55 * stride * (1.0 if i == 0 else -1.0)
	# Обе руки держат оружие перед собой и следуют за взглядом.
	var aim := 1.35 + pitch * 0.8
	_arms[0].rotation = Vector3(aim - 0.05, 0, 0.42)
	_arms[1].rotation = Vector3(aim, 0, -0.08)
	_head.rotation.x = pitch * 0.6
	_gun.rotation = Vector3(pitch * 0.8, 0, 0)
	if reload >= 0.0:
		var w := sin(reload * PI)
		_gun.rotation += Vector3(-0.5, 0, 0.6) * w
		_arms[0].rotation = Vector3(aim - 0.05 - 0.8 * w, 0, 0.42 - 0.3 * w + sin(reload * 18.0) * 0.08 * w)
		_head.rotation.x -= 0.35 * w
	_torso.rotation.x = -0.05 - stride * 0.08
	_down = move_toward(_down, 1.0 if downed else 0.0, delta * 3.0)
	rotation.x = _down * 1.45
	position.y = absf(s) * 0.04 * stride + _down * 0.2
