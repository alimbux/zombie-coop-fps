extends SceneTree
## Снимок экрана (нужен экран или Xvfb, рендер opengl3):
##   SHOT=/tmp/shot.png VIEW=escape PLAYERS=4 godot --rendering-driver opengl3 --path . -s tests/screenshot.gd
## VIEW: menu, waves, escape или gallery (четыре игрока и зомби с разными ранениями).
const Zombie := preload("res://scripts/zombie.gd")
const GameConfig := preload("res://scripts/game_config.gd")
const PlayerModel := preload("res://scripts/player_model.gd")
const Gore := preload("res://scripts/gore.gd")


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
		elif view == "gallery":
			await _stage_gallery(main)
		for i in 20:
			await physics_frame
		if view != "gallery":
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


## Витрина. PART=players — четыре персонажа лицом к камере;
## PART=zombies — зомби: целый, со вскрытым черепом, без правой ноги, без левой, без обеих.
func _stage_gallery(main: Node) -> void:
	var part := OS.get_environment("PART") if OS.has_environment("PART") else "zombies"
	var p0 = main.players[0]
	p0.yaw = 0.0
	p0.pitch = -0.1
	main.players[0].switch_to("knife")
	var base: Vector3 = p0.global_position + Vector3(0, 0, -3.0 if part == "players" else -4.5)
	var lamp := OmniLight3D.new()
	lamp.omni_range = 8.0
	lamp.light_energy = 1.4
	main.world.add_child(lamp)
	lamp.global_position = base + Vector3(0, 2.4, 1.6)
	if part == "blood":
		await _stage_blood(main, p0)
		return
	if part == "players":
		for i in 4:
			var m = PlayerModel.new()
			main.world.add_child(m)
			m.build(i, 1)
			m.global_position = base + Vector3(-1.35 + i * 0.9, 0, 0)
			m.rotation.y = PI + 0.55
			m.animate(0.05, 0.0, 0.0, false)
		return
	var specs := [["", Vector3(-1.5, 0, -0.6)], ["skull", Vector3(-0.4, 0, -0.5)], ["leg_r", Vector3(0.9, 0, -0.9)], ["leg_l", Vector3(-1.0, 0, 0.6)], ["both", Vector3(0.6, 0, 0.5)]]
	var sideways := false
	if part == "skull":
		specs = [["", Vector3(-0.9, 0, 2.2)], ["skull", Vector3(0.0, 0, 2.6)]]
	elif part == "mix":
		# Игроки рядом с зомби разных походок: видно, кто живой.
		for i in 2:
			var m = PlayerModel.new()
			main.world.add_child(m)
			m.build(i, 1)
			m.global_position = base + Vector3(-1.2 + i * 0.8, 0, 1.2)
			m.rotation.y = PI + 0.4
			m.animate(0.05, 0.0, 0.0, false)
		specs = [["walk", Vector3(0.6, 0, 0.6)], ["limp", Vector3(1.4, 0, 0.2)], ["fast", Vector3(-0.2, 0, -0.3)]]
	elif part == "crawl":
		specs = [["leg_r", Vector3(1.6, 0, 1.6)], ["leg_l", Vector3(2.4, 0, 0.4)], ["both", Vector3(3.4, 0, 1.6)]]
		sideways = true
	var zombies := []
	for spec in specs:
		var z = Zombie.new()
		main.world.add_child(z)
		z.global_position = base + spec[1]
		z.set_physics_process(false)
		z.look_at(z.global_position + (Vector3.LEFT if sideways else p0.global_position - z.global_position), Vector3.UP)
		if spec[0] in ["walk", "limp", "fast"]:
			z.gait = spec[0]
		zombies.append([z, spec[0]])
	for i in 3:
		await physics_frame
	for pair in zombies:
		var z = pair[0]
		var at: Vector3 = z.global_position
		var dir: Vector3 = (at - p0.global_position).normalized()
		match pair[1]:
			"skull":
				var c: Vector3 = z.parts["head"].to_global(Zombie.ZONES["head"]["center"])
				z.take_hit("head", 30.0, c + Vector3(0.13, 0, 0), dir)
			"leg_r", "leg_l":
				z.take_hit(pair[1], 60.0, at + Vector3(0, 0.4, 0), dir)
			"both":
				z.take_hit("leg_l", 60.0, at + Vector3(0, 0.4, 0), dir)
				z.take_hit("leg_r", 60.0, at + Vector3(0, 0.4, 0), dir)
			"walk", "limp", "fast":
				pass
			_:
				z.take_hit("torso", 15.0, at + Vector3(0.1, 1.2, 0) - dir * 0.15, dir)
				z.take_hit("arm_l", 10.0, z.parts["arm_l"].to_global(Vector3(0, -0.3, 0)), dir)
	for i in int(OS.get_environment("FRAMES")) if OS.has_environment("FRAMES") else 40:
		await physics_frame
		for pair in zombies:
			if is_instance_valid(pair[0]):
				pair[0]._animate(1.0 / 60.0, 1.0)


## PART=blood — пол после перестрелки: кляксы, потёки по направлению выстрелов, лужи,
## капли от раненых и размазанный след ползущего.
func _stage_blood(main: Node, p0) -> void:
	p0.pitch = -0.75
	var world: Node3D = main.world
	var o: Vector3 = p0.global_position
	for i in 7:
		var at := o + Vector3(randf_range(-2.5, 2.5), 1.0, -randf_range(2.0, 5.5))
		var dir := (at - o).normalized()
		Gore.burst(world, at, dir, 0) if i % 2 == 0 else Gore.splash(world, at, dir, 0)
	# Петляющий след ползущего и капли раненого, шедшего наискосок.
	var path := o + Vector3(-2.2, 0.0, -1.6)
	for i in 14:
		var step := Vector3(0.38, 0, -0.12 - sin(i * 0.5) * 0.2)
		path += step
		Gore.floor_stain(world, path, "smear", 0.32, step)
	for i in 9:
		var d := o + Vector3(2.4 - i * 0.35, 0, -1.4 - i * 0.45)
		Gore.floor_stain(world, d, "drops", randf_range(0.12, 0.2), Vector3(-0.35, 0, -0.45))
	for i in 3:
		await physics_frame
