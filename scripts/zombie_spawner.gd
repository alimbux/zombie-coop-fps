extends Node
## Режим «Волны»: зомби лезут волнами, каждая больше предыдущей.
## Между волнами в зале появляются патроны, оружие и изредка аптечка.

signal wave_started(number: int)

const Zombie := preload("res://scripts/zombie.gd")
const Pickup := preload("res://scripts/pickup.gd")
const MAX_ALIVE := 40
const SPAWN_INTERVAL := 0.7
const REST_BETWEEN_WAVES := 4.0

var world: Node3D
var spawn_points: Array = []
## Где раскладывать находки между волнами.
var pickup_points: Array = []
var players := 1
var wave := 0
var _to_spawn := 0
var _spawn_timer := 0.0
var _rest_timer := 2.0


func _process(delta: float) -> void:
	var alive := get_tree().get_nodes_in_group("zombies").size()
	if _to_spawn > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0 and alive < MAX_ALIVE:
			_spawn_one()
			_to_spawn -= 1
			_spawn_timer = SPAWN_INTERVAL
	elif alive == 0:
		_rest_timer -= delta
		if _rest_timer <= 0.0:
			_start_wave()


func _start_wave() -> void:
	wave += 1
	_to_spawn = 4 + wave * 3
	_rest_timer = REST_BETWEEN_WAVES
	_drop_pickups()
	wave_started.emit(wave)


func _spawn_one() -> void:
	var zombie = Zombie.new()
	world.add_child(zombie)
	var point: Vector3 = spawn_points.pick_random()
	zombie.global_position = point + Vector3(randf_range(-1.0, 1.0), 0.1, randf_range(-1.0, 1.0))


## Перед каждой волной в комнате появляются патроны, иногда оружие и редко аптечка.
## Перед первой — по пистолету на игрока, ведь в начале у всех только нож.
func _drop_pickups() -> void:
	for p in get_tree().get_nodes_in_group("pickups"):
		p.queue_free()
	var items: Array = []
	if wave == 1:
		for i in players:
			items.append(["weapon", "pistol"])
	for i in players:
		items.append(["ammo", ["pistol", "smg", "shotgun"].pick_random()])
	if wave % 2 == 0:
		items.append(["weapon", ["smg", "shotgun"].pick_random()])
	if wave % 3 == 0:
		items.append(["medkit", ""])
	var spots := pickup_points.duplicate()
	spots.shuffle()
	for i in items.size():
		var p = Pickup.new()
		p.kind = items[i][0]
		p.weapon = items[i][1]
		world.add_child(p)
		p.global_position = spots[i % spots.size()] + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
