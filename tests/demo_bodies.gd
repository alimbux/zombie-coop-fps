extends SceneTree
## Демо-ролик (не для CI): xvfb-run godot --rendering-driver opengl3 --write-movie out.avi --fixed-fps 30 --path . -s tests/demo_bodies.gd
const Zombie := preload("res://scripts/zombie.gd")
const GameConfig := preload("res://scripts/game_config.gd")

var main: Node
var p

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 7)
	GameConfig.new_game(GameConfig.Mode.WAVES, 1)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	if main.spawner:
		main.spawner.set_process(false)
	await _f(10)
	for z in get_nodes_in_group("zombies"):
		z.free()
	p = main.players[0]
	p.give_weapon("pistol", 90)
	p.give_weapon("smg", 200)
	p.hp = 100000.0
	p.yaw = 0.0
	p.pitch = -0.12
	var o: Vector3 = p.global_position
	if OS.get_environment("SIDE") == "1":
		# Вид сбоку, как в 2D-ролике: видно, как тела падают и ползут.
		var cam := Camera3D.new()
		p.camera.get_parent().add_child(cam)
		cam.global_position = o + Vector3(6.5, 1.4, -5.5)
		cam.look_at(o + Vector3(0, 0.7, -5.5), Vector3.UP)
		cam.fov = 62.0
		cam.make_current()
		var lamp := OmniLight3D.new()
		lamp.omni_range = 14.0
		lamp.light_energy = 2.2
		main.world.add_child(lamp)
		lamp.global_position = o + Vector3(3.5, 3.2, -5.5)
	var zs := []
	for off in [Vector3(-0.4, 0, -5.0), Vector3(0.6, 0, -6.8), Vector3(-0.2, 0, -8.5), Vector3(-0.5, 0, -10.5), Vector3(0.5, 0, -11.5), Vector3(0.0, 0, -13.0)]:
		var z = Zombie.new()
		main.world.add_child(z)
		z.global_position = o + off + Vector3.UP * 0.1
		z.gait = "walk"
		zs.append(z)
	await _f(20)
	var a = zs[0]
	var b = zs[1]
	var c = zs[2]
	p.switch_to("pistol")
	# A: две пули в грудь — оседает на колени и ползёт.
	await _shoot(a, "torso", Vector3(0.05, 0.45, 0))
	await _f(14)
	await _shoot(a, "torso", Vector3(-0.05, 0.4, 0))
	await _f(4)
	if not a.crawling:
		a._start_kneel()
	await _f(40)
	# B: в голову — падает целиком.
	await _shoot(b, "head", Zombie.ZONES["head"]["center"])
	await _f(50)
	# C: очередь в корпус — подгибаются колени, валится лицом вперёд.
	p.switch_to("smg")
	await _f(20)
	for i in 6:
		if c.dead:
			break
		await _shoot(c, "torso", Vector3(randf_range(-0.1, 0.1), 0.3, 0))
		await _f(5)
	await _f(70)
	# Труп B дёргается от пуль.
	p.switch_to("pistol")
	await _f(20)
	for i in 3:
		if is_instance_valid(b):
			await _shoot_corpse(b)
			await _f(14)
	# Остальные идут через трупы.
	await _f(200)
	# Ползущего A добить в голову.
	if is_instance_valid(a) and not a.dead:
		await _shoot(a, "head", Zombie.ZONES["head"]["center"])
	await _f(90)
	quit(0)


func _aim(at: Vector3) -> void:
	for i in 3:
		var d: Vector3 = (at - p.camera.global_position).normalized()
		p.yaw = atan2(-d.x, -d.z)
		p.pitch = asin(d.y)
		await physics_frame


func _shoot(z, zone: String, local: Vector3) -> void:
	if not is_instance_valid(z) or not z.parts.has(zone):
		return
	await _aim(z.parts[zone].to_global(local))
	p.fire_cooldown = 0.0
	if p.mag[p.current] <= 0:
		p.mag[p.current] = 12
	p.shoot()


func _shoot_corpse(z) -> void:
	if not z.parts.has("torso"):
		return
	await _aim(z.parts["torso"].to_global(Vector3(0, 0.3, 0)))
	p.fire_cooldown = 0.0
	p.shoot()


func _f(n: int) -> void:
	for i in n:
		await physics_frame
