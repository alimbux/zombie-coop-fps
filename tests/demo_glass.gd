extends SceneTree
## Демо-ролик (не для CI): xvfb-run godot --rendering-driver opengl3 --write-movie out.avi --fixed-fps 30 --path . -s tests/demo_glass.gd
## Вид от первого лица: город за окном, две пули разбивают секцию, удар ногой выбрасывает
## зомби в проём, потом игрок сам шагает в пустоту и разбивается.
const Zombie := preload("res://scripts/zombie.gd")
const GameConfig := preload("res://scripts/game_config.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 3)
	GameConfig.new_game(GameConfig.Mode.ESCAPE, 1)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# Без перезапуска этажа, когда единственный игрок выпал: досмотреть экран «РАЗБИЛСЯ».
	main._finishing = true
	await _f(5)
	for z in get_nodes_in_group("zombies"):
		z.free()
	var level = main.level
	# Окно стартовой комнаты, если есть, иначе любое.
	var pick: Dictionary = level.glass_walls[0]
	for g in level.glass_walls:
		if g["cell"] == level.start_cell:
			pick = g
	var win: Node3D = pick["node"]
	var out: Vector3 = win.outward
	var sec = win.sections[(win.sections.size() - 1) / 2]
	var glass: Vector3 = sec.center
	glass.y = 0.0
	var p = main.players[0]
	p.hp = 100000.0
	p.give_weapon("pistol", 60)
	p.switch_to("pistol")
	p.global_position = glass - out * 4.2 + Vector3.UP * 0.1
	p.yaw = atan2(-out.x, -out.z)
	p.pitch = 0.05
	await _f(45)
	var z = Zombie.new()
	main.world.add_child(z)
	z.global_position = glass - out * 1.4 + Vector3.UP * 0.1
	z.look_at(z.global_position - out, Vector3.UP)
	z.aware = false
	await _f(45)
	# Целиться выше головы зомби, в стекло за ним.
	p.pitch = 0.22
	await _f(10)
	for i in 2:
		p.shoot()
		await _f(18)
	p.pitch = 0.0
	# Зомби услышал выстрелы и идёт к игроку; ударить, когда подойдёт.
	for i in 150:
		await physics_frame
		if is_instance_valid(z) and z.global_position.distance_to(p.global_position) < 1.6:
			break
	p.kick()
	await _f(75)
	# Шаг к проёму и в пустоту.
	for i in 150:
		await physics_frame
		if p.fell:
			break
		p.global_position += out * 1.6 / 30.0
	await _f(110)
	quit(0)


func _f(n: int) -> void:
	for i in n:
		await physics_frame
