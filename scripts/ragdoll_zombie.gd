extends CharacterBody3D
## Эксперимент для сравнения: готовая модель человека (Quaternius, CC0) со скелетом,
## анимациями и рэгдоллом на PhysicalBone3D. Модели две, см. PROFILES.
## В игру не входит, живёт только в тестовой сцене scenes/ragdoll_test.tscn.
##
## Что тут сделано поверх готового:
## - кости рэгдолла (капсулы и суставы) собраны кодом, как это делает кнопка
##   редактора «Create Physical Skeleton», только с размерами под модель;
## - попадание включает рэгдолл на части тела на полсекунды (частичный рэгдолл)
##   и плавно возвращает анимацию, так тело дёргается от пули по физике;
## - смерть и удар ногой роняют всё тело рэгдоллом, после удара зомби встаёт;
## - раны — наклейки на кости, рука и нога отрываются сжатием кости в ноль.
## Отвечает тем же методам, что и наш зомби (take_hit, hit_corpse, kicked, push,
## alert), поэтому по нему работают выстрелы и удар ногой игрока.

const Gore := preload("res://scripts/gore.gd")
const Sfx := preload("res://scripts/sfx.gd")

const SPEED := 1.25
const GRAVITY := 18.0
const ATTACK_RANGE := 1.3
const ATTACK_DAMAGE := 12.0
const REACT_TIME := 0.6
const KNOCKDOWN_TIME := 2.2
const BULLET_IMPULSE := 9.0
const CRY_DB := -8.0

## Те же зоны и прочность, что у наших зомби.
const ZONES := {
	"head": {"hp": 110.0, "mult": 1.5},
	"torso": {"hp": 260.0, "mult": 1.0},
	"arm_l": {"hp": 70.0, "mult": 1.0},
	"arm_r": {"hp": 70.0, "mult": 1.0},
	"leg_l": {"hp": 90.0, "mult": 1.0},
	"leg_r": {"hp": 90.0, "mult": 1.0},
}

## Две модели на выбор (kind):
## - "chibi": Quaternius «Ultimate Animated Character Pack», мультяшный зомби;
## - "human": Quaternius «Universal Base Characters» с анимациями «Universal
##   Animation Library» — обычные человеческие пропорции, анимации общие для всех
##   персонажей набора.
## Кости рэгдолла (bones): длина по оси кости, радиус капсулы, зона, масса.
## Размеры в единицах модели (до масштаба scale). У обеих моделей ось кости — +Y.
## react — какие кости обмякают от попадания в зону, пока зомби на ногах.
const PROFILES := {
	"chibi": {
		"model": "res://assets/ragdoll_test/Zombie_Male.gltf",
		"anims": "",
		"scale": 0.74,
		"walk": "Walk", "walk_speed": 0.8, "punch": "Punch", "rise": "StandUp", "loops": ["Walk", "Idle", "Run"],
		"feet_ik": true, "hunch": false,
		"root": "Body_2", "torso": "Torso", "head": "Head",
		"lower_arm": "LowerArm.%s", "upper_arm": "UpperArm.%s", "lower_leg": "LowerLeg.%s", "side_upper": true,
		"bones": {
			"Body_2": [0.3, 0.2, "torso", 12.0],
			"Abdomen": [0.3, 0.19, "torso", 8.0],
			"Torso": [0.5, 0.23, "torso", 10.0],
			"Head": [0.42, 0.21, "head", 4.0],
			"UpperArm.L": [0.52, 0.08, "arm_l", 2.0],
			"LowerArm.L": [0.5, 0.075, "arm_l", 1.5],
			"UpperArm.R": [0.52, 0.08, "arm_r", 2.0],
			"LowerArm.R": [0.5, 0.075, "arm_r", 1.5],
			"UpperLeg.L": [0.45, 0.12, "leg_l", 6.0],
			"LowerLeg.L": [0.5, 0.1, "leg_l", 4.0],
			"UpperLeg.R": [0.45, 0.12, "leg_r", 6.0],
			"LowerLeg.R": [0.5, 0.1, "leg_r", 4.0],
		},
		"react": {
			"head": ["Head", "Torso"],
			"torso": ["Abdomen", "Torso", "Head", "UpperArm.L", "LowerArm.L", "UpperArm.R", "LowerArm.R"],
			"arm_l": ["UpperArm.L", "LowerArm.L"],
			"arm_r": ["UpperArm.R", "LowerArm.R"],
			"leg": ["Abdomen", "Torso", "Head", "UpperArm.L", "LowerArm.L", "UpperArm.R", "LowerArm.R"],
		},
	},
	"human": {
		"model": "res://assets/ragdoll_test/human/Superhero_Male_FullBody.gltf",
		"anims": "res://assets/ragdoll_test/human/UAL1_Standard.glb",
		"scale": 0.97,
		"walk": "Walk", "walk_speed": 0.55, "punch": "Punch_Jab", "rise": "Idle", "loops": ["Walk", "Idle"],
		"feet_ik": false, "hunch": true,
		"root": "pelvis", "torso": "spine_03", "head": "Head",
		"lower_arm": "lowerarm_%s", "upper_arm": "upperarm_%s", "lower_leg": "calf_%s", "side_upper": false,
		"bones": {
			"pelvis": [0.18, 0.15, "torso", 12.0],
			"spine_01": [0.24, 0.14, "torso", 8.0],
			"spine_03": [0.24, 0.16, "torso", 10.0],
			"Head": [0.26, 0.11, "head", 4.0],
			"upperarm_l": [0.25, 0.055, "arm_l", 2.0],
			"lowerarm_l": [0.32, 0.045, "arm_l", 1.5],
			"upperarm_r": [0.25, 0.055, "arm_r", 2.0],
			"lowerarm_r": [0.32, 0.045, "arm_r", 1.5],
			"thigh_l": [0.43, 0.08, "leg_l", 6.0],
			"calf_l": [0.46, 0.06, "leg_l", 4.0],
			"thigh_r": [0.43, 0.08, "leg_r", 6.0],
			"calf_r": [0.46, 0.06, "leg_r", 4.0],
		},
		"react": {
			"head": ["Head", "spine_03"],
			"torso": ["spine_01", "spine_03", "Head", "upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r"],
			"arm_l": ["upperarm_l", "lowerarm_l"],
			"arm_r": ["upperarm_r", "lowerarm_r"],
			"leg": ["spine_01", "spine_03", "Head", "upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r"],
		},
	},
}

