extends RefCounted
## Звуки, синтезированные кодом: без сторонних файлов и лицензий.
## Выстрел, попадание, хруст отрыва, мычание, рык и сдавленный крик зомби, удар по игроку, щелчки затвора.
## У каждого звука несколько вариантов, чтобы повторы не резали слух.

const RATE := 22050
const MAX_GROANS := 6
## Звуки попаданий по телу: у каждого шесть вариантов, а при проигрывании ещё и
## случайная высота, поэтому две пули подряд почти никогда не звучат одинаково.
##   hit_flesh — пуля в мясо: хлёсткий шлепок и глухой удар;
##   hit_bone — по кости: сухой стук и треск;
##   hit_skull — по черепу: тяжёлый костяной стук и хлюп;
##   squelch — мокрое глухое чавканье (большая рана, выход пули, труп);
##   spatter — кровь брызгами шлёпает по полу и стенам;
##   tear — мясо рвётся (отрыв предплечья, руки, ноги).
const HIT_SOUNDS := ["hit_flesh", "hit_bone", "hit_skull", "squelch", "spatter", "tear"]
## Голоса зомби, кроме мычания, рыка и сдавленного крика:
##   yelp — короткий резкий вскрик «ах!» от пули;
##   shriek — пронзительный хриплый визг (оторвало руку, раскололо череп);
##   gurgle — бульканье кровью в горле;
##   howl — протяжный вой, когда подогнулись колени;
##   death — предсмертный хрип, тон падает и переходит в клёкот;
##   snarl — злобное шипение-рык, когда заметил игрока;
##   hiss — сиплое дыхание ползущего.
const VOICE_SOUNDS := ["yelp", "shriek", "gurgle", "howl", "death", "snarl", "hiss"]

static var _cache := {}
static var _active_groans := 0


## Генерирует все звуки заранее, чтобы первый выстрел не подтормаживал.
static func preload_all() -> void:
	for sound in ["shot", "splat", "crunch", "groan", "growl", "pain", "hurt", "click", "reload", "slash", "pickup"] + HIT_SOUNDS + VOICE_SOUNDS:
		stream(sound)


static func stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		var variants: Array = []
		for v in (6 if sound in HIT_SOUNDS or sound in VOICE_SOUNDS else 4):
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
## voice — высота голоса этого зомби: у каждого свой, от низкого хрипа до сиплого крика.
static func groan(zombie: Node3D, sound := "groan", volume_db := -4.0, voice := 1.0) -> void:
	var pos := zombie.global_position + Vector3.UP * 1.5
	if sound != "groan" and sound != "hiss":
		play_at(zombie.get_parent(), sound, pos, volume_db, voice * randf_range(0.9, 1.02))
		return
	if _active_groans >= MAX_GROANS:
		return
	_active_groans += 1
	var p := play_at(zombie.get_parent(), sound, pos, volume_db, voice * randf_range(0.88, 1.02))
	p.tree_exited.connect(func(): _active_groans -= 1)


# --- Синтез -----------------------------------------------------------------

static func _synth(sound: String, variant: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sound) + variant * 7919
	var out := _synth_raw(sound, rng)
	# Попадания и шипение глушим: звонкие верха делают их игрушечными.
	if sound in HIT_SOUNDS or sound in ["snarl", "hiss", "gurgle", "splat", "crunch"]:
		out = _dark(out, 0.22 if sound in ["hit_bone", "hit_skull", "crunch"] else 0.3)
	return out


static func _synth_raw(sound: String, rng: RandomNumberGenerator) -> PackedFloat32Array:
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
		"slash":
			return _slash(rng)
		"pickup":
			return _pickup()
		"hit_flesh":
			return _hit_flesh(rng)
		"hit_bone":
			return _hit_bone(rng, rng.randf_range(150.0, 240.0), 0.2)
		"hit_skull":
			return _mix(_hit_bone(rng, rng.randf_range(95.0, 150.0), 0.3), _scaled(_squelch(rng, 0.3), 0.5))
		"squelch":
			return _squelch(rng, rng.randf_range(0.3, 0.45))
		"spatter":
			return _spatter(rng)
		"tear":
			return _tear(rng)
		"yelp":
			return _yelp(rng)
		"shriek":
			return _shriek(rng)
		"gurgle":
			return _gurgle(rng)
		"howl":
			return _howl(rng)
		"death":
			return _death_rattle(rng)
		"snarl":
			return _snarl(rng)
		"hiss":
			return _hiss(rng)
	return PackedFloat32Array()


