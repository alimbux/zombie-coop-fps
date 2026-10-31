extends CharacterBody3D
## Зомби: сгорбленная фигура в рваной одежде, руки тянутся вперёд. Каждая часть тела —
## шарнир (шея, плечо, бедро) с несколькими мешами, поэтому зомби шагает, качает головой
## и ползёт. Шесть зон попадания, у каждой своя прочность и своя смерть:
## голова — мгновенно (вскользь — вскрытый череп и текущие мозги), торс — падение,
## рука — отрыв, нога — ползёт на оставшейся, без обеих — на руках.

signal died(cause: String)

const Gore := preload("res://scripts/gore.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Kit := preload("res://scripts/mesh_kit.gd")

const WALK_SPEED := 1.6
const FAST_SPEED := 2.6
const CRAWL_SPEED := 0.75
const ATTACK_RANGE := 1.3
const ATTACK_DAMAGE := 12.0
const ATTACK_INTERVAL := 1.0
const GRAVITY := 18.0
const HUNCH := -0.25
const ARM_REACH := 1.45
const MAX_WOUNDS := 8
const MAX_KNOCK := 14.0
## Если отдача разогнала зомби сильнее этого (дробовик в упор), он падает навзничь.
const KNOCKDOWN_SPEED := 9.0
const KNOCKDOWN_TIME := 1.4
## Насколько далеко от центра головы должна пройти пуля, чтобы задеть её вскользь.
const GLANCE_DISTANCE := 0.09

## pivot — шарнир (у головы и рук — относительно торса), size/center — зона попадания
## относительно шарнира.
const ZONES := {
	"torso": {"pivot": Vector3(0.0, 0.88, 0.0), "size": Vector3(0.5, 0.66, 0.32), "center": Vector3(0.0, 0.32, 0.0), "hp": 110.0, "mult": 1.0},
	"head": {"pivot": Vector3(0.0, 0.6, 0.0), "size": Vector3(0.3, 0.34, 0.32), "center": Vector3(0.0, 0.16, -0.02), "hp": 30.0, "mult": 3.0},
	"arm_l": {"pivot": Vector3(-0.25, 0.5, 0.0), "size": Vector3(0.15, 0.72, 0.15), "center": Vector3(0.0, -0.34, 0.0), "hp": 35.0, "mult": 0.7},
	"arm_r": {"pivot": Vector3(0.25, 0.5, 0.0), "size": Vector3(0.15, 0.72, 0.15), "center": Vector3(0.0, -0.34, 0.0), "hp": 35.0, "mult": 0.7},
	"leg_l": {"pivot": Vector3(-0.12, 0.88, 0.0), "size": Vector3(0.2, 0.88, 0.24), "center": Vector3(0.0, -0.44, -0.02), "hp": 40.0, "mult": 0.7},
	"leg_r": {"pivot": Vector3(0.12, 0.88, 0.0), "size": Vector3(0.2, 0.88, 0.24), "center": Vector3(0.0, -0.44, -0.02), "hp": 40.0, "mult": 0.7},
}

var zone_hp := {}
## Шарниры частей тела по зонам.
var parts := {}
var body: Node3D
var dead := false
var crawling := false
## Как ползёт: "left" — опирается на левую ногу, "right" — на правую, "arms" — на руках.
var crawl_style := ""
## Походка: "walk" — обычная, "limp" — хромает на одну ногу, "fast" — идёт быстро, рывками.
var gait := "walk"
var skull_open := false
var attack_cooldown := 0.0
var speed_jitter := 1.0
var level = null
## Заметил ли игроков. В режиме волн зомби сразу знают, где все; на этажах — стоят, пока не заметят.
var aware := true

var _groan_timer := 0.0
var _look_timer := 0.0
var _phase := 0.0
var _limp_arm := ""
var _bad_leg := "leg_r"
var _head_tilt := 0.0
var _wounds := 0
var _stumps := 0
## Сколько прошёл с последней отметки на полу и где была прошлая отметка.
var _trail_left := 0.0
var _trail_from := Vector3.ZERO
## Отдача от попаданий: скорость, с которой зомби отбрасывает назад, и насколько
## он отшатнулся (для позы).
var _knock := Vector3.ZERO
var _stagger := 0.0
## Сколько ещё лежит после сбивания с ног, и поворот корпуса от попадания.
var knocked_down := 0.0
var _flinch := 0.0
var _skin: StandardMaterial3D
var _capsule: CapsuleShape3D
var _capsule_node: CollisionShape3D


func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 2
	collision_mask = 1 | 2 | 8
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.35
	_capsule.height = 1.8
	_capsule_node = CollisionShape3D.new()
	_capsule_node.shape = _capsule
	_capsule_node.position.y = 0.9
	add_child(_capsule_node)

	speed_jitter = randf_range(0.8, 1.3)
	_groan_timer = randf_range(0.5, 4.0)
	_phase = randf_range(0.0, TAU)
	_head_tilt = randf_range(-0.35, 0.35)
	if randf() < 0.25:
		_limp_arm = ["arm_l", "arm_r"].pick_random()
	var roll := randf()
	gait = "limp" if roll < 0.3 else ("fast" if roll < 0.5 else "walk")
	_bad_leg = ["leg_l", "leg_r"].pick_random()
	_build_body()


# --- Внешность ----------------------------------------------------------------

func _build_body() -> void:
	body = Node3D.new()
	add_child(body)
	# Кожа серая, темнее, чем у живых людей, в трупных пятнах.
	_skin = Kit.shade(snappedf(randf_range(0.3, 0.46), 0.04))
	var rot := Kit.shade(0.16)
	var bone := Kit.shade(0.88, 0.6)
	# Мутные светящиеся бельма: в темноте видно только их.
	var milky := StandardMaterial3D.new()
	milky.albedo_color = Color(0.9, 0.9, 0.9)
	milky.emission_enabled = true
	milky.emission = Color.WHITE
	milky.emission_energy_multiplier = 1.5
	var shirt := Kit.shade([0.12, 0.3, 0.5, 0.85].pick_random())
	var pants := Kit.shade([0.1, 0.22, 0.38].pick_random())
	var dark := Kit.shade(0.06)
	var pale := Kit.shade(0.95)

	var torso := _pivot("torso", body)
	torso.rotation.x = HUNCH
	Kit.add(torso, Kit.sphere(0.16), pants, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.15, 0.85, 0.8))
	Kit.add(torso, Kit.sphere(0.16), shirt, Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1.1, 1.1, 0.8))
	Kit.add(torso, Kit.sphere(0.2), shirt, Vector3(0, 0.42, 0), Vector3.ZERO, Vector3(1.2, 1.05, 0.72))
	Kit.add(torso, Kit.capsule(0.07, 0.5), shirt, Vector3(0, 0.53, 0), Vector3(0, 0, PI / 2))
	Kit.add(torso, Kit.cylinder(0.05, 0.06, 0.14), _skin, Vector3(0, 0.62, -0.01))
	# Рваная рубашка: в дырах видна серая кожа, свисает лоскут.
	var side: float = [-1.0, 1.0].pick_random()
	Kit.add(torso, Kit.sphere(0.08), _skin, Vector3(0.08 * side, 0.4, -0.14), Vector3(0, 0, 0.6), Vector3(1.3, 0.8, 0.3))
	Kit.add(torso, Kit.sphere(0.05), _skin, Vector3(0.02 * side, 0.3, -0.135), Vector3.ZERO, Vector3(1.2, 0.8, 0.3))
	Kit.add(torso, Kit.box(Vector3(0.13, 0.16, 0.012)), shirt, Vector3(-0.1 * side, 0.02, -0.13), Vector3(0.1, 0, 0.25 * side))
	if randf() < 0.35:
		# Засохшие подтёки крови на одежде.
		var at := Vector3(randf_range(-0.1, 0.1), randf_range(0.3, 0.45), -0.145)
		for i in 3:
			Kit.add(torso, Kit.sphere(0.03), Gore.blood_material(), at + Vector3(randf_range(-0.03, 0.03), -i * 0.04, 0), Vector3.ZERO, Vector3(1.0 - i * 0.2, 1.4, 0.25))

	# Трупные пятна на шее.
	for i in randi_range(1, 2):
		Kit.add(torso, Kit.sphere(0.025), rot, Vector3(randf_range(-0.04, 0.04), randf_range(0.6, 0.66), -0.05), Vector3.ZERO, Vector3(1.2, 1.0, 0.5))
	if randf() < 0.3:
		# Вспоротый живот: кишки свисают из дыры.
		var gut := Gore.brain_material()
		Kit.add(torso, Kit.sphere(0.07), dark, Vector3(0.03, 0.17, -0.125), Vector3.ZERO, Vector3(1.2, 0.9, 0.35))
		for i in 3:
			Kit.add(torso, Kit.capsule(0.024, randf_range(0.14, 0.26)), gut, Vector3(-0.02 + i * 0.03, 0.08 - i * 0.02, -0.15), Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.4, 0.4)))
		Kit.add(torso, Kit.sphere(0.03), Gore.blood_material(), Vector3(0.03, 0.12, -0.16), Vector3.ZERO, Vector3(1.6, 1.0, 0.4))

	var head := _pivot("head", torso)
	head.rotation = Vector3(0.15, 0, _head_tilt)
	Kit.add(head, Kit.sphere(0.115), _skin, Vector3(0, 0.12, -0.03), Vector3.ZERO, Vector3(0.9, 1.0, 1.0))
	var cap := Kit.add(head, Kit.sphere(0.125), _skin, Vector3(0, 0.2, -0.01), Vector3.ZERO, Vector3(0.95, 0.75, 1.0))
	cap.name = "Cap"
	cap.set_meta("hit_size", Vector3(0.22, 0.12, 0.22))
	if randf() < 0.55:
		var hair := Kit.shade(0.08)
		for i in randi_range(3, 6):
			var a := randf_range(0, TAU)
			Kit.add(cap, Kit.sphere(0.045), hair, Vector3(cos(a) * 0.08, 0.07, sin(a) * 0.08 + 0.02))
	# Отвисшая челюсть, тёмный провал рта, запавшие глаза под надбровьем.
	Kit.add(head, Kit.box(Vector3(0.14, 0.045, 0.11)), Kit.shade(0.5), Vector3(0, 0.025, -0.07), Vector3(0.4, 0, 0.08))
	Kit.add(head, Kit.sphere(0.04), dark, Vector3(0, 0.065, -0.11), Vector3.ZERO, Vector3(1.3, 0.7, 0.5))
	Kit.add(head, Kit.box(Vector3(0.025, 0.045, 0.03)), _skin, Vector3(0, 0.125, -0.14), Vector3(-0.2, 0, 0))
	Kit.add(head, Kit.box(Vector3(0.17, 0.025, 0.04)), _skin, Vector3(0, 0.2, -0.12), Vector3(0.2, 0, 0))
	var lost_eye := randf() < 0.4
	for x in [-0.045, 0.045]:
		if lost_eye and x > 0.0:
			# Выбитый глаз: глубокая тёмная глазница с кровью.
			Kit.add(head, Kit.sphere(0.032), dark, Vector3(x, 0.162, -0.105), Vector3.ZERO, Vector3(1.1, 1.0, 0.6))
			Kit.add(head, Kit.capsule(0.008, 0.08), Gore.blood_material(), Vector3(x, 0.12, -0.122))
			continue
		Kit.add(head, Kit.sphere(0.024), dark, Vector3(x, 0.165, -0.11), Vector3.ZERO, Vector3(1.2, 0.8, 0.6))
		Kit.add(head, Kit.sphere(0.011), milky, Vector3(x, 0.165, -0.124))
		Kit.add(head, Kit.box(Vector3(0.02, 0.055, 0.04)), _skin, Vector3(x * 2.55, 0.14, -0.01))
	_add_face_rot(head, rot, bone, dark)

	for zone in ["arm_l", "arm_r"]:
		var arm := _pivot(zone, torso)
		var sleeve := shirt if randf() < 0.6 else _skin
		Kit.add(arm, Kit.capsule(0.056, 0.34), sleeve, Vector3(0, -0.15, 0))
		Kit.add(arm, Kit.capsule(0.048, 0.32), _skin, Vector3(0, -0.44, -0.02), Vector3(0.15, 0, 0))
		Kit.add(arm, Kit.box(Vector3(0.075, 0.1, 0.035)), _skin, Vector3(0, -0.63, -0.04))
		Kit.add(arm, Kit.box(Vector3(0.065, 0.07, 0.02)), Kit.shade(0.3), Vector3(0, -0.7, -0.06), Vector3(0.6, 0, 0))
		if randf() < 0.45:
			# Пальцы в крови.
			Kit.add(arm, Kit.box(Vector3(0.068, 0.04, 0.024)), Gore.blood_material(), Vector3(0, -0.73, -0.075), Vector3(0.6, 0, 0))
		if randf() < 0.25:
			# Сломанная кость торчит из предплечья.
			Kit.add(arm, Kit.capsule(0.016, 0.12), bone, Vector3(0.03, -0.42, -0.06), Vector3(0.9, 0, 0.5))
			Kit.add(arm, Kit.sphere(0.03), Gore.blood_material(), Vector3(0.02, -0.42, -0.04), Vector3.ZERO, Vector3(1, 1, 0.5))
		Kit.add(arm, Kit.sphere(0.03), rot, Vector3(randf_range(-0.03, 0.03), randf_range(-0.55, -0.35), -0.04), Vector3.ZERO, Vector3(1, 1.4, 0.5))

	for zone in ["leg_l", "leg_r"]:
		var leg := _pivot(zone, body)
		Kit.add(leg, Kit.capsule(0.076, 0.46), pants, Vector3(0, -0.21, 0))
		Kit.add(leg, Kit.capsule(0.063, 0.44), pants if randf() < 0.7 else _skin, Vector3(0, -0.62, 0.02))
		Kit.add(leg, Kit.box(Vector3(0.1, 0.07, 0.23)), dark if randf() < 0.75 else _skin, Vector3(0, -0.85, -0.05))


