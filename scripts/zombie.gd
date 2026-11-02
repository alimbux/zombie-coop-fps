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
const MAX_WOUNDS := 22
## Сколько ран на части тела, после которых одежда в этом месте пропитывается кровью.
const SOAK_EVERY := 3
## Локоть: где у руки шарнир предплечья (по оси руки от плеча).
const ELBOW_Y := -0.3
## Когда у руки остаётся меньше этой доли прочности, пули отрывают предплечье с кистью.
const FOREARM_TEAR := 0.6
const MAX_KNOCK := 14.0
## Если отдача разогнала зомби сильнее этого (дробовик в упор), он падает навзничь.
const KNOCKDOWN_SPEED := 9.0
const KNOCKDOWN_TIME := 1.4
## Насколько далеко от центра головы должна пройти пуля, чтобы задеть её вскользь.
const GLANCE_DISTANCE := 0.09
## На сколько опускается тело, когда зомби стоит на коленях, и где колено в осях тела.
const KNEEL_SINK := 0.4
const KNEE_POS := Vector3(0.0, 0.46, 0.0)
## Сколько трупов лежит на уровне одновременно: самые старые убираются.
const MAX_CORPSES := 30
## Прочность трупа: сколько ещё нужно всадить, чтобы он развалился на куски.
const CORPSE_HP := 160.0