## Какую модель брать. Задаётся до добавления в сцену.
var kind := "human"

var dead := false
var aware := true
var zone_hp := {}
var voice := 1.0
var _bumped: Array = []

var _model: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _sim: PhysicalBoneSimulator3D
var _hider
var _bodies := {}
var _attach := {}
var _react := 0.0
var _down := 0.0
var _rise := 0.0
var _knock := Vector3.ZERO
var _attack_cd := 0.0
var _groan := 0.0
var _feet_on_legs := false
var _lost := {}
var _p: Dictionary
var BONES: Dictionary
var SCALE := 1.0


func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 2
	collision_mask = 1
	for zone in ZONES:
		zone_hp[zone] = ZONES[zone]["hp"]
	voice = randf_range(0.85, 1.1)
	_groan = randf_range(1.0, 4.0)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)

	_p = PROFILES[kind]
	BONES = _p["bones"]
	SCALE = _p["scale"]
	_model = load(_p["model"]).instantiate()
	_model.scale = Vector3.ONE * SCALE
	# Модель смотрит в +Z, а тело идёт в -Z.
	_model.rotation.y = PI
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	if _p["anims"] == "":
		_anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
	else:
		# Анимации лежат в отдельном файле набора, скелет у всех персонажей общий.
		_anim = AnimationPlayer.new()
		_model.add_child(_anim)
		_anim.add_animation_library("", _anim_library(_p["anims"]))
	_recolor()
	for loop in _p["loops"]:
		_anim.get_animation(loop).loop_mode = Animation.LOOP_LINEAR
	_anim.play(_p["walk"], 0.2, _p["walk_speed"])
	_anim.seek(randf() * 1.2, true)

	# Тела собираются до того, как симулятор попадёт в скелет: так их привязка
	# к костям проходит так же, как у сцены, сохранённой в редакторе.
	if _p["hunch"]:
		_skeleton.add_child(load("res://scripts/ragdoll_zombie_pose.gd").new())
	_sim = PhysicalBoneSimulator3D.new()
	for bone in BONES:
		_add_body(bone)
	_skeleton.add_child(_sim)
	# Без рэгдолла симулятор всё равно переписывает позу костей, поэтому держим его
	# влияние на нуле, пока тело не обмякнет.
	_sim.influence = 0.0
	_hider = load("res://scripts/ragdoll_bone_hider.gd").new()
	_skeleton.add_child(_hider)


