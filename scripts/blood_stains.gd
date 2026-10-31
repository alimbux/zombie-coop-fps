extends RefCounted
## Формы кровавых пятен. Рисуются один раз при первом использовании в маленькие текстуры
## с прозрачностью и кладутся на пол и стены плоскими квадратами:
##   splat — клякса с рваным краем, лучами и брызгами вокруг;
##   streak — вытянутый потёк с каплями по направлению выстрела;
##   drops — россыпь капель разного размера;
##   pool — большая неровная лужа;
##   smear — размазанный след (ползущий зомби, тело, которое протащило по полу).

const SIZE := 128
const VARIANTS := 3
const KINDS := ["splat", "streak", "drops", "pool", "smear"]

## Свежая кровь яркая, подсохшая темнее: фильтр оставляет оба тона красными.
const TONES := [Color(0.9, 0.0, 0.03), Color(0.62, 0.0, 0.02), Color(0.45, 0.0, 0.015)]

static var _materials := {}
static var _mesh: PlaneMesh


## Квадрат 2×2 м, который масштабируется до нужного размера пятна.
static func mesh() -> PlaneMesh:
	if _mesh == null:
		_mesh = PlaneMesh.new()
		_mesh.size = Vector2(2.0, 2.0)
	return _mesh


## Случайный материал пятна данного вида.
static func material(kind: String) -> StandardMaterial3D:
	var key := "%s/%d/%d" % [kind, randi() % VARIANTS, randi() % TONES.size()]
	if not _materials.has(key):
		var parts := key.split("/")
		var m := StandardMaterial3D.new()
		m.albedo_color = TONES[int(parts[2])]
		m.albedo_texture = _texture(kind, int(parts[1]))
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]


static var _textures := {}


static func _texture(kind: String, variant: int) -> ImageTexture:
	var key := "%s%d" % [kind, variant]
	if _textures.has(key):
		return _textures[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var mask := PackedByteArray()
	mask.resize(SIZE * SIZE)
	match kind:
		"splat":
			_blob(mask, rng, Vector2.ZERO, 0.42, 0.18, 7)
			for i in rng.randi_range(4, 8):
				_ray(mask, rng, rng.randf_range(0, TAU), 0.35, rng.randf_range(0.7, 0.95), rng.randf_range(0.03, 0.06))
			_satellites(mask, rng, rng.randi_range(8, 16), 0.55, 0.97, 0.015, 0.06)
		"streak":
			# Капля-«головастик»: толстое начало, хвост и брызги вдоль направления (+Y текстуры).
			var y := -0.75
			var r := 0.22
			while y < 0.9 and r > 0.012:
				_disc(mask, Vector2(rng.randf_range(-0.03, 0.03), y), r)
				y += r * 0.6
				r *= rng.randf_range(0.86, 0.95)
			for i in rng.randi_range(6, 12):
				var t := rng.randf_range(-0.2, 1.0)
				_disc(mask, Vector2(rng.randf_range(-0.25, 0.25) * (1.0 - t * 0.5), -0.5 + t * 1.4), rng.randf_range(0.012, 0.045))
		"drops":
			for i in rng.randi_range(10, 18):
				var a := rng.randf_range(0, TAU)
				var d := sqrt(rng.randf()) * 0.85
				var c := Vector2(cos(a), sin(a)) * d
				var rr := rng.randf_range(0.025, 0.11)
				_blob(mask, rng, c, rr, 0.12, 4)
		"pool":
			_blob(mask, rng, Vector2.ZERO, 0.5, 0.14, 4)
			_blob(mask, rng, Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)), 0.3, 0.2, 5)
			_satellites(mask, rng, rng.randi_range(3, 7), 0.65, 0.95, 0.02, 0.07)
		"smear":
			# Сплошная мазня с рваными краями: по краям — полосы от пальцев и одежды,
			# концы обрываются неровно, рядом брызги.
			var ph := [rng.randf_range(0, TAU), rng.randf_range(0, TAU), rng.randf_range(0, TAU)]
			for px in SIZE:
				for py in SIZE:
					var u := px / float(SIZE) * 2.0 - 1.0
					var v := py / float(SIZE) * 2.0 - 1.0
					var width := 0.42 + 0.1 * sin(v * 5.0 + ph[0]) + 0.05 * sin(v * 13.0 + ph[1])
					var end_v := 0.8 + 0.12 * sin(u * 9.0 + ph[2])
					if absf(v) > end_v:
						continue
					var au := absf(u) / width
					if au < 0.62:
						mask[py * SIZE + px] = 255
					elif au < 1.0:
						var streaks := sin(u * 38.0 + sin(v * 4.0 + ph[1]) * 1.5)
						if streaks > -0.1 + (au - 0.62) * 2.0:
							mask[py * SIZE + px] = 255
			_satellites(mask, rng, rng.randi_range(4, 8), 0.5, 0.9, 0.015, 0.04)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_LA8)
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * 2)
	for i in SIZE * SIZE:
		data[i * 2] = 255
		data[i * 2 + 1] = mask[i]
	img.set_data(SIZE, SIZE, false, Image.FORMAT_LA8, data)
	var tex := ImageTexture.create_from_image(img)
	tex.set_meta("kind", kind)
	_textures[key] = tex
	return tex