## Гниющее лицо: пятна, оскал зубов, кровавая слюна, у кого-то прогнившая щека.
func _add_face_rot(head: Node3D, rot: Material, bone: Material, dark: Material) -> void:
	for i in randi_range(1, 3):
		Kit.add(head, Kit.sphere(0.03), rot, Vector3(randf_range(-0.08, 0.08), randf_range(0.08, 0.22), -0.09), Vector3.ZERO, Vector3(1.2, 1.0, 0.4))
	# Зубы торчат из оскала.
	for i in 5:
		Kit.add(head, Kit.box(Vector3(0.014, 0.022, 0.012)), bone, Vector3(-0.03 + i * 0.015, 0.082, -0.128))
	if randf() < 0.55:
		Kit.add(head, Kit.capsule(0.01, randf_range(0.08, 0.16)), Gore.blood_material(), Vector3(randf_range(-0.03, 0.03), -0.02, -0.12))
	if randf() < 0.35:
		# Щека прогнила насквозь: видны зубы сбоку.
		var x: float = [-0.07, 0.07].pick_random()
		Kit.add(head, Kit.sphere(0.035), dark, Vector3(x, 0.08, -0.085), Vector3.ZERO, Vector3(0.6, 1.0, 1.0))
		for i in 3:
			Kit.add(head, Kit.box(Vector3(0.01, 0.018, 0.012)), bone, Vector3(x * 1.08, 0.075 + (i - 1) * 0.004, -0.1 + i * 0.015))