## Модель цветная, а у нас мир чёрно-белый: кожа и одежда в оттенки серого,
## кишки и мозг — тёмно-красные, их фильтр оставит красными.
func _recolor() -> void:
	if kind == "human":
		_recolor_human()
		return
	var mesh_node: MeshInstance3D = _model.find_children("*", "MeshInstance3D", true, false)[0]
	var tones := {"Skin": 0.42, "Clothes": 0.22, "Pants": 0.32, "DarkClothes": 0.12, "Bones": 0.75, "Face": 0.05}
	for i in mesh_node.mesh.get_surface_count():
		var src: Material = mesh_node.mesh.surface_get_material(i)
		var m := StandardMaterial3D.new()
		m.roughness = 0.9
		var key := src.resource_name
		if key == "Guts" or key == "Brain":
			m.albedo_color = Color(0.5, 0.02, 0.04) if key == "Guts" else Color(0.35, 0.05, 0.06)
			m.roughness = 0.3
		else:
			var v: float = tones.get(key, 0.4)
			m.albedo_color = Color(v, v, v)
		mesh_node.set_surface_override_material(i, m)


static var _libraries := {}


static func _anim_library(path: String) -> AnimationLibrary:
	if not _libraries.has(path):
		var src: Node = load(path).instantiate()
		var player: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
		_libraries[path] = player.get_animation_library("")
		src.free()
	return _libraries[path]


## Текстуры у этой модели телесные, и фильтр окрасил бы кожу в розовый, как кровь.
## Умножаем на серо-зелёный: кожа становится бледной трупной, без красного.
func _recolor_human() -> void:
	for mesh_node in _model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh_node.mesh.get_surface_count():
			var src: Material = mesh_node.mesh.surface_get_material(i)
			if not (src is StandardMaterial3D):
				continue
			var m: StandardMaterial3D = src.duplicate()
			m.albedo_color = Color(0.6, 0.95, 0.95)
			mesh_node.set_surface_override_material(i, m)


## Капсула рэгдолла вдоль кости (у этой модели ось кости — +Y) и сустав у её начала.
## Плюс хитбокс той же формы для пуль игрока.
func _add_body(bone: String) -> void:
	var spec: Array = BONES[bone]
	var length: float = spec[0]
	var radius: float = spec[1]
	var pb := PhysicalBone3D.new()
	pb.name = "PB_" + bone
	pb.bone_name = bone
	pb.mass = spec[3]
	pb.body_offset = Transform3D(Basis(), Vector3(0, -length * 0.5, 0))
	pb.joint_offset = Transform3D(Basis(), Vector3(0, length * 0.5, 0))
	pb.collision_layer = 0
	pb.collision_mask = 1
	pb.linear_damp = 0.4
	pb.angular_damp = 2.0
	pb.friction = 0.9
	# Суставы — шарниры без ограничений, как делает кнопка редактора. С конусами и
	# петлями (ограничение углов) рэгдолл этой модели взрывался: оси суставов нужно
	# подбирать под каждую кость вручную.
	pb.joint_type = PhysicalBone3D.JOINT_TYPE_PIN
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius * SCALE
	cap.height = maxf(length * SCALE, radius * SCALE * 2.0 + 0.01)
	cs.shape = cap
	pb.add_child(cs)
	_sim.add_child(pb)
	_bodies[bone] = pb

	var att := BoneAttachment3D.new()
	att.bone_name = bone
	_skeleton.add_child(att)
	_attach[bone] = att
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("zone", spec[2])
	area.set_meta("zombie", self)
	var hs := CollisionShape3D.new()
	var hcap := CapsuleShape3D.new()
	hcap.radius = radius * 1.1
	hcap.height = maxf(length, radius * 2.2 + 0.01)
	hs.shape = hcap
	hs.position.y = length * 0.5
	area.add_child(hs)
	att.add_child(area)


func _process(_delta: float) -> void:
	# В Godot 4.3 модификаторы скелета (и рэгдолл) срабатывают, только когда поза
	# изменилась. Анимация на время рэгдолла стоит, поэтому трогаем позу сами.
	if _sim.is_simulating_physics():
		_skeleton.set_bone_pose_position(0, _skeleton.get_bone_pose_position(0))