## pivot — шарнир (у головы и рук — относительно торса), size/center — зона попадания
## относительно шарнира.
const ZONES := {
	"torso": {"pivot": Vector3(0.0, 0.88, 0.0), "size": Vector3(0.5, 0.66, 0.32), "center": Vector3(0.0, 0.32, 0.0), "hp": 260.0, "mult": 1.0},
	"head": {"pivot": Vector3(0.0, 0.6, 0.0), "size": Vector3(0.3, 0.34, 0.32), "center": Vector3(0.0, 0.16, -0.02), "hp": 110.0, "mult": 1.5},
	"arm_l": {"pivot": Vector3(-0.25, 0.5, 0.0), "size": Vector3(0.15, 0.72, 0.15), "center": Vector3(0.0, -0.34, 0.0), "hp": 70.0, "mult": 1.0},
	"arm_r": {"pivot": Vector3(0.25, 0.5, 0.0), "size": Vector3(0.15, 0.72, 0.15), "center": Vector3(0.0, -0.34, 0.0), "hp": 70.0, "mult": 1.0},
	"leg_l": {"pivot": Vector3(-0.12, 0.88, 0.0), "size": Vector3(0.2, 0.88, 0.24), "center": Vector3(0.0, -0.44, -0.02), "hp": 90.0, "mult": 1.0},
	"leg_r": {"pivot": Vector3(0.12, 0.88, 0.0), "size": Vector3(0.2, 0.88, 0.24), "center": Vector3(0.0, -0.44, -0.02), "hp": 90.0, "mult": 1.0},
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
## Сколько ран на каждой части тела (для пропитывания одежды кровью).
var _part_wounds := {}
## Насколько разворочена каждая часть тела (0 — нет, 1 — сильно, 2 — в клочья).
var _gore_stage := {}
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
## Кого уже сбил, пока летит от удара (чтобы не толкать одного дважды).
var _bumped: Array = []
## Насколько расслаблены руки (1 — болтаются свободно: летит от удара или лежит).
var _flail := 0.0
var _arm_state := {}
var _arm_pose := {}
## Вращение всего тела вокруг вертикали, пока летит или лежит после удара.
var _spin := 0.0
## Угол и скорость опрокидывания при падении и направление падения в осях зомби.
var _fall := 0.0
var _fall_vel := 0.0
var _fall_dir := Vector2(0, 1)
## Длина рук для расчёта качания (не видимая): у каждой руки своя частота.
var _arm_len := {"arm_l": 0.35, "arm_r": 0.35}
var _shoulder_prev := {}
var _skin: StandardMaterial3D
var _capsule: CapsuleShape3D
var _capsule_node: CollisionShape3D
## Коленные суставы: голень с ботинком сгибается относительно бедра.
var _knees := {}
## Пружины рывков от попаданий: отклонение корпуса (наклон, поворот, крен) и головы
## (кивок, крен). Пружины мягкие, поэтому тело дёргается, перелетает и качается обратно.
var _jerk := Vector3.ZERO
var _jerk_v := Vector3.ZERO
var _hjerk := Vector2.ZERO
var _hjerk_v := Vector2.ZERO
## Стоит на коленях после ранения: сколько ещё, прежде чем опуститься на руки и поползти.
var _kneel := 0.0
## Насколько опустилось тело (подогнулись колени).
var _sink := 0.0
## Смерть: "buckle" — подгибаются колени, "topple" — валится, "lying" — лежит трупом.
var death_stage := ""
var _death_timer := 0.0
## Вокруг какой точки (в осях тела) опрокидывается: ступни или колени.
var _fall_pivot := Vector3.ZERO
var _torso_rest := Vector3.ZERO
var _landed := false
## Середина лежащего трупа.
var corpse_center := Vector3.ZERO

static var _corpses: Array = []


func _ready() -> void:
	add_to_group("zombies")
	_arm_len = {"arm_l": randf_range(0.28, 0.42), "arm_r": randf_range(0.28, 0.42)}
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
		# Предплечье с кистью на локте: пули отрывают его раньше, чем всю руку.
		var elbow := Kit.joint(arm, Vector3(0, ELBOW_Y, 0), "Elbow")
		elbow.set_meta("hit_size", Vector3(0.12, 0.42, 0.12))
		elbow.set_meta("hit_center", Vector3(0, -0.2, -0.02))
		Kit.add(elbow, Kit.capsule(0.048, 0.32), _skin, Vector3(0, -0.14, -0.02), Vector3(0.15, 0, 0))
		Kit.add(elbow, Kit.box(Vector3(0.075, 0.1, 0.035)), _skin, Vector3(0, -0.33, -0.04))
		Kit.add(elbow, Kit.box(Vector3(0.065, 0.07, 0.02)), Kit.shade(0.3), Vector3(0, -0.4, -0.06), Vector3(0.6, 0, 0))
		if randf() < 0.45:
			# Пальцы в крови.
			Kit.add(elbow, Kit.box(Vector3(0.068, 0.04, 0.024)), Gore.blood_material(), Vector3(0, -0.43, -0.075), Vector3(0.6, 0, 0))
		if randf() < 0.25:
			# Сломанная кость торчит из предплечья.
			Kit.add(elbow, Kit.capsule(0.016, 0.12), bone, Vector3(0.03, -0.12, -0.06), Vector3(0.9, 0, 0.5))
			Kit.add(elbow, Kit.sphere(0.03), Gore.blood_material(), Vector3(0.02, -0.12, -0.04), Vector3.ZERO, Vector3(1, 1, 0.5))
		Kit.add(elbow, Kit.sphere(0.03), rot, Vector3(randf_range(-0.03, 0.03), randf_range(-0.25, -0.05), -0.04), Vector3.ZERO, Vector3(1, 1.4, 0.5))

	for zone in ["leg_l", "leg_r"]:
		var leg := _pivot(zone, body)
		Kit.add(leg, Kit.capsule(0.076, 0.46), pants, Vector3(0, -0.21, 0))
		# Голень на коленном суставе: зомби может упасть на колени и ползти на четвереньках.
		var knee := Kit.joint(leg, Vector3(0, -0.42, 0), "Knee")
		Kit.add(knee, Kit.capsule(0.063, 0.44), pants if randf() < 0.7 else _skin, Vector3(0, -0.2, 0.02))
		Kit.add(knee, Kit.box(Vector3(0.1, 0.07, 0.23)), dark if randf() < 0.75 else _skin, Vector3(0, -0.43, -0.05))
		_knees[zone] = knee


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
		_corpse_process(delta)
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
	_bump_others()
	_stagger = maxf(0.0, _stagger - delta * 2.0)
	_flinch = move_toward(_flinch, 0.0, delta * 3.0)
	if knocked_down > 0.0:
		# Лежит после удара дробью и встаёт.
		knocked_down -= delta
		rotate_y(_spin * delta)
		_spin *= exp(-delta * 2.0)
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
	if _kneel > 0.0:
		_kneel -= delta
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
			# Пока отшатывается от попаданий, вперёд почти не идёт; стоя на коленях — стоит.
			var speed := _move_speed() * (1.0 - minf(_stagger, 0.85))
			if _kneel > 0.0:
				speed = 0.0
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
	if crawl_style == "knees":
		# На четвереньках: шаг рукой и коленом — рывок, между шагами почти стоит.
		surge = 0.4 + 1.1 * absf(sin(_phase))
	elif crawl_style == "arms":
		surge = 0.25 + 1.2 * absf(cos(_phase))
	else:
		surge = 0.35 + 1.3 * maxf(0.0, sin(_phase))
	var arms := int(parts.has("arm_l")) + int(parts.has("arm_r"))
	var factor := 0.75 if crawl_style == "arms" else (1.3 if crawl_style == "knees" else 1.0)
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
	_update_jerk(delta)
	if crawling:
		_animate_crawl(s, delta)
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
			# Поза, к которой тянут мышцы; саму руку двигает _animate_flail.
			_arm_pose[zone] = Vector2(reach + sway, 0.08 if zone == "arm_l" else -0.08)
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
	# Отшатывается от попадания: корпус дёргается туда, куда толкнула пуля, перелетает
	# и качается обратно, голова мотается отдельно.
	if torso:
		torso.rotation.x += _stagger * 0.35 + _jerk.x
		torso.rotation.z += _jerk.z
		torso.rotation.y = _flinch + _jerk.y
	if parts.has("head"):
		parts["head"].rotation.x = 0.15 + _stagger * 0.3 + _hjerk.x
		parts["head"].rotation.z += _hjerk.y
	for zone in _knees:
		_knees[zone].rotation.x = 0.0
	_animate_flail(delta)
	body.position.y = absf(s) * 0.03 * walking
	if gait == "limp":
		body.position.y = -maxf(0.0, -s) * 0.06 * walking
	_animate_fall(delta)


## Падение — опрокидывание тела вокруг ступней, как у палки, поставленной на пол:
## толчок даёт начальное вращение, ноги тормозят о пол, а верх тела продолжает
## лететь, дальше заваливает гравитация (чем ниже, тем быстрее). Падает в ту сторону,
## куда толкнули, ударяется о пол, немного отскакивает и затихает. Потом встаёт.
const FALL_COM := 0.95
const FALL_GROUND := 1.45
const GET_UP_STIFF := 40.0

func _start_fall() -> void:
	var d: Vector3 = global_transform.basis.inverse() * Vector3(_knock.x, 0.0, _knock.z)
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3.BACK
	d = d.normalized()
	if _fall < 0.2:
		_fall_dir = Vector2(d.x, d.z)
	_fall_vel = maxf(_fall_vel, clampf(_knock.length() * 0.2, 0.8, 4.0))


func _animate_fall(delta: float) -> void:
	if knocked_down > 0.35:
		# Гравитация опрокидывает, торможение ног о пол переворачивает верх вперёд по ходу.
		var alpha := 9.8 / FALL_COM * sin(maxf(_fall, 0.05))
		alpha += 0.5 * 4.5 * _knock.length() * cos(_fall) / FALL_COM
		_fall_vel += alpha * delta
		_fall += _fall_vel * delta
		if _fall >= FALL_GROUND:
			_fall = FALL_GROUND
			if _fall_vel > 1.5:
				# Удар о пол: тело подскакивает, скольжение гасится трением.
				Sfx.play_at(get_parent(), "splat", global_position + Vector3.UP * 0.2, -6.0, 0.45)
				_fall_vel = -_fall_vel * 0.28
				_knock *= 0.55
				_spin *= 0.4
				if parts.has("head"):
					parts["head"].rotation.x += 0.6
			else:
				_fall_vel = 0.0
	else:
		# Поднимается: мышцы тянут обратно в вертикаль.
		_fall_vel += (-GET_UP_STIFF * _fall - 2.0 * sqrt(GET_UP_STIFF) * _fall_vel) * delta
		_fall += _fall_vel * delta
		if _fall < 0.0:
			_fall = 0.0
			_fall_vel = 0.0
	body.rotation.x = _fall * _fall_dir.y
	body.rotation.z = -_fall * _fall_dir.x
	if _fall > 0.3:
		body.position.y = 0.12 * clampf(_fall / FALL_GROUND, 0.0, 1.0)


## Руки — маятники на плечах. Каждую руку тянет к позе из анимации пружина-мышца,
## а на неё действуют гравитация и инерция: плечо резко дёрнулось назад —
## рука по инерции уходит вперёд, тело тормозит — рука догоняет и качается обратно,
## тело падает навзничь — руки валятся под своим весом. Пока зомби летит от удара
## или лежит, мышцы почти расслаблены и руки болтаются свободно.
const ARM_STIFF := 150.0
const ARM_LIMP := 3.0
const ARM_MAX_SPIN := 14.0

func _animate_flail(delta: float) -> void:
	var target := clampf((_knock.length() - 1.5) / 5.0, 0.0, 1.0)
	if knocked_down > 0.0 or dead:
		target = 1.0
	_flail = move_toward(_flail, target, delta * (10.0 if target > _flail else 1.2))
	if delta <= 0.0:
		return
	var g := Vector3(0.0, -9.8, 0.0)
	for zone in ["arm_l", "arm_r"]:
		if not parts.has(zone):
			continue
		var arm: Node3D = parts[zone]
		var shoulder := arm.global_position
		var acc := Vector3.ZERO
		if _shoulder_prev.has(zone):
			var prev: Array = _shoulder_prev[zone]
			var vel: Vector3 = (shoulder - prev[0]) / delta
			acc = ((vel - prev[1]) / delta).limit_length(400.0)
			_shoulder_prev[zone] = [shoulder, vel]
		else:
			_shoulder_prev[zone] = [shoulder, Vector3.ZERO]
		# Гравитация с учётом ускорения плеча, в осях родителя (корпуса).
		var basis := (arm.get_parent() as Node3D).global_transform.basis.orthonormalized()
		var ge: Vector3 = basis.inverse() * (g - acc)
		var gs: Vector3 = basis.inverse() * g
		var st: Array = _arm_state.get(zone, [arm.rotation.x, 0.0, arm.rotation.z, 0.0])
		var pose: Vector2 = _arm_pose.get(zone, Vector2(arm.rotation.x, arm.rotation.z))
		var pose_x := pose.x
		var pose_z := pose.y
		var k := lerpf(ARM_STIFF, ARM_LIMP, _flail)
		var c := lerpf(2.0 * sqrt(ARM_STIFF), 0.7, _flail)
		var hold := 1.0 - _flail
		# Вперёд-назад: рука (0, -cos, -sin) после поворота на угол вокруг X.
		var arm_len: float = _arm_len[zone]
		var ax: float = _arm_torque_x(st[0], ge) / arm_len + k * (pose_x - st[0]) - c * st[1] - hold * _arm_torque_x(pose_x, gs) / arm_len
		# Вбок: рука (sin, -cos, 0) после поворота вокруг Z.
		# Поднятая вперёд рука качается вбок слабее (короче плечо силы) — качания
		# вперёд и вбок связаны, и движение получается неповторяющимся.
		var lever := maxf(0.2, absf(cos(st[0])))
		var az: float = _arm_torque_z(st[2], ge) * lever / arm_len + k * (pose_z - st[2]) - c * st[3] - hold * _arm_torque_z(pose_z, gs) / arm_len
		st[1] = clampf(st[1] + ax * delta, -ARM_MAX_SPIN, ARM_MAX_SPIN)
		st[3] = clampf(st[3] + az * delta, -ARM_MAX_SPIN, ARM_MAX_SPIN)
		st[0] += st[1] * delta
		st[2] += st[3] * delta
		# Сустав не выворачивается: упор гасит скорость.
		var lim_x := Vector2(-1.0, 3.1)
		var lim_z := Vector2(-1.5, 0.25) if zone == "arm_l" else Vector2(-0.25, 1.5)
		if st[0] < lim_x.x or st[0] > lim_x.y:
			st[0] = clampf(st[0], lim_x.x, lim_x.y)
			st[1] *= -0.2
		if st[2] < lim_z.x or st[2] > lim_z.y:
			st[2] = clampf(st[2], lim_z.x, lim_z.y)
			st[3] *= -0.2
		_arm_state[zone] = st
		arm.rotation.x = st[0]
		arm.rotation.z = st[2]


static func _arm_torque_x(angle: float, ge: Vector3) -> float:
	return -cos(angle) * ge.z + sin(angle) * ge.y


static func _arm_torque_z(angle: float, ge: Vector3) -> float:
	return sin(angle) * ge.y + cos(angle) * ge.x


func _animate_crawl(s: float, delta: float) -> void:
	var torso: Node3D = parts["torso"]
	match crawl_style:
		"knees":
			_animate_knees(s, delta)
			return
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
		parts["head"].rotation.x = -0.8 + _hjerk.x
		parts["head"].rotation.z = _head_tilt * 0.5 + _hjerk.y
	torso.rotation += _jerk * 0.6
	var leg_left := "leg_l" if crawl_style == "left" else "leg_r"
	if _knees.has(leg_left):
		_knees[leg_left].rotation.x = -0.35 - 0.25 * s


## На коленях, потом на четвереньках. Сначала тело оседает (подгибаются колени),
## зомби покачивается, стоя на коленях, руки висят. Потом валится вперёд на руки
## и ползёт: рука и противоположное колено шагают вместе, спина ходит вверх-вниз.
func _animate_knees(s: float, delta: float) -> void:
	var torso: Node3D = parts["torso"]
	_sink = move_toward(_sink, KNEEL_SINK, delta * 2.6)
	var bend := _sink / KNEEL_SINK
	# 1 — стоит на коленях прямо, 0 — на четвереньках.
	var up := smoothstep(0.0, 0.45, _kneel)
	var down := 1.0 - up
	body.rotation = Vector3.ZERO
	body.position = Vector3(0, -_sink + down * absf(s) * 0.03, 0)
	for zone in ["leg_l", "leg_r"]:
		if not parts.has(zone):
			continue
		var side := 1.0 if zone == "leg_l" else -1.0
		parts[zone].rotation = Vector3(down * (0.15 + 0.22 * s * side), 0, 0.05 * side)
		_knees[zone].rotation.x = -1.5 * bend + down * 0.18 * s * side
	var sway := sin(_phase * 0.7)
	torso.rotation = Vector3(lerpf(HUNCH - 0.1, -1.08, down) + _jerk.x, _jerk.y + down * s * 0.08, up * sway * 0.14 + _jerk.z)
	for zone in ["arm_l", "arm_r"]:
		if parts.has(zone):
			var side := 1.0 if zone == "arm_l" else -1.0
			var hang := 0.25 + sway * 0.1 * side
			parts[zone].rotation = Vector3(lerpf(hang, 1.08 - 0.38 * s * side, down), 0, 0.1 * side)
	if parts.has("head"):
		parts["head"].rotation.x = lerpf(0.25 + sway * 0.1, 0.95, down) + _hjerk.x
		parts["head"].rotation.z = _head_tilt + _hjerk.y


## Пружины рывков: тянут отклонение обратно к нулю, но слабо затухают — тело
## перелетает положение равновесия и пару раз качается.
const JERK_STIFF := 120.0
const JERK_DAMP := 9.0
const HEAD_STIFF := 150.0
const HEAD_DAMP := 8.0

func _update_jerk(delta: float) -> void:
	_jerk_v += (-JERK_STIFF * _jerk - JERK_DAMP * _jerk_v) * delta
	_jerk += _jerk_v * delta
	_jerk = _jerk.clamp(Vector3(-1.2, -0.9, -0.8), Vector3(1.0, 0.9, 0.8))
	_hjerk_v += (-HEAD_STIFF * _hjerk - HEAD_DAMP * _hjerk_v) * delta
	_hjerk += _hjerk_v * delta
	_hjerk = _hjerk.clamp(Vector2(-1.0, -0.9), Vector2(1.3, 0.9))


## Рывок от пули: куда и как дёрнется тело, зависит от зоны и точки попадания.
## В грудь — корпус откидывается назад, голова запрокидывается; в живот — сгибается
## пополам; в бок — разворачивает и кренит; в голову — голову резко отбрасывает;
## в ногу — заваливается вперёд на раненую ногу; в руку — руку отшвыривает.
func _jolt(zone: String, point: Vector3, dir: Vector3, force: float) -> void:
	var ld: Vector3 = global_transform.basis.orthonormalized().inverse() * dir.normalized()
	var f := clampf(force, 0.6, 8.0)
	var lp: Vector3 = to_local(point)
	match zone:
		"head":
			_hjerk_v += Vector2(ld.z * 4.5, -ld.x * 3.0 + randf_range(-1.5, 1.5)) * f
			_jerk_v += Vector3(ld.z * 1.0, 0, -ld.x * 0.6) * f
		"torso":
			var belly: bool = parts.has("torso") and (parts["torso"] as Node3D).to_local(point).y < 0.22
			if belly and randf() < 0.7:
				# В живот: сгибается пополам, голова падает вперёд.
				_jerk_v.x -= absf(ld.z) * 2.6 * f
				_hjerk_v.x -= 1.6 * f
			else:
				_jerk_v.x += ld.z * 2.8 * f
				_hjerk_v.x += ld.z * 2.4 * f
			_jerk_v.z += -ld.x * 1.6 * f
			_jerk_v.y += clampf(-lp.x * 6.0, -1.5, 1.5) * signf(ld.z if absf(ld.z) > 0.1 else 1.0) * f
		"leg_l", "leg_r":
			var side := 1.0 if zone == "leg_l" else -1.0
			_jerk_v += Vector3(-1.6, 0, side * 1.4) * f
			_hjerk_v.x -= 1.0 * f
		"arm_l", "arm_r":
			var st: Array = _arm_state.get(zone, [])
			if st.size() == 4:
				st[1] -= ld.z * 3.0 * f
				st[3] += -ld.x * 2.0 * f
			_jerk_v.y += (0.8 if zone == "arm_l" else -0.8) * ld.z * f
	_jerk_v = _jerk_v.limit_length(16.0)
	_hjerk_v = _hjerk_v.limit_length(18.0)


## Подогнулись колени: зомби оседает на колени, покачивается и опускается на руки.
func _start_kneel() -> void:
	if crawling or dead or knocked_down > 0.0 or _fall > 0.05:
		return
	crawling = true
	crawl_style = "knees"
	_kneel = randf_range(0.7, 1.4)
	_stagger = 0.0
	_arm_state.clear()
	_capsule.height = 1.1
	_capsule_node.position.y = 0.55
	Sfx.groan(self, "pain", 0.0)


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
	push(_glance_dir(point, dir), force)
	_jolt(zone, point, dir, force)
	Gore.splash(get_parent(), point, dir, 24)
	Gore.chunks(get_parent(), point, dir, randi_range(2, 5) + (3 if zone == "head" else 0))
	if zone == "head" and not skull_open and is_glancing(point, dir):
		_open_skull(point, dir)
		return false
	var def: Dictionary = ZONES[zone]
	zone_hp[zone] -= damage * float(def["mult"])
	if zone_hp[zone] > 0.0:
		_add_wound(zone, point, dir)
		if zone.begins_with("arm") and zone_hp[zone] < float(def["hp"]) * FOREARM_TEAR:
			_tear_forearm(zone, dir)
		# Разбитая пулями голова раскалывается: верх черепа слетает, но зомби ещё жив.
		if zone == "head" and not skull_open and zone_hp["head"] < float(def["hp"]) * 0.5:
			_open_skull(point, dir)
		if loud:
			_hit_sound(zone, point)
			if randf() < 0.55:
				Sfx.groan(self, "pain", -2.0)
		# Простреленная нога или изрешечённый корпус: подгибаются колени,
		# зомби падает на колени и дальше ползёт на четвереньках.
		if zone.begins_with("leg") and randf() < 0.6:
			_start_kneel()
		elif zone == "torso" and zone_hp[zone] < float(def["hp"]) * 0.45 and randf() < 0.5:
			_start_kneel()
		return false
	match zone:
		"head":
			_die_headshot(point, dir)
		"torso":
			_die_body(point, dir)
		_:
			_sever(zone, point, dir)
	return dead


## Летящий от удара зомби своим телом сбивает тех, в кого врезался, и они летят дальше.
const BUMP_SPEED := 5.0
const BUMP_RADIUS := 0.85
const BUMP_KEEP := 0.85

func _bump_others() -> void:
	var speed := _knock.length()
	if speed < BUMP_SPEED:
		_bumped.clear()
		return
	var dir := _knock / speed
	for other in get_tree().get_nodes_in_group("zombies"):
		if other == self or other.dead or _bumped.has(other):
			continue
		var to: Vector3 = other.global_position - global_position
		to.y = 0.0
		if to.length() > BUMP_RADIUS or to.dot(dir) < 0.0:
			continue
		_bumped.append(other)
		other._bumped.append(self)
		# Как бильярдные шары: сбитый летит по линии между центрами, ударивший
		# отскакивает в другую сторону. Чем больше вскользь, тем сильнее разлёт.
		var line := to.normalized()
		var push_dir := (line * 0.75 + dir * 0.25).normalized()
		other.push(push_dir, speed * BUMP_KEEP)
		var deflect := dir - line * dir.dot(line)
		_knock = (dir * 0.4 + deflect * 1.2).normalized() * speed * 0.55
		Sfx.play_at(get_parent(), "splat", other.global_position + Vector3.UP, -6.0, 0.7)
		Sfx.groan(other, "pain", -2.0)
		speed = _knock.length()
		if speed < BUMP_SPEED:
			return


## Направление толчка от пули: попадание сбоку от центра тела уводит зомби вбок.
func _glance_dir(point: Vector3, dir: Vector3) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var off := point - global_position
	off.y = 0.0
	var side := off - flat * off.dot(flat)
	var amount := clampf(side.length() / 0.3, 0.0, 1.0) * 0.6
	if side.length() < 0.001:
		return flat
	return (flat + side.normalized() * amount).normalized()


## Удар ногой: сильный толчок с падением навзничь и немного урона корпусу.
func kicked(dir: Vector3, speed: float, damage: float) -> void:
	if dead:
		return
	alert()
	_bumped.clear()
	push(dir, speed)
	# Удар ногой сильнее предела отдачи от пуль.
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	_knock = flat * speed * (0.4 if crawling else 1.0)
	if not crawling:
		knocked_down = KNOCKDOWN_TIME
		_start_fall()
	if zone_hp.has("torso"):
		zone_hp["torso"] = maxf(1.0, zone_hp["torso"] - damage)
	Sfx.groan(self, "pain", 0.0)


## Отдача: попадание толкает зомби по направлению выстрела. Лежачего — слабее.
func push(dir: Vector3, force: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	_knock += flat * force * (0.4 if crawling else 1.0)
	_knock = _knock.limit_length(MAX_KNOCK)
	_stagger = minf(1.0, _stagger + force * 0.25)
	_flinch = clampf(_flinch + randf_range(-0.25, 0.25) * force, -0.6, 0.6)
	if force > 4.0:
		# Сильный толчок закручивает тело и дёргает каждую руку по-своему:
		# дальше их раскачивают инерция, вращение и гравитация.
		_spin += randf_range(-0.35, 0.35) * force
		for zone in _arm_state:
			var st: Array = _arm_state[zone]
			st[1] += randf_range(-0.6, 0.6) * force
			st[3] += randf_range(-0.45, 0.45) * force
	if not crawling and knocked_down <= 0.0 and _knock.length() >= KNOCKDOWN_SPEED:
		knocked_down = KNOCKDOWN_TIME
		_start_fall()


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
## Рваная рана, а не пятно: чёрная дыра, вокруг неровный край из клочьев крови и мяса,
## по телу веером брызги в сторону полёта пули, вниз тянется потёк. Пуля в корпус или
## голову часто выходит насквозь — со спины рана больше, с вырванным мясом.
## Каждые несколько ран на части тела пропитывают кровью ещё кусок одежды, а сильно
## изрешечённая часть тела разворочена: рёбра наружу, кость из руки или ноги.
func _add_wound(zone: String, point: Vector3, dir: Vector3) -> void:
	if not parts.has(zone):
		return
	var part: Node3D = parts[zone]
	_part_wounds[zone] = int(_part_wounds.get(zone, 0)) + 1
	if _part_wounds[zone] % SOAK_EVERY == 0:
		_soak(part)
	_add_gore_stage(zone)
	if _wounds >= MAX_WOUNDS:
		return
	_wounds += 1
	var local := part.to_local(point)
	var local_dir: Vector3 = (part.global_transform.basis.orthonormalized().inverse() * dir).normalized()
	var center: Vector3 = ZONES[zone]["center"]
	var out: Vector3 = local - center
	out = out.normalized() if out.length() > 0.02 else -local_dir
	if out.dot(-local_dir) < 0.0:
		out = (out - local_dir).normalized()
	var big := 1.6 if zone == "torso" else (1.3 if zone == "head" else 1.1)
	_wound_mesh(part, local, out, local_dir, big, false)
	if randf() < 0.6:
		# Потёк вниз от раны.
		var run := Kit.add(part, Kit.capsule(0.011, randf_range(0.1, 0.22)), Gore.blood_material(), local + Vector3(0, -0.06, 0) + out * 0.01, Vector3.ZERO, Vector3(1, 0.2, 1))
		run.create_tween().tween_property(run, "scale:y", 1.0, randf_range(1.5, 3.0))
	if (zone == "torso" or zone == "head") and randf() < 0.65:
		# Выходное отверстие на другой стороне: больше и рванее.
		var depth: float = (ZONES[zone]["size"] as Vector3).z * 0.95
		var exit_at := local + local_dir * depth
		_wound_mesh(part, exit_at, local_dir, local_dir, big * 1.5, true)
	if _wounds <= 12 or randf() < 0.3:
		Gore.bleed(part, local, out, randf_range(2.5, 4.0))


## Сама рана в осях части тела: at — точка на поверхности, out — наружу, along — полёт пули.
func _wound_mesh(part: Node3D, at: Vector3, out: Vector3, along: Vector3, size: float, exit: bool) -> void:
	var w := Node3D.new()
	w.name = "Wound"
	part.add_child(w)
	w.position = at
	w.basis = Gore.basis_from_up(out).rotated(out, randf_range(0.0, TAU))
	var flat := Vector3(1, 0.3, 1)
	# Дыра: чёрная глубина, вокруг тёмное мясо.
	Kit.add(w, Kit.sphere(0.02 * size), Gore.hole_material(), Vector3(0, 0.006, 0), Vector3.ZERO, Vector3(1.0, 0.35, randf_range(1.0, 1.5)))
	Kit.add(w, Kit.sphere(0.032 * size), Gore.dark_blood_material(), Vector3.ZERO, Vector3.ZERO, Vector3(1.2, 0.3, 1.0))
	# Рваный край: клочья разного размера и формы.
	var shreds := randi_range(5, 8) + (3 if exit else 0)
	for i in shreds:
		var a := TAU * i / shreds + randf_range(-0.3, 0.3)
		var r := randf_range(0.024, 0.045) * size
		var mat: Material = [Gore.blood_material(), Gore.dark_blood_material(), Gore.meat_material()].pick_random()
		var shred := Kit.add(w, Kit.sphere(randf_range(0.01, 0.022) * size), mat, Vector3(cos(a) * r, randf_range(0.0, 0.008), sin(a) * r), Vector3(0, randf_range(0, TAU), 0), Vector3(randf_range(0.6, 1.8), 0.35, randf_range(0.5, 1.4)))
		shred.rotation.y = -a
	# Мясо торчит наружу (из выходной раны — больше).
	for i in randi_range(1, 2) + (3 if exit else 0):
		var a := randf_range(0.0, TAU)
		var r := randf_range(0.0, 0.03) * size
		Kit.add(w, Kit.box(Vector3(randf_range(0.012, 0.03), randf_range(0.01, 0.03), randf_range(0.012, 0.03)) * size), Gore.meat_material(), Vector3(cos(a) * r, randf_range(0.004, 0.018) * size, sin(a) * r), Vector3(randf_range(-0.8, 0.8), randf_range(0, TAU), randf_range(-0.8, 0.8)))
	# Брызги по телу веером в сторону полёта пули (у выходной — от раны во все стороны).
	var t: Vector3 = w.basis.inverse() * along
	t.y = 0.0
	var tangent := t.normalized() if t.length() > 0.05 else Vector3(1, 0, 0)
	for i in randi_range(3, 6):
		var d := tangent.rotated(Vector3.UP, randf_range(-0.7, 0.7)) if not exit else Vector3(1, 0, 0).rotated(Vector3.UP, randf_range(0, TAU))
		var dist := randf_range(0.05, 0.16) * size
		var drop := Kit.add(w, Kit.sphere(randf_range(0.005, 0.012) * size), Gore.blood_material(), d * dist + Vector3(0, 0.002, 0), Vector3.ZERO, Vector3(1.0, 0.3, randf_range(1.8, 3.2)))
		drop.rotation.y = atan2(d.x, d.z)
	w.scale = Vector3.ONE * 0.4
	w.create_tween().tween_property(w, "scale", Vector3.ONE, 0.12)


## Сильно изрешечённая часть тела разворочена. Ступени по оставшейся прочности.
func _add_gore_stage(zone: String) -> void:
	if not zone_hp.has(zone) or not parts.has(zone):
		return
	var frac: float = zone_hp[zone] / float(ZONES[zone]["hp"])
	var stage := 0
	if frac < 0.55:
		stage = 1
	if frac < 0.25:
		stage = 2
	var had: int = _gore_stage.get(zone, 0)
	if stage <= had:
		return
	_gore_stage[zone] = stage
	var part: Node3D = parts[zone]
	match zone:
		"torso":
			if stage >= 1 and had < 1:
				# Грудь разворочена: тёмная яма, в ней рёбра.
				var side: float = [-1.0, 1.0].pick_random()
				var at := Vector3(0.08 * side, 0.36, -0.14)
				Kit.add(part, Kit.sphere(0.09), Gore.dark_blood_material(), at, Vector3.ZERO, Vector3(1.0, 1.1, 0.35))
				Kit.add(part, Kit.sphere(0.06), Gore.hole_material(), at + Vector3(0, 0, -0.012), Vector3.ZERO, Vector3(1.0, 1.0, 0.3))
				for i in 3:
					Kit.add(part, Kit.capsule(0.012, 0.13), Gore.bone_material(), at + Vector3(0, 0.05 - i * 0.045, -0.025), Vector3(0, 0, PI / 2 + randf_range(-0.2, 0.2)))
				for i in 4:
					Kit.add(part, Kit.box(Vector3(0.03, 0.025, 0.03)), Gore.meat_material(), at + Vector3(randf_range(-0.07, 0.07), randf_range(-0.07, 0.07), -0.03), Vector3(randf(), randf(), randf()))
			if stage >= 2:
				# Живот вспорот: кишки свисают.
				Kit.add(part, Kit.sphere(0.08), Gore.hole_material(), Vector3(-0.02, 0.12, -0.13), Vector3.ZERO, Vector3(1.3, 0.9, 0.3))
				for i in 4:
					var gut := Kit.add(part, Kit.capsule(0.026, randf_range(0.18, 0.34)), Gore.meat_material(), Vector3(-0.06 + i * 0.035, 0.03 - i * 0.02, -0.16), Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.5, 0.5)))
					gut.scale = Vector3(1, 0.2, 1)
					gut.create_tween().tween_property(gut, "scale:y", 1.0, randf_range(0.6, 1.4))
		"arm_l", "arm_r", "leg_l", "leg_r":
			# Кость перебита и торчит из мяса.
			var holder: Node3D = part
			var y := randf_range(-0.2, -0.35) if zone.begins_with("arm") else randf_range(-0.15, -0.35)
			if zone.begins_with("leg") and _knees.has(zone) and stage >= 2:
				holder = _knees[zone]
				y = randf_range(-0.1, -0.25)
			var at := Vector3(0, y, -0.06)
			Kit.add(holder, Kit.sphere(0.05), Gore.dark_blood_material(), at + Vector3(0, 0, 0.01), Vector3.ZERO, Vector3(1.2, 1.4, 0.6))
			Kit.add(holder, Kit.capsule(0.017, 0.13), Gore.bone_material(), at + Vector3(0.01, 0.02, -0.03), Vector3(randf_range(0.6, 1.2), 0, randf_range(-0.6, 0.6)))
			for i in 3:
				Kit.add(holder, Kit.box(Vector3(0.025, 0.02, 0.025)), Gore.meat_material(), at + Vector3(randf_range(-0.03, 0.03), randf_range(-0.04, 0.04), -0.025), Vector3(randf(), randf(), randf()))
		"head":
			if stage >= 1 and had < 1:
				# Щека разорвана: дыра в лице, видны зубы.
				var x: float = [-0.06, 0.06].pick_random()
				Kit.add(part, Kit.sphere(0.045), Gore.hole_material(), Vector3(x, 0.09, -0.09), Vector3.ZERO, Vector3(0.8, 1.0, 0.6))
				Kit.add(part, Kit.sphere(0.055), Gore.dark_blood_material(), Vector3(x, 0.09, -0.08), Vector3.ZERO, Vector3(0.9, 1.1, 0.5))
				for i in 4:
					Kit.add(part, Kit.box(Vector3(0.012, 0.02, 0.012)), Gore.bone_material(), Vector3(x * 0.9, 0.075 + (i % 2) * 0.03, -0.11 + i * 0.008))


