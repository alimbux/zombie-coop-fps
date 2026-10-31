extends SceneTree
## Быстрая проверка без окна:
##   godot --headless --path . -s tests/smoke_test.gd
## Меню и оба режима запускаются, ранения работают по зонам, оружие тратит и находит
## патроны, патронами можно поделиться, генератор этажей строит связный уровень.

const Zombie := preload("res://scripts/zombie.gd")
const GameConfig := preload("res://scripts/game_config.gd")
const LevelGenerator := preload("res://scripts/level_generator.gd")
const Pickup := preload("res://scripts/pickup.gd")
const Weapons := preload("res://scripts/weapons.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_menu()
	await _test_generator()
	await _test_waves()
	await _test_escape()
	print("ГОТОВО: ошибок ", _failures)
	quit(_failures)


func _test_menu() -> void:
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await _frames(2)
	_check(menu.start_button != null and menu.start_button.has_focus(), "меню открылось, «НАЧАТЬ» в фокусе")
	menu._set_mode(GameConfig.Mode.WAVES)
	menu._set_players(3)
	GameConfig.new_game(menu._mode, menu._players)
	_check(GameConfig.mode == GameConfig.Mode.WAVES and GameConfig.players == 3, "меню выбирает режим и число игроков")
	menu.queue_free()
	await _frames(1)


func _test_generator() -> void:
	for floor_number in [1, 4, 12]:
		for players in [1, 4]:
			var world := Node3D.new()
			root.add_child(world)
			var gen = LevelGenerator.new()
			var result: Dictionary = gen.build(world, floor_number, players, 1000 + floor_number * 7 + players)
			var cells: Array = gen.cells
			var tag := "этаж %d, игроков %d" % [floor_number, players]
			_check(cells.size() == mini(5 + 2 * floor_number, 45), "%s: комнат %d" % [tag, cells.size()])
			_check(result["player_starts"].size() >= players, "%s: стартовые точки" % tag)
			_check(gen.exit_cell != gen.start_cell, "%s: выход не в стартовой комнате" % tag)
			# Из любой комнаты по подсказкам навигации можно дойти до старта.
			var all_reach := true
			for c in cells:
				var pos: Vector3 = gen.center(c)
				var steps := 0
				while gen.cell_of(pos) != gen.start_cell and steps < 100:
					pos = gen.next_waypoint(pos, gen.center(gen.start_cell))
					steps += 1
				all_reach = all_reach and gen.cell_of(pos) == gen.start_cell
			_check(all_reach, "%s: из любой комнаты есть путь к игрокам" % tag)
			var in_start := 0
			var zombies := 0
			var medkits := 0
			for n in world.get_children():
				if n is Zombie:
					zombies += 1
					if gen.cell_of(n.position) == gen.start_cell:
						in_start += 1
				elif n is Pickup and n.kind == "medkit":
					medkits += 1
			_check(zombies > 0 and in_start == 0, "%s: зомби %d, в стартовой комнате нет" % [tag, zombies])
			_check(medkits <= maxi(1, cells.size() / 5), "%s: аптечек %d — редко" % [tag, medkits])
			world.free()
	await _frames(1)


func _test_waves() -> void:
	GameConfig.new_game(GameConfig.Mode.WAVES, 2)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	var world: Node3D = main.world
	_check(main.players.size() == 2, "волны: двое игроков")

	var z1 = _spawn(world, Vector3(4, 0.1, -6))
	await _frames(2)
	_check(z1.take_hit("head", 34.0, z1.parts["head"].to_global(Zombie.ZONES["head"]["center"]), Vector3.FORWARD), "попадание в голову убивает")

	var z2 = _spawn(world, Vector3(6, 0.1, -6))
	await _frames(2)
	z2.take_hit("leg_l", 34.0, z2.global_position + Vector3.UP * 0.3, Vector3.FORWARD)
	z2.take_hit("leg_l", 34.0, z2.global_position + Vector3.UP * 0.3, Vector3.FORWARD)
	_check(z2.crawling and not z2.dead and z2.crawl_style == "right", "без левой ноги ползёт с опорой на правую")
	z2.take_hit("leg_r", 60.0, z2.global_position + Vector3.UP * 0.3, Vector3.FORWARD)
	_check(z2.crawl_style == "arms" and not z2.dead, "без обеих ног ползёт на руках")

	var zr = _spawn(world, Vector3(2, 0.1, -6))
	await _frames(2)
	zr.take_hit("leg_r", 60.0, zr.global_position + Vector3.UP * 0.3, Vector3.FORWARD)
	_check(zr.crawl_style == "left", "без правой ноги ползёт с опорой на левую")
	await _frames(30)
	_check(not zr.dead and zr.body.rotation.x < -1.0, "ползущий лежит лицом вниз")

	# Походки: хромой идёт рывками и в среднем медленнее, быстрый — быстрее обычного.
	var zw = _spawn(world, Vector3(-8, 0.1, -9))
	await _frames(1)
	var avg := {}
	for g in ["walk", "limp", "fast"]:
		zw.gait = g
		var total := 0.0
		for i in 60:
			zw._phase = TAU * i / 60.0
			total += zw._move_speed()
		avg[g] = total / 60.0
	zw.queue_free()
	_check(avg["fast"] > avg["walk"] * 1.4 and avg["limp"] < avg["walk"], "быстрые быстрее, хромые медленнее (%.2f / %.2f / %.2f)" % [avg["fast"], avg["walk"], avg["limp"]])

	# Вскользь по голове: череп вскрыт, зомби жив; второе попадание в голову убивает.
	var zg = _spawn(world, Vector3(-4, 0.1, -6))
	await _frames(2)
	var head_center: Vector3 = zg.parts["head"].to_global(Zombie.ZONES["head"]["center"])
	var edge := head_center + Vector3(0.13, 0, 0)
	_check(zg.is_glancing(edge, Vector3.FORWARD) and not zg.is_glancing(head_center, Vector3.FORWARD), "край головы считается касательным, центр — нет")
	_check(not zg.take_hit("head", 34.0, edge, Vector3.FORWARD) and zg.skull_open, "вскользь по голове: череп вскрыт, зомби жив")
	_check(zg.take_hit("head", 22.0, head_center, Vector3.FORWARD), "второе попадание во вскрытую голову убивает")

	var z3 = _spawn(world, Vector3(8, 0.1, -6))
	await _frames(2)
	var hits := 0
	while not z3.dead and hits < 10:
		z3.take_hit("torso", 34.0, z3.global_position + Vector3.UP * 1.0, Vector3.FORWARD)
		hits += 1
	_check(z3.dead and hits == 4, "торс убивает за 4 попадания (было %d)" % hits)

	var p1 = main.players[0]
	var p2 = main.players[1]
	_check(p1.current == "knife" and p1.owned == ["knife"], "в начале только нож")
	_check(p1.give_weapon("pistol", 24) and p1.current == "pistol", "подобрал пистолет и взял в руки")
	_check(p1.mag["pistol"] == 12 and p1.reserve["pistol"] == 12, "24 патрона: 12 в магазине, 12 в запасе")
	p1.give_ammo("pistol", 500)
	_check(p1.reserve["pistol"] == Weapons.stat("pistol", "max_reserve"), "запас не больше предела")

	# Убираем остальных зомби, чтобы никто не толкал игрока и не тряс камеру.
	for z in get_nodes_in_group("zombies"):
		z.queue_free()
	p1._shake = 0.0
	p1.yaw = 0.0
	p1.pitch = 0.0
	await _frames(2)
	var z4 = _spawn(world, p1.global_position + Vector3(0, 0, -4))
	z4.set_physics_process(false)
	await _frames(3)
	# Голова ровно на линии взгляда (игрок мог чуть подпрыгнуть на неровности пола).
	var head_y: float = z4.parts["head"].to_global(Zombie.ZONES["head"]["center"]).y
	z4.global_position.y += p1.camera.global_position.y - head_y
	await _frames(1)
	var zone: String = p1.shoot()
	_check(zone == "head" and z4.dead, "выстрел из пистолета в голову (зона «%s»)" % zone)
	_check(p1.mag["pistol"] == 11, "выстрел тратит патрон")

	p1.switch_to("knife")
	var z5 = _spawn(world, p1.global_position + Vector3(0, 0, -1.2))
	z5.set_physics_process(false)
	await _frames(3)
	p1.shoot()
	_check(z5.dead and p1.mag["pistol"] == 11, "нож убивает вплотную и не тратит патроны")

	p1.switch_to("pistol")
	p1.mag["pistol"] = 2
	p1.reserve["pistol"] = 5
	p1._start_reload()
	p1._finish_reload()
	_check(p1.mag["pistol"] == 7 and p1.reserve["pistol"] == 0, "перезарядка берёт из запаса (%d/%d)" % [p1.mag["pistol"], p1.reserve["pistol"]])

	p1.reserve["pistol"] = 40
	p2.global_position = p1.global_position + Vector3(1.0, 0, 0)
	await _frames(2)
	var given: int = p1.share_ammo()
	_check(given == 20 and p1.reserve["pistol"] == 20 and p2.reserve["pistol"] == 20, "поделился патронами: %d" % given)
	p2.global_position = p1.global_position + Vector3(8.0, 0, 0)
	await _frames(2)
	_check(p1.share_ammo() == 0, "далеко от напарника — не передаёт")

	p2.hp = 50.0
	var kit = Pickup.new()
	kit.kind = "medkit"
	world.add_child(kit)
	_check(kit.try_give(p2) and p2.hp == 90.0, "аптечка лечит 40")

	for z in get_nodes_in_group("zombies"):
		z.queue_free()
	await _frames(240)
	print("Зомби в зале через 4 секунды: ", get_nodes_in_group("zombies").size(),
		", находок: ", get_nodes_in_group("pickups").size())
	_check(get_nodes_in_group("pickups").size() > 0, "перед волной появились находки")
	main.queue_free()
	await _frames(2)


func _test_escape() -> void:
	for count in [1, 3, 4]:
		GameConfig.new_game(GameConfig.Mode.ESCAPE, count)
		var main: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		await _frames(30)
		_check(main.players.size() == count and main.level != null, "побег: игроков %d, этаж построен" % count)
		var sleeping := 0
		for z in get_nodes_in_group("zombies"):
			if not z.aware:
				sleeping += 1
		_check(sleeping > 0, "побег: зомби бродят по этажу и ещё не заметили игроков (%d)" % sleeping)
		main.queue_free()
		await _frames(2)


func _spawn(world: Node3D, pos: Vector3):
	var z = Zombie.new()
	world.add_child(z)
	z.global_position = pos
	return z


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("OK   ", what)
	else:
		_failures += 1
		printerr("FAIL ", what)