func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	if _react > 0.0:
		_react -= delta
		_sim.influence = clampf(_react / REACT_TIME, 0.0, 1.0)
		if _react <= 0.0 and not dead and _down <= 0.0:
			_sim.physical_bones_stop_simulation()
			_sim.influence = 0.0
	if dead:
		return
	if _down > 0.0:
		_down -= delta
		if _down <= 0.0:
			_get_up()
		return
	if _rise > 0.0:
		_rise -= delta
		_sim.influence = clampf(_rise / 0.8, 0.0, 1.0)
		if _rise <= 0.0:
			_sim.physical_bones_stop_simulation()
			_sim.influence = 0.0
			_anim.play(_p["walk"], 0.4, _p["walk_speed"])
		return

	var target = _nearest_player()
	var move := Vector3.ZERO
	if target != null and aware:
		var to: Vector3 = target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 0.05:
			rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(delta * 4.0, 1.0))
		if dist > ATTACK_RANGE:
			move = -global_transform.basis.z * SPEED
			if _anim.current_animation != _p["walk"]:
				_anim.play(_p["walk"], 0.3, _p["walk_speed"])
		elif _attack_cd <= 0.0:
			_attack_cd = 1.2
			_anim.play(_p["punch"], 0.15)
			_anim.queue(_p["walk"])
			if target.has_method("take_damage"):
				target.take_damage(ATTACK_DAMAGE)
			Sfx.groan(self, "growl", -2.0, voice)
	_groan -= delta
	if _groan <= 0.0:
		_groan = randf_range(3.0, 7.0)
		Sfx.groan(self, "groan", -6.0, voice)
	_knock = _knock.move_toward(Vector3.ZERO, delta * 9.0)
	velocity.x = move.x + _knock.x
	velocity.z = move.z + _knock.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()


func _nearest_player():
	var best = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.get("downed"):
			continue
		var d: float = p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func alert() -> void:
	aware = true


func push(dir: Vector3, force: float) -> void:
	if dead or _down > 0.0:
		return
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	_knock = (_knock + flat * force * 1.2).limit_length(8.0)


func _say(sound: String, volume_db := -2.0) -> void:
	Sfx.groan(self, sound, volume_db, voice)


## Попадание пули. Возвращает true, если зомби убит.
func take_hit(zone: String, damage: float, point: Vector3, dir: Vector3, loud := true, force := 1.0) -> bool:
	if dead or not zone_hp.has(zone):
		return false
	alert()
	Gore.splash(get_parent(), point, dir, 24)
	Gore.chunks(get_parent(), point, dir, randi_range(2, 5))
	zone_hp[zone] -= damage * float(ZONES[zone]["mult"])
	var bone := _bone_at(zone, point)
	_wound(bone, point, dir)
	if loud:
		_hit_sound(zone, point)
		if randf() < 0.8:
			_say(["pain", "yelp", "snarl"].pick_random(), -2.0 + CRY_DB)
	if zone_hp["head"] <= 0.0 or zone_hp["torso"] <= 0.0:
		if zone == "head":
			_lose(_p["head"], point, dir)
		_die(bone, point, dir * force)
		return true
	if zone.begins_with("arm") and zone_hp[zone] <= 0.0:
		var lower := _side_bone("lower_arm", zone)
		_lose(_side_bone("upper_arm", zone) if _lost.has(lower) else lower, point, dir)
		zone_hp[zone] = ZONES[zone]["hp"] * 0.6
	if zone.begins_with("leg") and zone_hp[zone] <= 0.0:
		# Анимаций ползания в этом наборе нет: без ноги тело просто падает рэгдоллом.
		_lose(_side_bone("lower_leg", zone), point, dir)
		_die(bone, point, dir * force)
		return true
	push(dir, force * 0.8)
	_hit_react(zone, bone, point, dir * force)
	return false


## Попадание в лежащее тело: оно дёргается по физике.
func hit_corpse(zone: String, damage: float, point: Vector3, dir: Vector3, force := 1.0) -> void:
	if not dead:
		return
	Gore.splash(get_parent(), point, dir, 16)
	var bone := _bone_at(zone, point)
	_wound(bone, point, dir)
	Sfx.play_at(get_parent(), "squelch", point, -8.0, randf_range(0.8, 1.0))
	var pb: PhysicalBone3D = _bodies.get(bone)
	if pb:
		pb.apply_impulse(dir * BULLET_IMPULSE * 0.6 * force, point - pb.global_position)


