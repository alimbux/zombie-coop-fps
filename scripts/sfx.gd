extends RefCounted
## Звуки, синтезированные кодом: без сторонних файлов и лицензий.
## Выстрел, попадание, хруст отрыва, стоны и рык зомби, удар по игроку, щелчки затвора.
## У каждого звука несколько вариантов, чтобы повторы не резали слух.

const RATE := 22050
const MAX_GROANS := 6

static var _cache := {}
static var _active_groans := 0


## Генерирует все звуки заранее, чтобы первый выстрел не подтормаживал.
static func preload_all() -> void:
	for sound in ["shot", "splat", "crunch", "groan", "growl", "hurt", "click", "reload"]:
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


## Стон зомби. Одновременно звучит не больше MAX_GROANS, чтобы толпа не превращалась в кашу.
static func groan(zombie: Node3D, sound := "groan", volume_db := -4.0) -> void:
	if _active_groans >= MAX_GROANS:
		return
	_active_groans += 1
	var p := play_at(zombie.get_parent(), sound, zombie.global_position + Vector3.UP * 1.5, volume_db, randf_range(0.85, 1.15))
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
			return _groan(rng, rng.randf_range(1.0, 1.6), rng.randf_range(70.0, 110.0))
		"growl":
			return _groan(rng, 0.45, rng.randf_range(120.0, 160.0))
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


static func _groan(rng: RandomNumberGenerator, length: float, base: float) -> PackedFloat32Array:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	var breath := 0.0
	var wobble := rng.randf_range(4.0, 7.0)
	for i in n:
		var t := float(i) / RATE
		var u := t / length
		var freq := base * (1.0 + 0.07 * sin(TAU * wobble * t)) * (1.15 - 0.3 * u)
		phase = fmod(phase + freq / RATE, 1.0)
		var saw := phase * 2.0 - 1.0
		lp += (saw - lp) * 0.14
		breath += (rng.randf_range(-1.0, 1.0) - breath) * 0.08
		var env := minf(u / 0.15, 1.0) * minf((1.0 - u) / 0.3, 1.0)
		out[i] = (lp * 1.4 + breath * 0.9) * env * 0.8
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
