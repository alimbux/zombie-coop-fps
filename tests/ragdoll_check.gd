extends SceneTree
## Проверка тестовой сцены с готовой моделью:
##   godot --headless --path . -s tests/ragdoll_check.gd
## Сцена грузится, зомби обоих видов появляются, пули по модели включают рэгдолл,
## убитая модель падает телом.

const RagdollZombie := preload("res://scripts/ragdoll_zombie.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node = load("res://scenes/ragdoll_test.tscn").instantiate()
	root.add_child(scene)
	for i in 90:
		await physics_frame
	var model = null
	var ours := 0
	for z in get_nodes_in_group("zombies"):
		if z is RagdollZombie:
			model = z
		else:
			ours += 1
	_check(ours >= 1, "наши зомби на месте")
	_check(model != null, "готовая модель на месте")
	if model:
		var head: Vector3 = model._attach["Head"].global_position
		model.take_hit("torso", 20.0, model.global_position + Vector3.UP * 1.2, Vector3.FORWARD)
		_check(model._sim.is_simulating_physics(), "попадание включает частичный рэгдолл")
		for i in 60:
			await physics_frame
		_check(not model._sim.is_simulating_physics(), "через полсекунды анимация возвращается")
		var killed := false
		for i in 10:
			killed = model.take_hit("head", 34.0, head, Vector3.FORWARD) or killed
		_check(killed and model.dead, "пули в голову убивают")
		for i in 90:
			await physics_frame
		var top: Vector3 = model._attach["Torso"].global_position
		_check(top.y < model.global_position.y + 0.7, "тело лежит на полу (грудь на высоте %.2f)" % (top.y - model.global_position.y))
	print("ГОТОВО: ошибок ", _failures)
	quit(_failures)


func _check(ok: bool, what: String) -> void:
	print(("ок   " if ok else "ОШИБКА ") + what)
	if not ok:
		_failures += 1