## Шарнир части тела с зоной попадания.
func _pivot(zone: String, parent: Node3D) -> Node3D:
	var def: Dictionary = ZONES[zone]
	var pivot := Kit.joint(parent, def["pivot"], zone)
	pivot.set_meta("hit_size", def["size"])
	pivot.set_meta("hit_center", def["center"])
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("zone", zone)
	area.set_meta("zombie", self)
	area.position = def["center"]
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = def["size"]
	col.shape = shape
	area.add_child(col)
	pivot.add_child(area)
	parts[zone] = pivot
	zone_hp[zone] = def["hp"]
	return pivot


# --- Поведение ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_cooldown -= delta
	_groan_timer -= delta
	if _groan_timer <= 0.0:
		_groan_timer = randf_range(4.0, 9.0) if aware else randf_range(7.0, 15.0)
		Sfx.groan(self, "groan", -4.0)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	velocity.x = _knock.x
	velocity.z = _knock.z
	_knock *= exp(-delta * 4.5)
	_stagger = maxf(0.0, _stagger - delta * 2.0)
	_flinch = move_toward(_flinch, 0.0, delta * 3.0)
	if knocked_down > 0.0:
		# Лежит после удара дробью и встаёт.
		knocked_down -= delta
		move_and_slide()
		_animate(delta, 0.0)
		return
	if not aware:
		_look_timer -= delta
		if _look_timer <= 0.0:
			_look_timer = 0.3
			_look_for_players()
		move_and_slide()
		_animate(delta, 0.0)
		return
	var moving := false
	var target = _nearest_player()
	if target != null:
		var to: Vector3 = target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		var goal: Vector3 = target.global_position if level == null else level.next_waypoint(global_position, target.global_position)
		var step: Vector3 = goal - global_position
		step.y = 0.0
		if step.length() > 0.05:
			look_at(global_position + step, Vector3.UP)
		if dist > ATTACK_RANGE:
			var dir := step.normalized()
			# Пока отшатывается от попаданий, вперёд почти не идёт.
			var speed := _move_speed() * (1.0 - minf(_stagger, 0.85))
			velocity.x += dir.x * speed
			velocity.z += dir.z * speed
			moving = true
		elif attack_cooldown <= 0.0:
			attack_cooldown = ATTACK_INTERVAL
			Sfx.groan(self, "growl", 0.0)
			target.take_damage(_attack_damage())
	move_and_slide()
	_leave_trail()
	_animate(delta, 1.0 if moving else 0.0)