## Удар ногой игрока: всё тело улетает рэгдоллом, через пару секунд зомби встаёт.
func kicked(dir: Vector3, speed: float, damage: float) -> void:
	if dead:
		return
	zone_hp["torso"] -= damage
	if zone_hp["torso"] <= 0.0:
		_die(_p["torso"], global_position + Vector3.UP, dir * speed * 0.5)
		return
	_ragdoll_all()
	for bone in _bodies:
		var pb: PhysicalBone3D = _bodies[bone]
		pb.apply_central_impulse((dir * speed * 0.3 + Vector3.UP * 1.2) * pb.mass)
	_down = KNOCKDOWN_TIME
	_say("pain", -2.0 + CRY_DB)


func _hit_react(zone: String, bone: String, point: Vector3, dir: Vector3) -> void:
	if _down > 0.0 or _rise > 0.0:
		var pb0: PhysicalBone3D = _bodies.get(bone)
		if pb0:
			pb0.apply_impulse(dir * BULLET_IMPULSE, point - pb0.global_position)
		return
	_sim.physical_bones_stop_simulation()
	var names: Array[StringName] = []
	for b in _p["react"]["leg" if zone.begins_with("leg") else zone]:
		if not _lost.has(b):
			names.append(StringName(b))
	_sim.physical_bones_start_simulation(names)
	_sim.influence = 1.0
	_react = REACT_TIME
	var pb: PhysicalBone3D = _bodies.get(bone)
	if pb and names.has(StringName(bone)):
		pb.apply_impulse(dir * BULLET_IMPULSE, point - pb.global_position)
	else:
		# Пуля в ногу сгибает корпус вперёд.
		_bodies[_p["torso"]].apply_central_impulse(-dir * BULLET_IMPULSE * 0.6 + Vector3.DOWN * 4.0)


func _die(bone: String, point: Vector3, impulse: Vector3) -> void:
	dead = true
	remove_from_group("zombies")
	add_to_group("corpses")
	_say("death", -1.0 + CRY_DB)
	Gore.burst(get_parent(), point, impulse.normalized(), 40)
	_ragdoll_all()
	var pb: PhysicalBone3D = _bodies.get(bone)
	if pb:
		pb.apply_impulse(impulse * BULLET_IMPULSE * 0.7, point - pb.global_position)
	collision_layer = 0


func _ragdoll_all() -> void:
	_react = 0.0
	_anim.pause()
	_feet_follow_legs(true)
	_sim.physical_bones_stop_simulation()
	var names: Array[StringName] = []
	for b in _bodies:
		if not _lost.has(b):
			names.append(StringName(b))
	_sim.physical_bones_start_simulation(names)
	_sim.influence = 1.0


## После удара: тело переносится к месту падения, и рэгдолл за 0,8 с перетекает
## в анимацию подъёма. Своей анимации «встать с пола» в наборе нет, берём StandUp
## (подъём со стула), поэтому переход виден.
func _get_up() -> void:
	var hips: Vector3 = _bodies[_p["root"]].global_position
	var head: Vector3 = _bodies[_p["torso"]].global_position
	var face := Vector3(hips.x - head.x, 0.0, hips.z - head.z)
	global_position = Vector3(hips.x, global_position.y, hips.z)
	if face.length() > 0.1:
		rotation.y = atan2(-face.x, -face.z)
	_feet_follow_legs(false)
	_anim.play(_p["rise"], 0.0, 1.0)
	_anim.queue(_p["walk"])
	_rise = 0.8


## У этой модели ступни прикреплены к корню скелета (IK-риг), а не к голени, и в
## рэгдолле оставались бы на месте. На время рэгдолла переносим их на голени.
func _feet_follow_legs(on: bool) -> void:
	if _feet_on_legs == on or not _p["feet_ik"]:
		return
	_feet_on_legs = on
	for side in ["L", "R"]:
		var foot := _skeleton.find_bone("Foot." + side)
		var parent := _skeleton.find_bone("LowerLeg." + side if on else "Bone")
		var global_rest := _skeleton.get_bone_global_rest(foot)
		var global_pose := _skeleton.get_bone_global_pose(foot)
		_skeleton.set_bone_parent(foot, parent)
		var local_rest := _skeleton.get_bone_global_rest(parent).affine_inverse() * global_rest
		_skeleton.set_bone_rest(foot, local_rest)
		var local_pose := _skeleton.get_bone_global_pose(parent).affine_inverse() * global_pose
		_skeleton.set_bone_pose_position(foot, local_pose.origin)
		_skeleton.set_bone_pose_rotation(foot, local_pose.basis.get_rotation_quaternion())
		_skeleton.set_bone_pose_scale(foot, local_pose.basis.get_scale())
	# Смена родителя кости перестраивает список костей у симулятора, и он теряет
	# привязку тел к костям. Привязываем заново.
	for bone in _bodies:
		var pb: PhysicalBone3D = _bodies[bone]
		pb.bone_name = ""
		pb.bone_name = bone


