extends SceneTree
## Демо-ролик (не для CI): xvfb-run godot --rendering-driver opengl3 --write-movie out.avi --fixed-fps 30 --path . -s tests/demo_crawl.gd
## Четыре ползущих зомби наперегонки: на коленях, без ноги, без обеих ног и без ног
## с обрубками рук. VIEW=plan — снимок этажа сверху без потолка (двери у краёв стен).
const Zombie := preload("res://scripts/zombie.gd")
const GameConfig := preload("res://scripts/game_config.gd")
const LevelGenerator := preload("res://scripts/level_generator.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(5)
	if OS.get_environment("VIEW") == "plan":
		await _plan()
		return
	GameConfig.new_game(GameConfig.Mode.WAVES, 1)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	if main.spawner:
		main.spawner.set_process(false)
	await _f(10)
	for z in get_nodes_in_group("zombies"):
		z.free()
	# Ящики посреди зала убрать, чтобы ползли без помех.
	for n in main.world.get_children():
		if n is StaticBody3D and is_equal_approx(n.position.y, 0.6):
			n.free()
	var p = main.players[0]
	p.hp = 100000.0
	p.set_physics_process(false)
	var o: Vector3 = p.global_position
	var cam := Camera3D.new()
	p.camera.get_parent().add_child(cam)
	cam.global_position = o + Vector3(6.5, 2.6, -6.0)
	cam.look_at(o + Vector3(-0.5, 0.0, -8.0), Vector3.UP)
	cam.fov = 58.0
	cam.make_current()
	var lamp := OmniLight3D.new()
	lamp.omni_range = 16.0
	lamp.light_energy = 2.4
	main.world.add_child(lamp)
	lamp.global_position = o + Vector3(1.0, 3.0, -8.0)
	var zs := []
	for x in [-2.4, -0.8, 0.8, 2.4]:
		var z = Zombie.new()
		main.world.add_child(z)
		z.global_position = o + Vector3(x, 0.1, -12.0)
		z.gait = "walk"
		z.speed_jitter = 1.0
		zs.append(z)
	await _f(5)
	var back := Vector3(0, 0, 1)
	zs[0]._start_kneel()
	zs[1]._sever("leg_r", zs[1].global_position, back)
	for leg in ["leg_l", "leg_r"]:
		zs[2]._sever(leg, zs[2].global_position, back)
		zs[3]._sever(leg, zs[3].global_position, back)
	zs[3]._sever("arm_l", zs[3].global_position, back)
	zs[3]._tear_forearm("arm_r", back)
	for z in zs:
		z.speed_jitter = 1.0
	await _f(1000)
	quit(0)


func _plan() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var gen = LevelGenerator.new()
	gen.build(world, 6, 1, 777)
	for n in world.get_children():
		if n is StaticBody3D and (n.position.y > LevelGenerator.DOOR_HEIGHT or n.position.y < 0.0):
			n.queue_free()
		elif n is Node3D and n.is_in_group("zombies"):
			n.queue_free()
		elif n is WorldEnvironment:
			n.environment.fog_enabled = false
			n.environment.ambient_light_energy = 0.6
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.rotation = Vector3(-1.2, 0.4, 0)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in gen.cells:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.y))
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var mid := (lo + hi) / 2.0 * LevelGenerator.CELL
	cam.position = Vector3(mid.x, 40, mid.y)
	cam.rotation = Vector3(-PI / 2, 0, 0)
	cam.size = (maxf((hi.x - lo.x + 1.2) * 9.0 / 16.0, hi.y - lo.y + 1.2)) * LevelGenerator.CELL
	cam.make_current()
	await _f(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("SHOT"))
	quit(0)


func _f(n: int) -> void:
	for i in n:
		await physics_frame