## Раненый оставляет за собой капли, ползущий — сплошной размазанный след.
func _leave_trail() -> void:
	if not (crawling or _wounds > 0 or _stumps > 0):
		_trail_from = global_position
		return
	var step := global_position - _trail_from
	step.y = 0.0
	_trail_left -= step.length()
	_trail_from = global_position
	if _trail_left > 0.0 or step.length() < 0.0001:
		return
	if crawling:
		_trail_left = randf_range(0.35, 0.5)
		Gore.floor_stain(get_parent(), global_position, "smear", randf_range(0.28, 0.36), step)
	else:
		# Чем больше ран, тем чаще капает.
		var bleeding := _wounds + _stumps * 3
		_trail_left = randf_range(1.6, 2.6) / sqrt(float(bleeding))
		Gore.floor_stain(get_parent(), global_position + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2)), "drops", randf_range(0.12, 0.22), step)


## Скорость с рывками: ползущий зомби продвигается толчками ноги или подтягиваясь руками.
func _move_speed() -> float:
	if not crawling:
		match gait:
			"fast":
				return FAST_SPEED * speed_jitter
			"limp":
				# Шаг здоровой ногой — рывок вперёд, больную подтягивает.
				return WALK_SPEED * 0.8 * speed_jitter * (0.35 + 1.1 * maxf(0.0, sin(_phase)))
		return WALK_SPEED * speed_jitter
	var surge: float
	if crawl_style == "arms":
		surge = 0.25 + 1.2 * absf(cos(_phase))
	else:
		surge = 0.35 + 1.3 * maxf(0.0, sin(_phase))
	var arms := int(parts.has("arm_l")) + int(parts.has("arm_r"))
	var factor := 0.75 if crawl_style == "arms" else 1.0
	if arms < 2:
		factor *= 0.7
	return CRAWL_SPEED * speed_jitter * surge * factor