## Одна из деталей части тела (рукав, штанина, кусок рубашки) пропитывается кровью.
func _soak(part: Node3D) -> void:
	var meshes: Array = []
	for n in part.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.material_override != Gore.dark_blood_material() and m.material_override != Gore.blood_material() and m.name != "Cap":
			meshes.append(m)
	if meshes.is_empty():
		return
	var pick: MeshInstance3D = meshes.pick_random()
	pick.material_override = Gore.dark_blood_material() if randf() < 0.7 else Gore.blood_material()


## Скользящее попадание в голову или голова уже разбита пулями: верх черепа слетает,
## мозги вываливаются и стекают. Голова держится, но вдвое слабее.
func _open_skull(point: Vector3, dir: Vector3) -> void:
	skull_open = true
	zone_hp["head"] = maxf(1.0, minf(zone_hp["head"], float(ZONES["head"]["hp"]) * 0.5))
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


## Звук попадания зависит от зоны: голова — стук черепа, руки и ноги — то мясо,
## то кость, корпус — мясо, иногда с чавканьем. Сверху иногда шлёпают брызги.
## Каждый раз случайный вариант и высота, так что очередь не звучит как одна пуля.
func _hit_sound(zone: String, point: Vector3) -> void:
	var w := get_parent()
	var pitch := randf_range(0.82, 1.18)
	match zone:
		"head":
			Sfx.play_at(w, "hit_skull", point, -4.0, pitch)
		"torso":
			Sfx.play_at(w, "hit_flesh", point, -5.0, pitch * 0.92)
			if randf() < 0.35:
				Sfx.play_at(w, "squelch", point, -10.0, randf_range(0.85, 1.2))
		_:
			Sfx.play_at(w, "hit_bone" if randf() < 0.4 else "hit_flesh", point, -6.0, pitch * 1.08)
	if randf() < 0.45:
		Sfx.play_at(w, "spatter", point + Vector3.DOWN, -13.0, randf_range(0.9, 1.15))