## Пятно с неровным краем: радиус колеблется по нескольким гармоникам.
static func _blob(mask: PackedByteArray, rng: RandomNumberGenerator, center: Vector2, radius: float, rough: float, harmonics: int) -> void:
	var amps := []
	for k in harmonics:
		amps.append([k + 2, rng.randf_range(0.2, 1.0) * rough / (1.0 + k * 0.3), rng.randf_range(0, TAU)])
	var reach := radius * (1.0 + rough * 2.0)
	_each_pixel(mask, center, reach, func(p: Vector2) -> bool:
		var d := p - center
		var a := atan2(d.y, d.x)
		var r := radius
		for h in amps:
			r += radius * h[1] * sin(h[0] * a + h[2])
		return d.length() < r)


## Луч-выплеск от центра к краю, сужается к концу и заканчивается каплей.
static func _ray(mask: PackedByteArray, rng: RandomNumberGenerator, angle: float, start: float, end: float, width: float) -> void:
	var dir := Vector2(cos(angle), sin(angle))
	var steps := 12
	for i in steps + 1:
		var t := i / float(steps)
		_disc(mask, dir * lerpf(start, end, t), width * (1.0 - t * 0.7))
	_disc(mask, dir * (end + width), width * rng.randf_range(0.6, 1.1))


static func _satellites(mask: PackedByteArray, rng: RandomNumberGenerator, count: int, near: float, far: float, small: float, big: float) -> void:
	for i in count:
		var a := rng.randf_range(0, TAU)
		_disc(mask, Vector2(cos(a), sin(a)) * rng.randf_range(near, far), rng.randf_range(small, big))


static func _disc(mask: PackedByteArray, center: Vector2, radius: float) -> void:
	_each_pixel(mask, center, radius, func(p: Vector2) -> bool: return p.distance_to(center) < radius)


## Закрашивает пиксели в квадрате вокруг центра, для которых inside(p) истинно.
static func _each_pixel(mask: PackedByteArray, center: Vector2, reach: float, inside: Callable) -> void:
	var x0 := clampi(int((center.x - reach + 1.0) * 0.5 * SIZE), 0, SIZE - 1)
	var x1 := clampi(int((center.x + reach + 1.0) * 0.5 * SIZE) + 1, 0, SIZE - 1)
	var y0 := clampi(int((center.y - reach + 1.0) * 0.5 * SIZE), 0, SIZE - 1)
	var y1 := clampi(int((center.y + reach + 1.0) * 0.5 * SIZE) + 1, 0, SIZE - 1)
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var p := Vector2((px + 0.5) / SIZE * 2.0 - 1.0, (py + 0.5) / SIZE * 2.0 - 1.0)
			if inside.call(p):
				mask[py * SIZE + px] = 255