## Ближайшая к точке попадания кость своей зоны.
func _bone_at(zone: String, point: Vector3) -> String:
	var best := ""
	var best_d := INF
	for bone in BONES:
		if BONES[bone][2] != zone or _lost.has(bone):
			continue
		var att: Node3D = _attach[bone]
		var mid := att.global_transform * Vector3(0, BONES[bone][0] * 0.5, 0)
		var d := mid.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = bone
	return best if best != "" else _p["torso"]


## Рана — наклейка на кость: чёрная дыра и кровь вокруг, ложатся на поверхность
## капсулы хитбокса. С гладкой кожей модели она совпадает только примерно.
func _wound(bone: String, point: Vector3, dir: Vector3) -> void:
	var att: Node3D = _attach.get(bone)
	if att == null:
		return
	var local := att.global_transform.affine_inverse() * point
	var axis_y := clampf(local.y, 0.0, float(BONES[bone][0]))
	var out := Vector3(local.x, 0.0, local.z)
	if out.length() < 0.001:
		out = att.global_transform.basis.inverse() * -dir
		out.y = 0.0
	out = out.normalized()
	var radius: float = BONES[bone][1]
	var holder := Node3D.new()
	att.add_child(holder)
	holder.position = Vector3(0, axis_y, 0) + out * radius * 0.92
	holder.basis = Gore.basis_from_up(out)
	var splat := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = minf(randf_range(0.07, 0.11), float(BONES[bone][1]) * 0.6)
	disc.bottom_radius = disc.top_radius
	disc.height = 0.01
	splat.mesh = disc
	splat.material_override = Gore.blood_material()
	holder.add_child(splat)
	var hole := MeshInstance3D.new()
	var hd := CylinderMesh.new()
	hd.top_radius = minf(randf_range(0.03, 0.045), float(BONES[bone][1]) * 0.3)
	hd.bottom_radius = hd.top_radius
	hd.height = 0.02
	hole.mesh = hd
	hole.material_override = Gore.hole_material()
	holder.add_child(hole)
	Gore.bleed(holder, Vector3.ZERO, Vector3.UP, 2.0, 0.6)


## Потеря части тела: кость сжимается в ноль вместе с дочерними (кисть, ступня,
## голова), на обрубке красный срез. Отлетающего куска нет: у сплошного меша
## его пришлось бы вырезать заранее в Blender.
func _lose(bone: String, point: Vector3, dir: Vector3) -> void:
	if _lost.has(bone):
		return
	_lost[bone] = true
	_hider.hidden[bone] = true
	if _bodies.has(bone):
		_bodies[bone].collision_mask = 0
	Gore.burst(get_parent(), point, dir, 30)
	Gore.chunks(get_parent(), point, dir, 10)
	Sfx.play_at(get_parent(), "tear", point, -4.0, randf_range(0.85, 1.0))
	var parent_bone := _skeleton.get_bone_name(_skeleton.get_bone_parent(_skeleton.find_bone(bone)))
	var att: Node3D = _attach.get(parent_bone)
	if att == null:
		att = BoneAttachment3D.new()
		att.bone_name = parent_bone
		_skeleton.add_child(att)
		_attach[parent_bone] = att
	var stump := MeshInstance3D.new()
	var s := SphereMesh.new()
	var r: float = BONES[bone][1] * (0.9 if bone != _p["head"] else 0.6)
	s.radius = r
	s.height = r * 1.2
	stump.mesh = s
	stump.material_override = Gore.meat_material()
	att.add_child(stump)
	stump.global_position = _attach[bone].global_position
	Gore.bleed(stump, Vector3.ZERO, Vector3.UP, 4.0, 1.0)


func _side_bone(key: String, zone: String) -> String:
	var side := zone.right(1)
	return _p[key] % (side.to_upper() if _p["side_upper"] else side)


func _hit_sound(zone: String, point: Vector3) -> void:
	var w := get_parent()
	var pitch := randf_range(0.82, 1.18)
	match zone:
		"head":
			Sfx.play_at(w, "hit_skull", point, -4.0, pitch)
		"torso":
			Sfx.play_at(w, "hit_flesh", point, -5.0, pitch * 0.92)
		_:
			Sfx.play_at(w, "hit_bone" if randf() < 0.4 else "hit_flesh", point, -6.0, pitch * 1.08)