## Предплечье с кистью отрывается: улетает куском, из локтя торчит раздробленная
## кость в клочьях мяса, хлещет кровь. Рука становится короче, попасть в неё труднее.
func _tear_forearm(zone: String, dir: Vector3) -> void:
	var arm: Node3D = parts.get(zone)
	if arm == null:
		return
	var elbow: Node3D = arm.get_node_or_null("Elbow")
	if elbow == null:
		return
	var at := elbow.global_position
	Gore.detach(get_parent(), elbow, dir * 3.5 + _knock + Vector3.UP * 2.0)
	arm.remove_child(elbow)
	elbow.queue_free()
	# Раны и потёки, что были на предплечье, уходят вместе с ним.
	for child in arm.get_children():
		if child is Node3D and not (child is Area3D) and (child as Node3D).position.y < ELBOW_Y + 0.02:
			child.queue_free()
	_ragged_stump(arm, Vector3(0, ELBOW_Y, 0), Vector3.DOWN, 0.8)
	Gore.burst(get_parent(), at, dir, 22)
	Gore.chunks(get_parent(), at, dir, 8)
	Sfx.play_at(get_parent(), "tear", at, -1.0, randf_range(0.9, 1.15))
	Sfx.play_at(get_parent(), "hit_bone", at, -5.0, randf_range(0.8, 1.0))
	Sfx.groan(self, "pain", 0.0)
	_arm_len[zone] = _arm_len[zone] * 0.55
	# Зона попадания — только плечо.
	for area in arm.get_children():
		if area is Area3D:
			area.position = Vector3(0, ELBOW_Y / 2.0, 0)
			var col: CollisionShape3D = area.get_child(0)
			(col.shape as BoxShape3D).size = Vector3(0.15, absf(ELBOW_Y) + 0.04, 0.15)
	arm.set_meta("hit_size", Vector3(0.15, absf(ELBOW_Y) + 0.04, 0.15))
	arm.set_meta("hit_center", Vector3(0, ELBOW_Y / 2.0, 0))