## Покачивание и шаги: ноги ходят, руки тянутся, голова болтается.
func _animate(delta: float, walking: float) -> void:
	var rate := (4.2 if not crawling else 3.0) * speed_jitter
	if gait == "fast" and not crawling:
		rate *= 1.5
	_phase += delta * rate * maxf(walking, 0.25)
	var s := sin(_phase)
	var torso: Node3D = parts.get("torso")
	if crawling:
		_animate_crawl(s)
		return
	for zone in ["leg_l", "leg_r"]:
		if parts.has(zone):
			var side := 1.0 if zone == "leg_l" else -1.0
			var stride := 0.6 if gait == "fast" else 0.45
			if gait == "limp" and zone == _bad_leg:
				# Больная нога почти не сгибается и волочится, носок вывернут.
				parts[zone].rotation = Vector3(-0.15 + s * 0.12 * side * walking, 0.35, 0.12 if zone == "leg_l" else -0.12)
				continue
			parts[zone].rotation.x = s * stride * side * walking
	for zone in ["arm_l", "arm_r"]:
		if parts.has(zone):
			var reach := ARM_REACH if aware else 0.25
			if zone == _limp_arm:
				reach = 0.15
			var sway := sin(_phase * 0.5 + (0.0 if zone == "arm_l" else 1.7)) * 0.12
			parts[zone].rotation.x = lerpf(parts[zone].rotation.x, reach + sway, minf(1.0, delta * 3.0))
			parts[zone].rotation.z = 0.08 if zone == "arm_l" else -0.08
	if torso:
		torso.rotation.z = s * 0.07
		torso.rotation.x = HUNCH - absf(s) * 0.05
		if gait == "fast":
			torso.rotation.x = HUNCH - 0.25 - absf(s) * 0.08
		elif gait == "limp":
			# Тело заваливается на больную ногу при каждом шаге.
			var bad_side := -1.0 if _bad_leg == "leg_l" else 1.0
			torso.rotation.z = bad_side * (0.08 + maxf(0.0, -s) * 0.22) * maxf(walking, 0.3)
	if parts.has("head"):
		parts["head"].rotation.z = _head_tilt + sin(_phase * 0.5) * 0.12
	# Отшатывается назад от попадания: корпус откидывается, голова запрокидывается.
	if torso and _stagger > 0.0:
		torso.rotation.x += _stagger * 0.9
		if parts.has("head"):
			parts["head"].rotation.x = 0.15 + _stagger * 0.8
	if torso:
		torso.rotation.y = _flinch
	body.position.y = absf(s) * 0.03 * walking
	if gait == "limp":
		body.position.y = -maxf(0.0, -s) * 0.06 * walking
	# Сбит с ног: падает навзничь вокруг пяток, потом поднимается.
	var fall := 1.4 if knocked_down > 0.35 else 0.0
	body.rotation.x = lerpf(body.rotation.x, fall, minf(1.0, delta * (14.0 if fall > 0.0 else 5.0)))
	if body.rotation.x > 0.3:
		body.position.y = 0.12


