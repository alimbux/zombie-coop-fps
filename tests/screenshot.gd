extends SceneTree
## Снимок экрана (нужен экран или Xvfb, рендер opengl3):
##   SHOT=/tmp/shot.png VIEW=escape PLAYERS=4 godot --rendering-driver opengl3 --path . -s tests/screenshot.gd
## VIEW: menu, waves или escape.
const Zombie := preload("res://scripts/zombie.gd")
const GameConfig := preload("res://scripts/game_config.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var view := OS.get_environment("VIEW") if OS.has_environment("VIEW") else "waves"
	var count := int(OS.get_environment("PLAYERS")) if OS.has_environment("PLAYERS") else 2
	if view == "menu":
		root.add_child(load("res://scenes/menu.tscn").instantiate())
		for i in 10:
			await process_frame
	else:
		GameConfig.new_game(GameConfig.Mode.ESCAPE if view == "escape" else GameConfig.Mode.WAVES, count)
		var main: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		if main.spawner:
			main.spawner.set_process(false)
		for i in 10:
			await process_frame
		var guns := ["pistol", "smg", "shotgun", "knife"]
		for i in main.players.size():
			var p = main.players[i]
			if guns[i] != "knife":
				p.give_weapon(guns[i], 40)
			p.yaw = i * PI / 2.0
		if view == "waves":
			_stage_waves(main)
		for i in 20:
			await physics_frame
		main.players[0].shoot()
		for i in 8:
			await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("SHOT") if OS.has_environment("SHOT") else "user://shot.png")
	quit(0)


func _stage_waves(main: Node) -> void:
	var p0 = main.players[0]
	p0.yaw = 0.0
	for off in [Vector3(0.0, 0, -3.5), Vector3(1.4, 0, -5.0), Vector3(-1.6, 0, -6.0), Vector3(-2.5, 0, -4.5)]:
		var z = Zombie.new()
		main.world.add_child(z)
		z.global_position = p0.global_position + off
		z.set_physics_process(false)
		z.look_at(p0.global_position, Vector3.UP)
