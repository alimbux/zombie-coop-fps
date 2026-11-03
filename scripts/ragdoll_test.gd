extends Node
## Тестовая сцена для сравнения: слева наши блочные зомби, справа готовая модель
## с рэгдоллом (scripts/ragdoll_zombie.gd). Зал из режима «Волны», без волн:
## погибших заменяют новые. Запуск: godot --path . scenes/ragdoll_test.tscn
## или кнопка «Тест: готовая модель» в меню. Esc — в меню.

const Zombie := preload("res://scripts/zombie.gd")
const RagdollZombie := preload("res://scripts/ragdoll_zombie.gd")
const GameConfig := preload("res://scripts/game_config.gd")

const PAIRS := 2
## Зомби встают в дальнем конце зала: наши слева, готовая модель справа.
const OURS_AT := [Vector3(-3.5, 0.1, -6), Vector3(-5.5, 0.1, -9)]
const MODEL_AT := [Vector3(3.5, 0.1, -6), Vector3(5.5, 0.1, -9)]

var main: Node
var _respawn := 0.0


func _ready() -> void:
	GameConfig.new_game(GameConfig.Mode.WAVES, 1)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	if main.spawner:
		main.spawner.queue_free()
		main.spawner = null
	for z in get_tree().get_nodes_in_group("zombies"):
		z.queue_free()
	for p in get_tree().get_nodes_in_group("pickups"):
		p.queue_free()
	var p = main.players[0]
	p.give_weapon("pistol", 192)
	p.give_weapon("smg", 480)
	p.give_weapon("shotgun", 96)
	p.hp = 100000.0
	for hud in main.huds:
		hud.show_message("СЛЕВА НАШИ, СПРАВА ГОТОВАЯ МОДЕЛЬ", 4.0)


func _process(delta: float) -> void:
	_respawn -= delta
	if _respawn > 0.0:
		return
	_respawn = 1.0
	var ours := 0
	var theirs := 0
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is RagdollZombie:
			theirs += 1
		else:
			ours += 1
	if ours < PAIRS:
		spawn_ours(OURS_AT[ours % OURS_AT.size()])
	if theirs < PAIRS:
		spawn_model(MODEL_AT[theirs % MODEL_AT.size()])


func spawn_ours(at: Vector3) -> Node3D:
	var z = Zombie.new()
	main.world.add_child(z)
	z.global_position = at
	z.gait = "walk"
	return z


func spawn_model(at: Vector3) -> Node3D:
	var z = RagdollZombie.new()
	main.world.add_child(z)
	z.global_position = at
	return z
