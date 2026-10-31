extends Node
## Волны зомби для прототипа: каждая следующая больше предыдущей.
## Позже заменится спавном по комнатам из процедурного генератора.

signal wave_started(number: int)

const Zombie := preload("res://scripts/zombie.gd")
const MAX_ALIVE := 40
const SPAWN_INTERVAL := 0.7
const REST_BETWEEN_WAVES := 4.0

var world: Node3D
var spawn_points: Array = []
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
	wave_started.emit(wave)


func _spawn_one() -> void:
	var zombie = Zombie.new()
	world.add_child(zombie)
	var point: Vector3 = spawn_points.pick_random()
	zombie.global_position = point + Vector3(randf_range(-1.0, 1.0), 0.1, randf_range(-1.0, 1.0))