## Короткий вскрик «ах!»: резкая атака, тон подскакивает и сразу обрывается.
static func _yelp(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := rng.randf_range(0.8, 1.25)
	var vowel: Array = [[750.0, 1250.0], [600.0, 1700.0], [500.0, 1000.0]][rng.randi() % 3]
	return _voice(rng, rng.randf_range(0.18, 0.3), Vector3(105, 135, 80) * s, [
		[0.0, vowel[0], vowel[1], 2600.0, 0.0],
		[0.06, vowel[0], vowel[1], 2600.0, 1.0],
		[0.6, vowel[0] * 0.9, vowel[1] * 0.95, 2500.0, 0.8],
		[1.0, vowel[0] * 0.7, vowel[1] * 0.9, 2400.0, 0.0],
	], 0.5, rng.randf_range(0.2, 0.6), 0.08, 0.0)


## Визг: высокий, срывающийся, с хрипом; тон ползёт вверх и ломается.
static func _shriek(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := rng.randf_range(0.85, 1.2)
	var length := rng.randf_range(0.7, 1.1)
	var out := _voice(rng, length, Vector3(120, 175, 85) * s, [
		[0.0, 650.0, 1900.0, 2900.0, 0.0],
		[0.05, 800.0, 1800.0, 2900.0, 1.0],
		[0.4, 900.0, 1500.0, 2800.0, 1.0],
		[0.75, 700.0, 1300.0, 2700.0, 0.8],
		[1.0, 550.0, 1200.0, 2600.0, 0.0],
	], 0.75, 0.75, 0.14, 0.0)
	# Голос рвётся неровно: громкость скачет от случайного шума, а не по синусу.
	_roughen(rng, out, 0.45, 0.004)
	return out


## Бульканье: низкий клокочущий голос, кровь пузырится в горле.
static func _gurgle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := rng.randf_range(0.8, 1.15)
	var length := rng.randf_range(0.55, 0.9)
	var out := _voice(rng, length, Vector3(62, 72, 48) * s, [
		[0.0, 400.0, 900.0, 2300.0, 0.0],
		[0.1, 450.0, 850.0, 2300.0, 0.9],
		[0.7, 380.0, 800.0, 2200.0, 0.8],
		[1.0, 300.0, 750.0, 2200.0, 0.0],
	], 0.3, 0.9, 0.12, 0.3)
	# Голос захлёбывается кровью: громкость рвётся неровно, под ним мокрое хлюпанье.
	_roughen(rng, out, 0.75, 0.0025)
	return _mix(out, _scaled(_squelch(rng, length), 0.3))


## Протяжный вой «у-а-а-у»: тон медленно поднимается и тоскливо падает.
static func _howl(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := rng.randf_range(0.85, 1.15)
	return _voice(rng, rng.randf_range(1.2, 1.7), Vector3(70, 98, 50) * s, [
		[0.0, 320.0, 800.0, 2300.0, 0.0],
		[0.15, 350.0, 750.0, 2300.0, 0.8],
		[0.45, 700.0, 1150.0, 2500.0, 1.0],
		[0.8, 450.0, 850.0, 2300.0, 0.7],
		[1.0, 330.0, 780.0, 2200.0, 0.0],
	], 0.35, 0.6, 0.06, 0.15)


## Предсмертный хрип: стон опускается, становится скрипучим и рассыпается в клёкот.
static func _death_rattle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := rng.randf_range(0.85, 1.15)
	var length := rng.randf_range(1.0, 1.5)
	var out := _voice(rng, length, Vector3(80, 85, 32) * s, [
		[0.0, 550.0, 1100.0, 2400.0, 0.0],
		[0.08, 600.0, 1100.0, 2400.0, 1.0],
		[0.5, 450.0, 900.0, 2300.0, 0.7],
		[1.0, 300.0, 800.0, 2200.0, 0.0],
	], 0.45, 0.95, 0.1, 0.2)
	# Ближе к концу голос распадается на неровные хрипы.
	var tail := out.slice(int(out.size() * 0.45))
	_roughen(rng, tail, 0.9, 0.002)
	for i in tail.size():
		out[int(out.size() * 0.45) + i] = tail[i] * 1.3
	return out


## Злобное шипение-рык: резкий выдох сквозь зубы и короткий хриплый рык.
static func _snarl(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := rng.randf_range(0.9, 1.15)
	var length := rng.randf_range(0.5, 0.75)
	var out := _voice(rng, length, Vector3(64, 78, 52) * s, [
		[0.0, 500.0, 1700.0, 2700.0, 0.0],
		[0.25, 500.0, 1700.0, 2700.0, 0.1],
		[0.35, 650.0, 1400.0, 2600.0, 1.0],
		[0.8, 600.0, 1300.0, 2500.0, 0.8],
		[1.0, 500.0, 1200.0, 2400.0, 0.0],
	], 0.7, 1.0, 0.08, 0.0)
	# Шипение в начале.
	var bp := Band.new()
	bp.q = 0.6
	for i in int(length * 0.4 * RATE):
		var u := float(i) / (length * 0.4 * RATE)
		out[i] += bp.step(rng.randf_range(-1.0, 1.0), 1600.0) * sin(PI * u) * 0.5
	return out


## Сиплое дыхание ползущего: два-три хриплых вдоха-выдоха.
static func _hiss(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var length := rng.randf_range(1.0, 1.6)
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var breaths := rng.randi_range(2, 3)
	var bp := Band.new()
	bp.q = 0.9
	var lp := 0.0
	for i in n:
		var u := float(i) / n
		var b := fmod(u * breaths, 1.0)
		var env := sin(PI * b) * (0.6 + 0.4 * float(int(u * breaths) % 2))
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.2
		var rasp := 0.6 + 0.4 * absf(lp) * 3.0
		out[i] = (bp.step(noise, lerpf(500.0, 900.0, b)) * 0.8 + lp * 0.5) * env * rasp
	return out


## Простой фильтр (state variable): возвращает полосу вокруг частоты fc.
class Band:
	var low := 0.0
	var band := 0.0
	var q := 0.7

	func step(x: float, fc: float) -> float:
		var f := 2.0 * sin(PI * minf(fc, 8000.0) / 22050.0)
		low += f * band
		var high := x - low - q * band
		band += f * high
		return band


## Пуля в мясо: короткий хлёсткий шлепок (полоса шума повыше), под ним глухой
## удар, падающий по высоте, и мокрый хвост, который «булькает» с неровной частотой.
static func _hit_flesh(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * rng.randf_range(0.18, 0.28))
	var out := PackedFloat32Array()
	out.resize(n)
	var slap := Band.new()
	slap.q = rng.randf_range(0.4, 0.9)
	var slap_fc := rng.randf_range(650.0, 1400.0)
	var lp := 0.0
	var thud_f := rng.randf_range(45.0, 75.0)
	var phase := 0.0
	var wob := rng.randf_range(18.0, 45.0)
	var wet_amp := rng.randf_range(0.7, 1.4)
	var slap_decay := rng.randf_range(80.0, 120.0)
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var hit := slap.step(noise, slap_fc) * exp(-t * slap_decay) * 2.2
		phase += thud_f * (1.0 - t * 2.5) / RATE
		var thud := sin(TAU * phase) * exp(-t * 26.0)
		lp += (noise - lp) * 0.14
		var wet := lp * exp(-t * 15.0) * (0.55 + 0.45 * absf(sin(TAU * wob * t * 0.5 + rng.randf() * 0.4))) * wet_amp * 2.0
		out[i] = hit + thud * 0.85 + wet
	return out


## Удар по кости: несколько негармоничных обертонов (дерево, а не металл), быстро
## гаснут; в начале — сухие треск-зёрна, под ними немного мяса.
static func _hit_bone(rng: RandomNumberGenerator, f0: float, length: float) -> PackedFloat32Array:
	var n := int(RATE * length)
	var out := _scaled(_hit_flesh(rng), 0.45)
	out.resize(n)
	var ratios := [1.0, rng.randf_range(2.1, 2.5), rng.randf_range(3.4, 4.1), rng.randf_range(5.2, 6.3)]
	for i in n:
		var t := float(i) / RATE
		var knock := 0.0
		for k in ratios.size():
			knock += sin(TAU * f0 * ratios[k] * t + rng.randf_range(-0.6, 0.6)) * exp(-t * (55.0 + k * 30.0)) / (1.0 + k)
		out[i] += tanh(knock * 2.0) * 0.8
	for g in rng.randi_range(3, 6):
		var start := int(rng.randf_range(0.0, 0.035) * RATE)
		var len_g := int(rng.randf_range(0.002, 0.008) * RATE)
		var amp := rng.randf_range(0.5, 1.0)
		for j in len_g:
			if start + j < n:
				out[start + j] += rng.randf_range(-1.0, 1.0) * amp * (1.0 - float(j) / len_g)
	return out


## Мокрое чавканье: шум сквозь полосу, которая гуляет по высоте, и пузыри —
## короткие свисты вверх, как лопающаяся пена.
static func _squelch(rng: RandomNumberGenerator, length: float) -> PackedFloat32Array:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var bp := Band.new()
	bp.q = 0.5
	var f_lo := rng.randf_range(140.0, 260.0)
	var f_hi := rng.randf_range(380.0, 700.0)
	for i in n:
		var t := float(i) / RATE
		var u := t / length
		var fc := lerpf(f_lo, f_hi, sin(PI * u) * (0.6 + 0.4 * sin(t * 31.0)))
		var env := minf(t / 0.01, 1.0) * exp(-u * 3.5)
		out[i] = bp.step(rng.randf_range(-1.0, 1.0), fc) * env * 2.5
	for b in rng.randi_range(4, 9):
		var start := int(rng.randf_range(0.0, length * 0.8) * RATE)
		var dur := rng.randf_range(0.01, 0.03)
		var fc := rng.randf_range(160.0, 420.0)
		var amp := rng.randf_range(0.4, 0.9)
		var wet := Band.new()
		wet.q = 0.35
		for j in int(dur * RATE):
			if start + j >= n:
				break
			var v := float(j) / (dur * RATE)
			out[start + j] += wet.step(rng.randf_range(-1.0, 1.0), fc) * sin(PI * v) * amp * 2.0
	return out


## Брызги: десятки мелких капель шлёпают по полу и стене, чаще сразу, потом реже.
static func _spatter(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	var drops := rng.randi_range(12, 26)
	for d in drops:
		var start := int((0.02 + pow(rng.randf(), 2.0) * 0.38) * RATE)
		var len_d := int(rng.randf_range(0.003, 0.012) * RATE)
		var amp := rng.randf_range(0.2, 1.0)
		var bp := Band.new()
		bp.q = 0.8
		var fc := rng.randf_range(500.0, 1800.0)
		for j in len_d:
			if start + j >= n:
				break
			var v := float(j) / len_d
			out[start + j] += bp.step(rng.randf_range(-1.0, 1.0), fc) * amp * (1.0 - v) * 3.0
	return out


## Мясо рвётся: густой треск волокон нарастает и обрывается, под ним мокрый гул.
static func _tear(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var length := rng.randf_range(0.4, 0.6)
	var n := int(RATE * length)
	var out := _scaled(_squelch(rng, length), 0.7)
	var grains := rng.randi_range(45, 80)
	for g in grains:
		var u := rng.randf()
		u = sqrt(u) * 0.85
		var start := int(u * length * RATE)
		var len_g := int(rng.randf_range(0.002, 0.01) * RATE)
		var amp := rng.randf_range(0.2, 0.9) * (0.4 + u)
		var bp := Band.new()
		bp.q = 0.6
		var fc := rng.randf_range(350.0, 1300.0)
		for j in len_g:
			if start + j >= n:
				break
			out[start + j] += bp.step(rng.randf_range(-1.0, 1.0), fc) * amp * 2.5
	# Последний рывок: глухой хлопок, когда кусок отделяется.
	var pop := int(length * 0.82 * RATE)
	for j in int(0.08 * RATE):
		if pop + j >= n:
			break
		var t := float(j) / RATE
		out[pop + j] += sin(TAU * 60.0 * t) * exp(-t * 30.0) * 0.9
	return out


## Двойной фильтр низких частот: оставляет мясо и удар, убирает «стеклянный» звон.
static func _dark(a: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var out := a.duplicate()
	var l1 := 0.0
	var l2 := 0.0
	for i in out.size():
		l1 += (out[i] - l1) * k
		l2 += (l1 - l2) * k
		out[i] = l2
	return out


static func _scaled(a: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var out := a.duplicate()
	for i in out.size():
		out[i] *= k
	return out


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
		var src := (g - prev_g) * 12.0 * (1.0 - maxf(fry, 0.6) * 0.75 if odd else 1.0)
		prev_g = g
		src += rng.randf_range(-1.0, 1.0) * breath
		var k := _key(keys, u)
		var sum := 0.0
		for f in 3:
			# Глотка большая и разорванная: все резонансы ниже, чем у живого человека.
			var theta: float = TAU * k[f] * 0.78 / RATE
			var r := exp(-PI * bandwidth[f] / RATE)
			var v: float = (1.0 - r) * src + 2.0 * r * cos(theta) * y1[f] - r * r * y2[f]
			y2[f] = y1[f]
			y1[f] = v
			# Без поправки высокие форманты почти не слышны, и голос превращается в гул.
			sum += v * weight[f] * 2.0 * sin(theta)
		lp += (sum - lp) * (1.0 - maxf(muffle, 0.2))
		out[i] = lp * k[3]
	return _grim(rng, out)


## Делает голос мрачным: грязный перегруз связок, срез звонких верхов и глухой
## отзвук, как в бетонном коридоре. Без этого синтез звучит чисто и «мультяшно».
static func _grim(rng: RandomNumberGenerator, dry: PackedFloat32Array) -> PackedFloat32Array:
	var tail := int(0.35 * RATE)
	var out := PackedFloat32Array()
	out.resize(dry.size() + tail)
	var peak := 0.0001
	for v in dry:
		peak = maxf(peak, absf(v))
	var lp := 0.0
	var lp2 := 0.0
	for i in dry.size():
		var x := tanh(dry[i] / peak * 2.6)
		# Шершавость: громкость каждого мгновения слегка дёргается от шума.
		x *= 0.8 + 0.2 * rng.randf()
		lp += (x - lp) * 0.32
		lp2 += (lp - lp2) * 0.5
		out[i] = lp2 * peak * 0.85
	# Отзвук: несколько затухающих задержек, ниже и глуше оригинала.
	var delays := [0.031, 0.047, 0.071, 0.113]
	var gains := [0.32, 0.24, 0.17, 0.11]
	var wet := out.duplicate()
	for d in delays.size():
		var off := int(delays[d] * RATE)
		var echo_lp := 0.0
		for i in range(off, out.size()):
			echo_lp += (wet[i - off] - echo_lp) * 0.2
			out[i] += echo_lp * gains[d]
	return out


## Рвёт голос: громкость прыгает от сглаженного шума (как кровь и хрипы в горле),
## без ровной синусоидальной дрожи. depth — насколько глубоко, smooth — плавность.
static func _roughen(rng: RandomNumberGenerator, out: PackedFloat32Array, depth: float, smooth: float) -> void:
	var g := 1.0
	var target := 1.0
	for i in out.size():
		if i % 400 == 0:
			target = rng.randf()
		g += (target - g) * smooth
		out[i] *= 1.0 - depth + depth * clampf(g * 1.6 - 0.2, 0.0, 1.0)


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
	return _voice(rng, rng.randf_range(1.3, 2.0), Vector3(64, 74, 52) * s, [
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
	return _voice(rng, 0.5, Vector3(56, 64, 42) * s, [
		[0.0, 600.0, 1100.0, 2400.0, 0.0],
		[0.08, 650.0, 1150.0, 2400.0, 1.0],
		[0.7, 550.0, 1000.0, 2400.0, 0.8],
		[1.0, 450.0, 950.0, 2300.0, 0.0],
	], 0.55, 0.9, 0.05, 0.25)


## Сдавленный крик от попадания: резкое «э-а», которое обрывается в горле.
static func _pain(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := rng.randf_range(0.85, 1.2)
	var length := rng.randf_range(0.4, 0.55)
	var out := _voice(rng, length, Vector3(100, 128, 75) * s, [
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
		if u > 0.64 and u < 0.82:
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.25
			out[i] += lp * 0.06 * (1.0 - (u - 0.64) / 0.18)
	return out


## Взмах ножом: шипящий «вжух», нарастает и стихает.
static func _slash(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.2)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var prev := 0.0
	for i in n:
		var u := float(i) / n
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * lerpf(0.15, 0.6, u)
		var bright := lp - prev
		prev = lp
		out[i] = (lp * 0.6 + bright * 1.5) * sin(PI * u) * sin(PI * u)
	return out


## Подбор предмета: два коротких звонких сигнала.
static func _pickup() -> PackedFloat32Array:
	var n := int(RATE * 0.18)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 880.0 if t < 0.07 else 1320.0
		var local := t if t < 0.07 else t - 0.07
		out[i] = sin(TAU * f * t) * exp(-local * 30.0) * 0.6
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
