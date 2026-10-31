extends Node
## Прототип: тестовая комната, игроки от первого лица на разделённом экране, волны зомби.
## Все половины экрана смотрят в один общий 3D-мир, у каждой свой нуар-фильтр и интерфейс.

const PLAYER_COUNT := 2
const NoirShader := preload("res://shaders/noir.gdshader")
const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/player_hud.gd")
const SpawnerScript := preload("res://scripts/zombie_spawner.gd")
const TestRoom := preload("res://scripts/test_room.gd")
const Sfx := preload("res://scripts/sfx.gd")

var world: Node3D
var players: Array = []
var huds: Array = []
var spawner: Node
var _restarting := false


func _ready() -> void:
	randomize()
	Engine.time_scale = 1.0
	Sfx.preload_all()
	var shared_world := World3D.new()

	# Белый фон проступает тонкой полосой между половинами экрана.
	var background := ColorRect.new()
	background.color = Color.WHITE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var split := HBoxContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 4)
	add_child(split)

	world = Node3D.new()
	world.name = "World"
	var cameras: Array = []
	for i in PLAYER_COUNT:
		var half := Control.new()
		half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		half.size_flags_vertical = Control.SIZE_EXPAND_FILL
		split.add_child(half)

		var container := SubViewportContainer.new()
		container.stretch = true
		container.set_anchors_preset(Control.PRESET_FULL_RECT)
		var mat := ShaderMaterial.new()
		mat.shader = NoirShader
		mat.set_shader_parameter("seed_offset", float(i) * 17.0)
		container.material = mat
		half.add_child(container)

		var viewport := SubViewport.new()
		viewport.world_3d = shared_world
		viewport.audio_listener_enable_3d = i == 0
		container.add_child(viewport)
		if i == 0:
			viewport.add_child(world)
		var cam := Camera3D.new()
		viewport.add_child(cam)
		cam.current = true
		cameras.append(cam)

		var hud: Control = HudScript.new()
		half.add_child(hud)
		huds.append(hud)

	var layout: Dictionary = TestRoom.build(world)
	for i in PLAYER_COUNT:
		var player = PlayerScript.new()
		player.setup(i, cameras[i], huds[i])
		world.add_child(player)
		player.global_position = layout["player_starts"][i]
		players.append(player)

	spawner = SpawnerScript.new()
	spawner.world = world
	spawner.spawn_points = layout["zombie_spawns"]
	spawner.wave_started.connect(_on_wave_started)
	add_child(spawner)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		players[0].add_mouse_look(event.relative)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	if _restarting:
		return
	for p in players:
		if not p.downed:
			return
	_restart()


func _restart() -> void:
	_restarting = true
	for hud in huds:
		hud.show_message("ВСЕ ПАЛИ", 3.0)
	await get_tree().create_timer(2.5, true, false, true).timeout
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _on_wave_started(number: int) -> void:
	for hud in huds:
		hud.show_message("ВОЛНА %d" % number)