## Рваный обрубок: раздробленная кость, клочья мяса и кожи вокруг, бьёт кровь.
func _ragged_stump(holder: Node3D, at: Vector3, out: Vector3, size := 1.0) -> void:
	Kit.add(holder, Kit.sphere(0.055 * size), Gore.dark_blood_material(), at, Vector3.ZERO, Vector3(1.1, 0.6, 1.1))
	Kit.add(holder, Kit.capsule(0.017 * size, 0.11 * size), Gore.bone_material(), at + out * 0.05 * size, Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)))
	for i in randi_range(5, 8):
		var a := randf_range(0, TAU)
		var r := randf_range(0.03, 0.06) * size
		var mat: Material = [Gore.meat_material(), Gore.blood_material(), Gore.dark_blood_material(), _skin].pick_random()
		Kit.add(holder, Kit.box(Vector3(randf_range(0.015, 0.035), randf_range(0.03, 0.07), randf_range(0.015, 0.035)) * size), mat, at + Vector3(cos(a) * r, 0, sin(a) * r) + out * randf_range(0.0, 0.04) * size, Vector3(randf_range(-0.7, 0.7), a, randf_range(-0.7, 0.7)))
	Gore.bleed(holder, at, out, 5.0, 1.6)


func _sever(zone: String, point: Vector3, dir: Vector3) -> void:
	var part: Node3D = parts[zone]
	Gore.detach(get_parent(), part, dir * 3.0 + _knock + Vector3.UP * 2.0)
	Gore.burst(get_parent(), part.global_position, dir, 25)
	Gore.chunks(get_parent(), part.global_position, dir, 10)
	Sfx.play_at(get_parent(), "crunch", point, 0.0)
	Sfx.play_at(get_parent(), "tear", point, -3.0, randf_range(0.8, 1.05))
	Sfx.groan(self, "pain", 0.0)
	_remove_part(zone)
	if dead:
		return
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
	_become_corpse(dir, "head")


