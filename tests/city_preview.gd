extends SceneTree
## Проверка города: число узлов и экземпляров, зазор 25 м от этажа, снимок при SHOT=путь.
##   godot --headless --path . -s tests/city_preview.gd
const City := preload("res://scripts/city.gd")

var _bmin := Vector3(-10, 0, -10)
var _bmax := Vector3(30, 0, 20)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var city: Node3D = City.build(world, _bmin, _bmax, 12345)
	var nodes := 0
	var instances := 0
	var violations := 0
	var min_gap := INF
	var stack: Array = [city]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		stack.append_array(n.get_children())
		if n is MultiMeshInstance3D:
			instances += n.multimesh.instance_count
			print("%s: %d instances" % [n.name, n.multimesh.instance_count])
	# Headless не возвращает данные MultiMesh, поэтому проверяем башни по мета-данным города.
	var towers: Array = city.get_meta("towers")
	for t in towers:
		var pos: Vector2 = t["pos"]
		var rot := Basis(Vector3.UP, t["yaw"])
		var ex: Vector3 = rot.x * t["w"] * 0.5
		var ez: Vector3 = rot.z * t["d"] * 0.5
		var corners: Array[Vector2] = []
		for c: Vector3 in [ex + ez, ex - ez, -ex - ez, -ex + ez]:
			corners.append(pos + Vector2(c.x, c.z))
		var gap := _footprint_gap(corners)
		min_gap = minf(min_gap, gap)
		if gap < City.GAP:
			violations += 1
	print("nodes: %d" % nodes)
	print("total instances: %d" % instances)
	print("towers: %d" % towers.size())
	print("draw calls (MultiMesh instances): %d" % _mesh_count(city))
	print("min footprint gap to bounds: %.2f m (need >= %.0f)" % [min_gap, City.GAP])
	print("footprints closer than %.0f m: %d" % [City.GAP, violations])
	print("RESULT: %s" % ("OK" if violations == 0 else "FAIL"))

	var shot := OS.get_environment("SHOT") if OS.has_environment("SHOT") else ""
	if shot != "":
		_shot(world, shot)
	else:
		quit(0 if violations == 0 else 1)


## Расстояние от контура футпринта (по точкам рёбер) до прямоугольника этажа; 0 — пересечение.
func _footprint_gap(corners: Array[Vector2]) -> float:
	var bmin := Vector2(_bmin.x, _bmin.z)
	var bmax := Vector2(_bmax.x, _bmax.z)
	var best := INF
	for i in corners.size():
		var a := corners[i]
		var b := corners[(i + 1) % corners.size()]
		for k in 201:
			var p := a.lerp(b, k / 200.0)
			best = minf(best, _rect_dist(p, bmin, bmax))
	return best


func _rect_dist(p: Vector2, bmin: Vector2, bmax: Vector2) -> float:
	var dx := maxf(maxf(bmin.x - p.x, 0.0), p.x - bmax.x)
	var dz := maxf(maxf(bmin.y - p.y, 0.0), p.y - bmax.y)
	return Vector2(dx, dz).length()


func _mesh_count(node: Node) -> int:
	var count := 0
	for c in node.get_children():
		if c is MeshInstance3D or c is MultiMeshInstance3D:
			count += 1
	return count


func _shot(world: Node3D, path: String) -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color.BLACK
	env.fog_density = 0.045
	env_node.environment = env
	world.add_child(env_node)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(10, 1.7, 0)
	cam.look_at(Vector3(200, 1.7, 0), Vector3.UP)
	cam.make_current()
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	quit(0)