func _animate_crawl(s: float) -> void:
	var torso: Node3D = parts["torso"]
	match crawl_style:
		"arms":
			# Лежит на животе и подтягивается руками по очереди: одна тянется вперёд,
			# другая упирается и тащит тело.
			if parts.has("arm_l"):
				parts["arm_l"].rotation = Vector3(2.35 + 0.45 * s, 0, 0.25)
			if parts.has("arm_r"):
				parts["arm_r"].rotation = Vector3(2.35 - 0.45 * s, 0, -0.25)
			torso.rotation = Vector3(0.25 + absf(s) * 0.06, s * 0.1, 0)
			body.position.y = 0.1
		_:
			# На четвереньках без одной ноги: опирается на уцелевшую, тело заваливается
			# на её сторону, руки загребают по очереди.
			var leg := "leg_l" if crawl_style == "left" else "leg_r"
			if parts.has(leg):
				parts[leg].rotation = Vector3(0.15 + 0.2 * s, 0, 0)
			for zone in ["arm_l", "arm_r"]:
				if parts.has(zone):
					var phase := s if zone == "arm_l" else -s
					parts[zone].rotation = Vector3(2.3 + 0.35 * phase, 0, 0.12 if zone == "arm_l" else -0.12)
			var lean := 0.3 if crawl_style == "left" else -0.3
			torso.rotation = Vector3(0.1, lean + s * 0.06, 0)
			body.position.y = 0.16 + maxf(0.0, s) * 0.04
	if parts.has("head"):
		parts["head"].rotation.x = -0.8
		parts["head"].rotation.z = _head_tilt * 0.5


