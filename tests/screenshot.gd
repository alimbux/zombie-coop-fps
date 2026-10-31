extends SceneTree
## Снимок экрана прототипа (нужен экран или Xvfb, рендер opengl3):
##   SHOT=/tmp/shot.png godot --rendering-driver opengl3 --path . -s tests/screenshot.gd
const Zombie := preload("res://scripts/zombie.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.spawner.set_process(false)
	for i in 10:
		await process_frame
	var world: Node3D = main.world
	var p0 = main.players[0]
	var p1 = main.players[1]
	p1.yaw = 0.35
	var zs = []
	for off in [Vector3(0.0, 0, -3.5), Vector3(1.4, 0, -5.0), Vector3(-1.6, 0, -6.0), Vector3(-2.5, 0, -4.5), Vector3(-0.5,0,-7.5)]:
		var z = Zombie.new()
		world.add_child(z)
		z.global_position = p0.global_position + off
		z.set_physics_process(false)
		z.look_at(p0.global_position, Vector3.UP)
		zs.append(z)
	for i in 5:
		await physics_frame
	zs[1].take_hit("arm_r", 60.0, zs[1].global_position + Vector3(0.4,1.36,0), Vector3(0.3,0,-1))
	zs[2].take_hit("leg_l", 60.0, zs[2].global_position + Vector3(0,0.3,0), Vector3(0,0,-1))
	p0.pitch = 0.0
	for i in 3:
		await physics_frame
	p0.shoot()
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("SHOT") if OS.has_environment("SHOT") else "user://shot.png")
	quit(0)
