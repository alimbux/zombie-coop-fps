extends SceneTree
## Быстрая проверка без окна:
##   godot --headless --path . -s tests/smoke_test.gd
## Сцена запускается, попадание в голову убивает, отрыв ноги заставляет ползти,
## торс убивает за несколько попаданий, выстрел игрока через луч доходит до зомби.

const Zombie := preload("res://scripts/zombie.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	var world: Node3D = main.world

	var z1 = _spawn(world, Vector3(4, 0.1, -6))
	await _frames(2)
	_check(z1.take_hit("head", 34.0, z1.global_position + Vector3.UP * 1.66, Vector3.FORWARD), "попадание в голову убивает")

	var z2 = _spawn(world, Vector3(6, 0.1, -6))
	await _frames(2)
	z2.take_hit("leg_l", 34.0, z2.global_position + Vector3.UP * 0.3, Vector3.FORWARD)
	z2.take_hit("leg_l", 34.0, z2.global_position + Vector3.UP * 0.3, Vector3.FORWARD)
	_check(z2.crawling and not z2.dead, "без ноги зомби ползёт")
	_check(not z2.parts.has("leg_l"), "нога оторвана")

	var z3 = _spawn(world, Vector3(8, 0.1, -6))
	await _frames(2)
	var hits := 0
	while not z3.dead and hits < 10:
		z3.take_hit("torso", 34.0, z3.global_position + Vector3.UP * 1.0, Vector3.FORWARD)
		hits += 1
	_check(z3.dead and hits == 4, "торс убивает за 4 попадания (было %d)" % hits)

	# Выстрел игрока: зомби стоит прямо перед ним, прицел на уровне головы.
	var player = main.players[0]
	var z4 = _spawn(world, player.global_position + Vector3(0, 0, -4))
	z4.set_physics_process(false)
	await _frames(3)
	var zone: String = player.shoot()
	_check(zone == "head" and z4.dead, "выстрел игрока в голову (зона «%s»)" % zone)

	await _frames(120)
	print("Зомби в комнате после 2 секунд: ", get_nodes_in_group("zombies").size())
	print("ГОТОВО: ошибок ", _failures)
	quit(_failures)


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
