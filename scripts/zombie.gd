extends CharacterBody3D
## Зомби из простых блоков. Шесть зон попадания, у каждой свой запас прочности
## и своя смерть: голова — мгновенно, торс — падение, рука — отрыв, нога — ползёт.

signal died(cause: String)

const Gore := preload("res://scripts/gore.gd")
const Sfx := preload("res://scripts/sfx.gd")

const WALK_SPEED := 1.6
const CRAWL_SPEED := 0.6
const ATTACK_RANGE := 1.3
const ATTACK_DAMAGE := 12.0
const ATTACK_INTERVAL := 1.0
const GRAVITY := 18.0
const CRAWL_TILT := -1.4

const ZONES := {
	"head": {"size": Vector3(0.36, 0.36, 0.36), "pos": Vector3(0.0, 1.66, 0.0), "hp": 30.0, "mult": 3.0},
	"torso": {"size": Vector3(0.62, 0.78, 0.34), "pos": Vector3(0.0, 1.07, 0.0), "hp": 110.0, "mult": 1.0},
	"arm_l": {"size": Vector3(0.17, 0.17, 0.72), "pos": Vector3(-0.42, 1.36, -0.3), "hp": 35.0, "mult": 0.7},
	"arm_r": {"size": Vector3(0.17, 0.17, 0.72), "pos": Vector3(0.42, 1.36, -0.3), "hp": 35.0, "mult": 0.7},
	"leg_l": {"size": Vector3(0.22, 0.68, 0.22), "pos": Vector3(-0.16, 0.34, 0.0), "hp": 40.0, "mult": 0.7},
	"leg_r": {"size": Vector3(0.22, 0.68, 0.22), "pos": Vector3(0.16, 0.34, 0.0), "hp": 40.0, "mult": 0.7},
}

## Где остаётся красный обрубок, когда зона оторвана.
const STUMPS := {
	"head": Vector3(0.0, 1.48, 0.0),
	"arm_l": Vector3(-0.36, 1.36, 0.0),
	"arm_r": Vector3(0.36, 1.36, 0.0),
	"leg_l": Vector3(-0.16, 0.68, 0.0),
	"leg_r": Vector3(0.16, 0.68, 0.0),
}

var zone_hp := {}
var parts := {}
var body: Node3D
var dead := false
var crawling := false
var attack_cooldown := 0.0
var speed_jitter := 1.0
var _groan_timer := 0.0
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

	body = Node3D.new()
	add_child(body)
	speed_jitter = randf_range(0.8, 1.3)
	_groan_timer = randf_range(0.5, 4.0)
	var shade := randf_range(0.72, 0.92)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(shade, shade, shade)
	mat.roughness = 1.0
	for zone in ZONES:
		_build_part(zone, mat)
	_add_eyes(parts["head"])


func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_cooldown -= delta
	_groan_timer -= delta
	if _groan_timer <= 0.0:
		_groan_timer = randf_range(4.0, 9.0)
		Sfx.groan(self)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var target = _nearest_player()
	velocity.x = 0.0
	velocity.z = 0.0
	if target != null:
		var to: Vector3 = target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 0.05:
			look_at(global_position + to, Vector3.UP)
		if dist > ATTACK_RANGE:
			var speed := (CRAWL_SPEED if crawling else WALK_SPEED) * speed_jitter
			velocity.x = to.x / dist * speed
			velocity.z = to.z / dist * speed
		elif attack_cooldown <= 0.0:
			attack_cooldown = ATTACK_INTERVAL
			Sfx.groan(self, "growl", 0.0)
			target.take_damage(_attack_damage())
	move_and_slide()
	if not crawling:
		body.rotation.z = sin(Time.get_ticks_msec() * 0.006 * speed_jitter) * 0.08