## Зомби услышал выстрел или его задели: идёт к игрокам.
func alert() -> void:
	if aware or dead:
		return
	aware = true
	_groan_timer = randf_range(0.0, 0.6)


## Замечает игрока рядом или в прямой видимости.
func _look_for_players() -> void:
	var eye := global_position + Vector3.UP * 1.6
	for p in get_tree().get_nodes_in_group("players"):
		var d: float = p.global_position.distance_to(global_position)
		if d < 3.0:
			alert()
			return
		if d < 11.0:
			var query := PhysicsRayQueryParameters3D.create(eye, p.global_position + Vector3.UP * 1.5, 1)
			if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				alert()
				return


# --- Попадания ----------------------------------------------------------------

## Попадание пули. Возвращает true, если зомби умер.
func take_hit(zone: String, damage: float, point: Vector3, dir: Vector3, loud := true, force := 1.0) -> bool:
	if dead or not zone_hp.has(zone):
		return false
	alert()
	push(dir, force)
	Gore.splash(get_parent(), point, dir, 16)
	if zone == "head" and not skull_open and is_glancing(point, dir):
		_open_skull(point, dir)
		return false
	var def: Dictionary = ZONES[zone]
	zone_hp[zone] -= damage * float(def["mult"])
	if zone_hp[zone] > 0.0:
		_add_wound(zone, point, dir)
		if loud:
			Sfx.play_at(get_parent(), "splat", point, -8.0)
			Sfx.groan(self, "pain", -2.0)
		return false
	match zone:
		"head":
			_die_headshot(point, dir)
		"torso":
			_die_body(point, dir)
		_:
			_sever(zone, point, dir)
	return dead