func _die_body(point: Vector3, dir: Vector3) -> void:
	dead = true
	Gore.burst(get_parent(), point, dir, 35)
	Sfx.play_at(get_parent(), "crunch", point, 0.0, 0.9)
	died.emit("torso")
	Gore.hit_stop(get_tree(), 0.04)
	_become_corpse(dir, "torso")


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
	_corpses.erase(self)
	queue_free()


## Ползёт: на уцелевшей ноге или, если ног не осталось, на руках.
func _start_crawl() -> void:
	knocked_down = 0.0
	_fall = 0.0
	_fall_vel = 0.0
	var has_l := parts.has("leg_l")
	var has_r := parts.has("leg_r")
	crawl_style = "arms" if not (has_l or has_r) else ("left" if has_l else "right")
	crawling = true
	_kneel = 0.0
	_sink = 0.0
	for z in _knees:
		_knees[z].rotation.x = 0.0
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
	_knees.erase(zone)
	holder.remove_child(part)
	part.queue_free()
	# Рваный обрубок: кость, клочья мяса и кожи, из него ещё какое-то время хлещет кровь.
	var stump := Kit.add(holder, Kit.sphere(0.08), Gore.blood_material(), at, Vector3.ZERO, Vector3(1, 0.6, 1))
	var out := Vector3.UP if zone == "head" else (Vector3.DOWN if zone.begins_with("leg") else Vector3(signf(at.x), 0, 0))
	_ragged_stump(holder, at, out, 1.4)
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


