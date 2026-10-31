extends RefCounted
## Звуки, синтезированные кодом: без сторонних файлов и лицензий.
## Выстрел, попадание, хруст отрыва, мычание, рык и сдавленный крик зомби, удар по игроку, щелчки затвора.
## У каждого звука несколько вариантов, чтобы повторы не резали слух.

const RATE := 22050
const MAX_GROANS := 6

static var _cache := {}
static var _active_groans := 0


## Генерирует все звуки заранее, чтобы первый выстрел не подтормаживал.
static func preload_all() -> void:
	for sound in ["shot", "splat", "crunch", "groan", "growl", "pain", "hurt", "click", "reload"]:
		stream(sound)


static func stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		var variants: Array = []
		for v in 4:
			variants.append(_wav(_synth(sound, v)))
		_cache[sound] = variants
	return _cache[sound].pick_random()


## Звук в точке мира: громкость и панорама зависят от расстояния до слушателя.
static func play_at(world: Node3D, sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.unit_size = 6.0
	p.max_distance = 45.0
	world.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p


## Звук «в голове» игрока: свой выстрел и свою боль слышно одинаково громко на любой половине экрана.
static func play_flat(parent: Node, sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Голос зомби. Мычания одновременно звучит не больше MAX_GROANS, чтобы толпа не превращалась в кашу.
static func groan(zombie: Node3D, sound := "groan", volume_db := -4.0) -> void:
	var pos := zombie.global_position + Vector3.UP * 1.5
	if sound != "groan":
		play_at(zombie.get_parent(), sound, pos, volume_db, randf_range(0.9, 1.1))
		return
	if _active_groans >= MAX_GROANS:
		return
	_active_groans += 1
	var p := play_at(zombie.get_parent(), sound, pos, volume_db, randf_range(0.85, 1.15))
	p.tree_exited.connect(func(): _active_groans -= 1)


# --- Синтез -----------------------------------------------------------------

static func _synth(sound: String, variant: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sound) + variant * 7919
	match sound:
		"shot":
			return _shot(rng)
		"splat":
			return _splat(rng, 0.25)
		"crunch":
			return _crunch(rng)
		"groan":
			return _moan(rng)
		"growl":
			return _growl(rng)
		"pain":
			return _pain(rng)
		"hurt":
			return _hurt(rng)
		"click":
			return _click(rng, 0.0, 0.05)
		"reload":
			return _mix(_click(rng, 0.0, 0.5), _click(rng, 0.35, 0.5))
	return PackedFloat32Array()


static func _shot(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		# Яркий щелчок в начале, потом тёмный хвост эха.
		lp += (noise - lp) * lerpf(0.95, 0.06, minf(t / 0.12, 1.0))
		var crack := noise * exp(-t * 220.0)
		var body := lp * exp(-t * 11.0)
		var thump := sin(TAU * 55.0 * t) * exp(-t * 22.0)
		out[i] = (crack * 0.9 + body * 0.9 + thump * 0.9)
	return out


static func _splat(rng: RandomNumberGenerator, length: float) -> PackedFloat32Array:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var freq := rng.randf_range(90.0, 140.0)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.18
		phase += freq * (1.0 - t * 2.0) / RATE
		var wet := lp * 2.2 * exp(-t * 16.0)
		var thud := sin(TAU * phase) * exp(-t * 30.0)
		out[i] = wet + thud * 0.7
	return out


static func _crunch(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.35)
	var out := _splat(rng, 0.35)
	# Хруст: короткие резкие треск-зёрна поверх мокрого удара.
	var grains := rng.randi_range(6, 10)
	for g in grains:
		var start := int(rng.randf_range(0.0, 0.18) * RATE)
		var length := int(rng.randf_range(0.004, 0.012) * RATE)
		var amp := rng.randf_range(0.4, 0.9)
		for j in length:
			if start + j < n:
				out[start + j] += rng.randf_range(-1.0, 1.0) * amp * (1.0 - float(j) / length)
	return out


## Голосовой синтез: импульсы «связок» проходят через резонансы гласной (форманты),
## как во рту. Ключи: [доля времени, F1, F2, F3, громкость]. fry — хрип (каждый
## второй импульс слабее), breath — придыхание, muffle — закрытый рот (мычание).
static func _voice(rng: RandomNumberGenerator, length: float, pitch: Vector3, keys: Array, breath: float, fry: float, jitter: float, muffle: float) -> PackedFloat32Array:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var odd := false
	var prev_g := 0.0
	var drift := 0.0
	var lp := 0.0
	var bandwidth := [90.0, 130.0, 200.0]
	var weight := [1.0, 0.7, 0.45]
	var y1 := [0.0, 0.0, 0.0]
	var y2 := [0.0, 0.0, 0.0]
	for i in n:
		var u := float(i) / n
		# Высота тона: от начала к пику на 30% и вниз к концу, плюс дрожание.
		var f0 := lerpf(pitch.x, pitch.y, u / 0.3) if u < 0.3 else lerpf(pitch.y, pitch.z, (u - 0.3) / 0.7)
		drift = clampf(drift + rng.randf_range(-1.0, 1.0) * 0.02, -1.0, 1.0)
		f0 *= 1.0 + drift * jitter + 0.02 * sin(TAU * 4.5 * u * length)
		phase += f0 / RATE
		if phase >= 1.0:
			phase -= 1.0
			odd = not odd
		var g := 0.0
		if phase < 0.4:
			g = 0.5 * (1.0 - cos(PI * phase / 0.4))
		elif phase < 0.56:
			g = cos(PI * 0.5 * (phase - 0.4) / 0.16)
		var src := (g - prev_g) * 12.0 * (1.0 - fry * 0.6 if odd else 1.0)
		prev_g = g
		src += rng.randf_range(-1.0, 1.0) * breath
		var k := _key(keys, u)
		var sum := 0.0
		for f in 3:
			var theta: float = TAU * k[f] / RATE
			var r := exp(-PI * bandwidth[f] / RATE)
			var v: float = (1.0 - r) * src + 2.0 * r * cos(theta) * y1[f] - r * r * y2[f]
			y2[f] = y1[f]
			y1[f] = v
			# Без поправки высокие форманты почти не слышны, и голос превращается в гул.
			sum += v * weight[f] * 2.0 * sin(theta)
		lp += (sum - lp) * (1.0 - muffle)
		out[i] = lp * k[3]
	return out


## Значение ключей гласной в момент u (линейная интерполяция).
static func _key(keys: Array, u: float) -> Array:
	for j in range(1, keys.size()):
		if u <= keys[j][0]:
			var a: Array = keys[j - 1]
			var b: Array = keys[j]
			var w: float = (u - a[0]) / maxf(b[0] - a[0], 0.0001)
			return [lerpf(a[1], b[1], w), lerpf(a[2], b[2], w), lerpf(a[3], b[3], w), lerpf(a[4], b[4], w)]
	var last: Array = keys[-1]
	return [last[1], last[2], last[3], last[4]]


## Мычание: закрытый рот «м-м» переходит в глухое «у-о» и обратно.
static func _moan(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := rng.randf_range(0.85, 1.15)
	return _voice(rng, rng.randf_range(1.3, 2.0), Vector3(95, 112, 78) * s, [
		[0.0, 260.0, 1000.0, 2300.0, 0.0],
		[0.12, 270.0, 950.0, 2300.0, 0.6],
		[0.35, 330.0, 800.0, 2300.0, 0.9],
		[0.55, 430.0, 850.0, 2400.0, 1.0],
		[0.85, 350.0, 800.0, 2300.0, 0.7],
		[1.0, 270.0, 950.0, 2300.0, 0.0],
	], 0.2, 0.55, 0.03, 0.4)


## Рык при атаке: короткое хриплое «а-гх».
static func _growl(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := rng.randf_range(0.9, 1.1)
	return _voice(rng, 0.5, Vector3(90, 105, 70) * s, [
		[0.0, 600.0, 1100.0, 2400.0, 0.0],
		[0.08, 650.0, 1150.0, 2400.0, 1.0],
		[0.7, 550.0, 1000.0, 2400.0, 0.8],
		[1.0, 450.0, 950.0, 2300.0, 0.0],
	], 0.55, 0.9, 0.05, 0.25)


## Сдавленный крик от попадания: резкое «э-а», которое обрывается в горле.
static func _pain(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := rng.randf_range(0.85, 1.2)
	var length := rng.randf_range(0.4, 0.55)
	var out := _voice(rng, length, Vector3(220, 290, 170) * s, [
		[0.0, 600.0, 1700.0, 2600.0, 0.0],
		[0.04, 700.0, 1600.0, 2600.0, 1.0],
		[0.45, 750.0, 1450.0, 2550.0, 0.9],
		[0.58, 650.0, 1300.0, 2500.0, 0.7],
		[0.62, 500.0, 1200.0, 2400.0, 0.0],
		[1.0, 500.0, 1200.0, 2400.0, 0.0],
	], 0.45, 0.35, 0.06, 0.0)
	# Напряжение в голосе и хриплый выдох «гх» после обрыва.
	var lp := 0.0
	for i in out.size():
		var u := float(i) / out.size()
		out[i] *= 1.0 + 0.25 * sin(TAU * 28.0 * u * length)
		if u > 0.64 and u < 0.82:
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.25
			out[i] += lp * 0.06 * (1.0 - (u - 0.64) / 0.18)
	return out


static func _hurt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.3)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.1
		out[i] = (sin(TAU * 85.0 * t) * 0.9 + lp * 1.5) * exp(-t * 18.0)
	return out


static func _click(rng: RandomNumberGenerator, at: float, total: float) -> PackedFloat32Array:
	var n := int(RATE * maxf(total, at + 0.05))
	var out := PackedFloat32Array()
	out.resize(n)
	var start := int(at * RATE)
	var prev := 0.0
	for j in int(RATE * 0.03):
		var noise := rng.randf_range(-1.0, 1.0)
		var t := float(j) / RATE
		out[start + j] = (noise - prev) * 0.5 * exp(-t * 200.0) + sin(TAU * 1800.0 * t) * 0.3 * exp(-t * 300.0)
		prev = noise
	return out


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate()
	if b.size() > out.size():
		out.resize(b.size())
	for i in b.size():
		out[i] += b[i]
	return out


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	# Нормализация до 0.9, чтобы громкие звуки не хрипели от перегруза.
	var peak := 0.001
	for v in samples:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