## Отдача: попадание толкает зомби по направлению выстрела. Лежачего — слабее.
func push(dir: Vector3, force: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	_knock += flat * force * (0.4 if crawling else 1.0)
	_knock = _knock.limit_length(MAX_KNOCK)
	_stagger = minf(1.0, _stagger + force * 0.25)
	_flinch = clampf(_flinch + randf_range(-0.25, 0.25) * force, -0.6, 0.6)
	if not crawling and knocked_down <= 0.0 and _knock.length() >= KNOCKDOWN_SPEED:
		knocked_down = KNOCKDOWN_TIME


## Пуля прошла по краю головы, а не в лоб.
func is_glancing(point: Vector3, dir: Vector3) -> bool:
	if not parts.has("head"):
		return false
	var center: Vector3 = parts["head"].to_global(ZONES["head"]["center"])
	var to_center := center - point
	var d := dir.normalized()
	var miss := to_center - d * to_center.dot(d)
	return miss.length() > GLANCE_DISTANCE


## Рана: кровавое пятно на теле и струйка крови, бьющая из него несколько секунд.
func _add_wound(zone: String, point: Vector3, dir: Vector3) -> void:
	if _wounds >= MAX_WOUNDS or not parts.has(zone):
		return
	_wounds += 1
	var part: Node3D = parts[zone]
	var local := part.to_local(point)
	Kit.add(part, Kit.sphere(0.035), Gore.blood_material(), local)
	var out: Vector3 = (local - Vector3(ZONES[zone]["center"])).normalized()
	if out.length() < 0.5:
		out = part.global_transform.basis.inverse() * -dir
	Gore.bleed(part, local, out, randf_range(2.5, 4.0))


## Скользящее попадание в голову: верх черепа слетает, мозги вываливаются и стекают.
## Голова держится на честном слове: следующее попадание в неё убивает.
func _open_skull(point: Vector3, dir: Vector3) -> void:
	skull_open = true
	zone_hp["head"] = minf(zone_hp["head"], 1.0)
	var head: Node3D = parts["head"]
	var cap: Node3D = head.get_node_or_null("Cap")
	var top := Vector3(0, 0.2, -0.01)
	if cap:
		top = cap.position
		Gore.detach(get_parent(), cap, dir * 2.5 + Vector3.UP * 3.0)
		head.remove_child(cap)
		cap.queue_free()
	Gore.brains(head, top)
	Gore.burst(get_parent(), point, dir + Vector3.UP, 20)
	Sfx.play_at(get_parent(), "crunch", point, -2.0, 1.25)
	Sfx.groan(self, "pain", 0.0)
	speed_jitter *= 0.8
	_head_tilt = 0.5 * signf(_head_tilt if _head_tilt != 0.0 else 1.0)


func _sever(zone: String, point: Vector3, dir: Vector3) -> void:
	var part: Node3D = parts[zone]
	Gore.detach(get_parent(), part, dir * 3.0 + _knock + Vector3.UP * 2.0)
	Gore.burst(get_parent(), part.global_position, dir, 25)
	Sfx.play_at(get_parent(), "crunch", point, 0.0)
	Sfx.groan(self, "pain", 0.0)
	_remove_part(zone)
	if zone.begins_with("leg"):
		_start_crawl()
	if not (parts.has("arm_l") or parts.has("arm_r") or parts.has("leg_l") or parts.has("leg_r")):
		_die_body(point, dir)


func _die_headshot(point: Vector3, dir: Vector3) -> void:
	dead = true
	var head: Node3D = parts["head"]
	var neck: Vector3 = head.global_position
	Gore.detach(get_parent(), head, dir * 6.0 + _knock + Vector3.UP * 4.0)
	_remove_part("head")
	Gore.burst(get_parent(), neck, Vector3.UP, 45)
	Sfx.play_at(get_parent(), "crunch", point, 3.0, 0.8)
	died.emit("head")
	Gore.hit_stop(get_tree(), 0.06)
	_collapse(dir * 1.5 + _knock * 1.2)


func _die_body(point: Vector3, dir: Vector3) -> void:
	dead = true
	Gore.burst(get_parent(), point, dir, 35)
	Sfx.play_at(get_parent(), "crunch", point, 0.0, 0.9)
	died.emit("torso")
	Gore.hit_stop(get_tree(), 0.04)
	_collapse(dir * 3.0 + _knock * 1.5)


## Тело разваливается: каждая часть отлетает отдельным физическим куском.
func _collapse(impulse: Vector3) -> void:
	for zone in ["head", "arm_l", "arm_r", "leg_l", "leg_r", "torso"]:
		if not parts.has(zone):
			continue
		var part: Node3D = parts[zone]
		Gore.detach(get_parent(), part, impulse + Vector3(randf_range(-1, 1), randf_range(0, 1.5), randf_range(-1, 1)))
		part.get_parent().remove_child(part)
		part.queue_free()
	parts.clear()
	queue_free()


## Ползёт: на уцелевшей ноге или, если ног не осталось, на руках.
func _start_crawl() -> void:
	knocked_down = 0.0
	var has_l := parts.has("leg_l")
	var has_r := parts.has("leg_r")
	crawl_style = "arms" if not (has_l or has_r) else ("left" if has_l else "right")
	crawling = true
	var tilt := -1.5 if crawl_style == "arms" else -1.3
	var tween := create_tween().set_parallel()
	tween.tween_property(body, "rotation:x", tilt, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(body, "position:y", 0.2, 0.35)
	body.rotation.z = 0.0
	_capsule.height = 0.8
	_capsule_node.position.y = 0.4


func _remove_part(zone: String) -> void:
	var part: Node3D = parts[zone]
	var holder: Node3D = part.get_parent()
	var at := part.position
	parts.erase(zone)
	zone_hp.erase(zone)
	holder.remove_child(part)
	part.queue_free()
	# Красный обрубок, из которого ещё какое-то время хлещет кровь.
	var stump := Kit.add(holder, Kit.sphere(0.09), Gore.blood_material(), at, Vector3.ZERO, Vector3(1, 0.7, 1))
	var out := Vector3.UP if zone == "head" else (Vector3.DOWN if zone.begins_with("leg") else Vector3(signf(at.x), 0, 0))
	Gore.bleed(holder, at, out, 5.0, 2.0)
	stump.name = "Stump_" + zone
	_stumps += 1


func _attack_damage() -> float:
	var arms := int(parts.has("arm_l")) + int(parts.has("arm_r"))
	return ATTACK_DAMAGE * maxf(0.25, arms / 2.0)


func _nearest_player():
	var best = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.downed:
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best