# --- Смерть и трупы -----------------------------------------------------------

## Тело не разлетается на куски, а падает целиком и остаётся лежать. Как падает:
## от выстрела в голову чаще валится как подкошенный по направлению пули, иногда
## сначала подгибаются колени; убитый в корпус оседает на колени, качается и падает
## лицом вперёд; сбитый дробью продолжает лететь; ползущий просто обмякает.
func _become_corpse(dir: Vector3, cause: String) -> void:
	dead = true
	remove_from_group("zombies")
	add_to_group("corpses")
	# Живые и игроки проходят сквозь труп (и спотыкаются о него), пол держит.
	collision_layer = 0
	collision_mask = 1
	_capsule.radius = 0.25
	_capsule.height = 0.5
	_capsule_node.position.y = 0.25
	_arm_state.clear()
	_shoulder_prev.clear()
	_flail = 1.0
	if zone_hp.has("torso"):
		zone_hp["torso"] = CORPSE_HP
	_corpses.append(self)
	while _corpses.size() > MAX_CORPSES:
		var old = _corpses.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var torso: Node3D = parts.get("torso")
	if torso:
		_torso_rest = torso.rotation
	_landed = false
	if crawling:
		death_stage = "slump"
		_death_timer = 0.0
		return
	if knocked_down > 0.0 or _knock.length() >= KNOCKDOWN_SPEED * 0.8:
		# Уже летит или падает: просто не встанет.
		if _fall < 0.05:
			_start_fall()
		death_stage = "topple"
		return
	var buckle_chance := 0.4 if cause == "head" else 0.75
	if randf() < buckle_chance:
		death_stage = "buckle"
		_death_timer = randf_range(0.35, 0.75)
	else:
		_topple_along(dir, 1.2)


func _topple_along(dir: Vector3, speed: float) -> void:
	var d: Vector3 = global_transform.basis.orthonormalized().inverse() * Vector3(dir.x, 0.0, dir.z)
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3.BACK
	d = d.normalized()
	_fall_dir = Vector2(d.x, d.z)
	_fall_pivot = Vector3.ZERO
	_fall_vel = maxf(_fall_vel, speed)
	death_stage = "topple"


