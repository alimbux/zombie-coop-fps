extends SceneTree
## Демо-ролик сравнения (не для CI): слева наш блочный зомби, справа готовая модель
## с рэгдоллом. Одинаковые выстрелы по обоим: в корпус, по руке, удар ногой, в голову,
## по трупу.
## xvfb-run godot --rendering-driver opengl3 --write-movie out.avi --fixed-fps 30 --path . -s tests/demo_ragdoll.gd
## SIDE=1 — вид со стороны вместо первого лица.
const Zombie := preload("res://scripts/zombie.gd")
const RagdollZombie := preload("res://scripts/ragdoll_zombie.gd")
const GameConfig := preload("res://scripts/game_config.gd")
const PlayerScript := preload("res://scripts/player.gd")

var main: Node
var p
var o: Vector3


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 3)
	GameConfig.new_game(GameConfig.Mode.WAVES, 1)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	if main.spawner:
		main.spawner.set_process(false)
	await _f(10)
	for z in get_nodes_in_group("zombies"):
		z.free()
	for pk in get_nodes_in_group("pickups"):
		pk.free()
	p = main.players[0]
	p.give_weapon("pistol", 190)
	p.give_weapon("smg", 400)
	p.give_weapon("shotgun", 90)
	p.hp = 100000.0
	p.yaw = 0.0
	p.pitch = -0.08
	p.set_physics_process(true)
	o = p.global_position
	var lamp := OmniLight3D.new()
	lamp.omni_range = 12.0
	lamp.light_energy = 2.0
	main.world.add_child(lamp)
	lamp.global_position = o + Vector3(0, 3.0, -4.0)
	if OS.get_environment("SIDE") == "1":
		var cam := Camera3D.new()
		p.camera.get_parent().add_child(cam)
		cam.global_position = o + Vector3(4.2, 1.9, -1.0)
		cam.look_at(o + Vector3(1.4, 0.7, -6.5), Vector3.UP)
		cam.fov = 60.0
		cam.make_current()
	var a = Zombie.new()
	main.world.add_child(a)
	a.global_position = o + Vector3(0.5, 0.1, -9.0)
	a.gait = "walk"
	var b = RagdollZombie.new()
	main.world.add_child(b)
	b.global_position = o + Vector3(2.6, 0.1, -9.0)
	for z in [a, b]:
		z.set_physics_process(false)
	await _f(30)
	for z in [a, b]:
		z.set_physics_process(true)
	await _f(30)
	p.switch_to("pistol")
	await _f(10)
	# 1. Две пули в грудь каждому.
	for i in 2:
		await _shoot(a, "torso", 0.0)
		await _f(18)
		await _shoot(b, "torso", 0.0)
		await _f(24)
	await _f(20)
	# 2. Очередь по правой руке, пока не оторвётся.
	p.switch_to("smg")
	await _f(15)
	for i in 6:
		await _shoot(a, "arm_r", 0.0)
		await _f(5)
	await _f(20)
	for i in 6:
		await _shoot(b, "arm_r", 0.0)
		await _f(5)
	await _f(30)
	# 3. Удар ногой.
	for z in [a, b]:
		if is_instance_valid(z) and not z.dead:
			var dir: Vector3 = (z.global_position - p.global_position)
			dir.y = 0.0
			z.kicked(dir.normalized(), PlayerScript.KICK_SPEED, PlayerScript.KICK_DAMAGE)
			await _f(20)
	await _f(110)
	# 4. В голову из пистолета до смерти.
	p.switch_to("pistol")
	await _f(10)
	for z in [a, b]:
		for i in 6:
			if not is_instance_valid(z) or z.dead:
				break
			await _shoot(z, "head", 0.0)
			await _f(14)
		await _f(30)
	# 5. Пули по трупам.
	for i in 3:
		for z in [a, b]:
			await _shoot(z, "torso", 0.0)
			await _f(10)
	await _f(80)
	quit(0)


func _target(z, zone: String) -> Vector3:
	if z is RagdollZombie:
		var bone: String = {"torso": "Torso", "head": "Head", "arm_r": "LowerArm.R", "arm_l": "LowerArm.L", "leg_l": "UpperLeg.L", "leg_r": "UpperLeg.R"}[zone]
		if z._lost.has(bone):
			bone = "UpperArm.R" if zone == "arm_r" else bone
		var att: Node3D = z._attach[bone]
		return att.global_transform * Vector3(0, RagdollZombie.BONES[bone][0] * (0.45 if zone != "head" else 0.3), 0)
	var part = z.parts.get(zone)
	if part == null:
		part = z.parts["torso"]
	var c: Vector3 = Zombie.ZONES[zone]["center"] if Zombie.ZONES.has(zone) and Zombie.ZONES[zone].has("center") else Vector3(0, 0.3, 0)
	return part.to_global(c)


func _shoot(z, zone: String, _jit: float) -> void:
	if not is_instance_valid(z):
		return
	await _aim(_target(z, zone))
	p.fire_cooldown = 0.0
	p.mag[p.current] = 30
	p.shoot()


func _aim(at: Vector3) -> void:
	for i in 3:
		var d: Vector3 = (at - p.camera.global_position).normalized()
		p.yaw = atan2(-d.x, -d.z)
		p.pitch = asin(d.y)
		await physics_frame


func _f(n: int) -> void:
	for i in n:
		await physics_frame