## Попадание пули. Возвращает true, если зомби умер.
func take_hit(zone: String, damage: float, point: Vector3, dir: Vector3) -> bool:
	if dead or not zone_hp.has(zone):
		return false
	var def: Dictionary = ZONES[zone]
	zone_hp[zone] -= damage * float(def["mult"])
	Gore.splash(get_parent(), point, dir, 10)
	if zone_hp[zone] > 0.0:
		Sfx.play_at(get_parent(), "splat", point, -8.0)
		Sfx.groan(self, "pain", -2.0)
		if not crawling:
			global_position += Vector3(dir.x, 0.0, dir.z).normalized() * 0.08
		return false
	match zone:
		"head":
			_die_headshot(point, dir)
		"torso":
			_die_body(point, dir)
		_:
			_sever(zone, point, dir)
	return dead


func _sever(zone: String, point: Vector3, dir: Vector3) -> void:
	var part: MeshInstance3D = parts[zone]
	Gore.detach(get_parent(), part, dir * 3.0 + Vector3.UP * 2.0)
	Gore.burst(get_parent(), part.global_position, dir, 25)
	Sfx.play_at(get_parent(), "crunch", point, 0.0)
	Sfx.groan(self, "pain", 0.0)
	_remove_part(zone)
	if zone.begins_with("leg") and not crawling:
		_start_crawl()
	if not (parts.has("arm_l") or parts.has("arm_r") or parts.has("leg_l") or parts.has("leg_r")):
		_die_body(point, dir)


func _die_headshot(point: Vector3, dir: Vector3) -> void:
	dead = true
	var head: MeshInstance3D = parts["head"]
	Gore.detach(get_parent(), head, dir * 6.0 + Vector3.UP * 4.0)
	_remove_part("head")
	Gore.burst(get_parent(), body.to_global(STUMPS["head"]), Vector3.UP, 45)
	Sfx.play_at(get_parent(), "crunch", point, 3.0, 0.8)
	died.emit("head")
	Gore.hit_stop(get_tree(), 0.06)
	_collapse(dir * 1.5)


func _die_body(point: Vector3, dir: Vector3) -> void:
	dead = true
	Gore.burst(get_parent(), point, dir, 35)
	Sfx.play_at(get_parent(), "crunch", point, 0.0, 0.9)
	died.emit("torso")
	Gore.hit_stop(get_tree(), 0.04)
	_collapse(dir * 4.0)


## Тело разваливается на отдельные физические блоки.
func _collapse(impulse: Vector3) -> void:
	for child in body.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			Gore.detach(get_parent(), child, impulse + Vector3(randf_range(-1, 1), randf_range(0, 1.5), randf_range(-1, 1)))
	queue_free()


func _start_crawl() -> void:
	crawling = true
	body.rotation.z = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(body, "rotation:x", CRAWL_TILT, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(body, "position:y", 0.15, 0.35)
	_capsule.height = 0.8
	_capsule_node.position.y = 0.4


func _remove_part(zone: String) -> void:
	var part: MeshInstance3D = parts[zone]
	parts.erase(zone)
	zone_hp.erase(zone)
	body.remove_child(part)
	part.queue_free()
	if STUMPS.has(zone):
		var stump := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.2
		box.material = Gore.blood_material()
		stump.mesh = box
		stump.position = STUMPS[zone]
		body.add_child(stump)


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


func _build_part(zone: String, mat: StandardMaterial3D) -> void:
	var def: Dictionary = ZONES[zone]
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = def["size"]
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = def["pos"]
	body.add_child(mesh_inst)
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("zone", zone)
	area.set_meta("zombie", self)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = def["size"]
	col.shape = shape
	area.add_child(col)
	mesh_inst.add_child(area)
	parts[zone] = mesh_inst
	zone_hp[zone] = def["hp"]


func _add_eyes(head: MeshInstance3D) -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color.BLACK
	for x in [-0.08, 0.08]:
		var eye := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.035, 0.02)
		box.material = dark
		eye.mesh = box
		eye.position = Vector3(x, 0.03, -0.185)
		head.add_child(eye)