func _corpse_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	velocity.x = _knock.x
	velocity.z = _knock.z
	# Лежачее тело быстро тормозит о пол.
	_knock *= exp(-delta * (4.5 if death_stage != "lying" else 9.0))
	move_and_slide()
	_update_jerk(delta)
	_animate_dead(delta)


func _animate_dead(delta: float) -> void:
	var torso: Node3D = parts.get("torso")
	match death_stage:
		"buckle":
			_death_timer -= delta
			_sink = move_toward(_sink, KNEEL_SINK, delta * 2.4)
			var bend := _sink / KNEEL_SINK
			for zone in _knees:
				parts[zone].rotation.x = move_toward(parts[zone].rotation.x, 0.0, delta * 3.0)
				_knees[zone].rotation.x = -1.5 * bend
			# Обмякает: корпус клонится вперёд и покачивается, голова падает.
			_torso_rest.x = lerpf(_torso_rest.x, -0.55, delta * 3.0)
			_torso_rest.z = sin(_phase * 2.0) * 0.12
			_phase += delta * 3.0
			body.rotation = Vector3.ZERO
			body.position = Vector3(0, -_sink, 0)
			if _death_timer <= 0.0:
				# Валится вперёд, немного вбок, вокруг коленей.
				_fall_dir = Vector2(randf_range(-0.5, 0.5), -1.0).normalized()
				_fall_pivot = KNEE_POS
				_fall = 0.0
				_fall_vel = 0.4
				death_stage = "topple"
		"slump":
			# Ползущий просто обмякает и ложится плашмя.
			_sink = move_toward(_sink, 0.0, delta * 2.0)
			for zone in _knees:
				_knees[zone].rotation.x = move_toward(_knees[zone].rotation.x, -0.2, delta * 3.0)
			for zone in ["leg_l", "leg_r"]:
				if parts.has(zone):
					parts[zone].rotation.x = move_toward(parts[zone].rotation.x, 0.0, delta * 3.0)
			body.rotation.x = move_toward(body.rotation.x, -1.5, delta * 4.0)
			body.rotation.z = 0.0
			body.position.y = move_toward(body.position.y, 0.14, delta * 2.0)
			_torso_rest = _torso_rest.move_toward(Vector3(0.05, 0, 0), delta * 3.0)
			if not _landed and body.rotation.x <= -1.45:
				_land()
		"topple", "lying":
			_animate_corpse_fall(delta)
	if torso:
		torso.rotation = _torso_rest + _jerk
	if parts.has("head"):
		parts["head"].rotation.x = _head_rest().x + _hjerk.x
		parts["head"].rotation.z = _head_rest().z + _hjerk.y
	_animate_flail(delta)
	if parts.has("torso"):
		corpse_center = (parts["torso"] as Node3D).global_position


func _head_rest() -> Vector3:
	if death_stage == "buckle":
		return Vector3(-0.5, 0, _head_tilt)
	return Vector3(0.1, 0, _head_tilt * 1.5)


## Тело валится вокруг ступней (или коленей, если уже на них осело): гравитация
## опрокидывает, у пола удар, отскок, и дальше лежит. Ноги разгибаются, корпус
## выпрямляется, пока летит.
const CORPSE_GROUND := 1.48

func _animate_corpse_fall(delta: float) -> void:
	var com := 0.95 if _fall_pivot == Vector3.ZERO else 0.55
	if death_stage == "topple":
		_fall_vel += 9.8 / com * sin(maxf(_fall, 0.08)) * delta
		_fall += _fall_vel * delta
		if _fall >= CORPSE_GROUND:
			_fall = CORPSE_GROUND
			if _fall_vel > 1.2:
				_fall_vel = -_fall_vel * 0.25
				_hjerk_v.x += 6.0
				_jerk_v.x += _fall_dir.y * 3.0
				if not _landed:
					_land()
			else:
				_fall_vel = 0.0
				death_stage = "lying"
				if not _landed:
					_land()
	_torso_rest = _torso_rest.move_toward(Vector3.ZERO, delta * 2.0)
	for zone in _knees:
		var target: float = -0.15 if _fall > 1.2 else _knees[zone].rotation.x
		_knees[zone].rotation.x = move_toward(_knees[zone].rotation.x, target, delta * 3.0)
		parts[zone].rotation.x = move_toward(parts[zone].rotation.x, 0.0, delta * 2.0)
	body.rotation = Vector3(_fall * _fall_dir.y, 0.0, -_fall * _fall_dir.x)
	var p := _fall_pivot
	body.position = Vector3(0, -_sink, 0) + p - body.basis * p
	body.position.y += 0.12 * clampf(_fall / CORPSE_GROUND, 0.0, 1.0)


## Тело ударилось о пол: глухой шлепок и лужа крови, которая растекается из-под него.
func _land() -> void:
	_landed = true
	Sfx.play_at(get_parent(), "splat", global_position + Vector3.UP * 0.2, -4.0, 0.45)
	var at: Vector3 = global_position
	if parts.has("torso"):
		at = (parts["torso"] as Node3D).global_position
	corpse_center = at
	var pool := Gore.floor_stain(get_parent(), at, "pool", randf_range(0.2, 0.28))
	if pool:
		var grown := pool.scale * randf_range(2.8, 3.6)
		grown.y = 1.0
		pool.create_tween().tween_property(pool, "scale", grown, randf_range(4.0, 7.0)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## Попадание в труп: тело дёргается, брызжет кровь, его немного сдвигает.
## Можно отстрелить голову или конечность, а изрешечённый труп разваливается на куски.
func hit_corpse(zone: String, damage: float, point: Vector3, dir: Vector3, force := 1.0) -> void:
	if not dead or not zone_hp.has(zone):
		return
	Gore.splash(get_parent(), point, dir, 16)
	Gore.chunks(get_parent(), point, dir, randi_range(1, 3))
	_jolt(zone, point, dir, force * 1.4)
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	_knock = (_knock + flat * force * 0.2).limit_length(4.0)
	zone_hp[zone] -= damage * float(ZONES[zone]["mult"])
	if zone_hp[zone] > 0.0:
		_add_wound(zone, point, dir)
		# Пуля в труп: глуше и мокрее, чем в живого.
		Sfx.play_at(get_parent(), ["hit_flesh", "squelch"].pick_random(), point, -9.0, randf_range(0.7, 0.95))
		return
	match zone:
		"torso":
			Gore.burst(get_parent(), point, dir, 30)
			Sfx.play_at(get_parent(), "crunch", point, -2.0, 0.9)
			_collapse(dir * 3.0 + _knock)
		_:
			var part: Node3D = parts[zone]
			Gore.detach(get_parent(), part, dir * 3.0 + Vector3.UP * 2.0)
			Gore.burst(get_parent(), part.global_position, dir, 20)
			Sfx.play_at(get_parent(), "crunch", point, -2.0)
			_remove_part(zone)

