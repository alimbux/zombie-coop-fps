extends Node
## Игровая сцена. Строит уровень по выбранному режиму (этажи или волны), делит экран
## на 1–4 части и раздаёт игрокам управление. Все части смотрят в один общий 3D-мир,
## у каждой свой нуар-фильтр и интерфейс.

const NoirShader := preload("res://shaders/noir.gdshader")
const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/player_hud.gd")
const SpawnerScript := preload("res://scripts/zombie_spawner.gd")
const TestRoom := preload("res://scripts/test_room.gd")
const LevelGenerator := preload("res://scripts/level_generator.gd")
const GameConfig := preload("res://scripts/game_config.gd")
const Sfx := preload("res://scripts/sfx.gd")

const MENU_SCENE := "res://scenes/menu.tscn"
const EXIT_RADIUS := 2.0

var world: Node3D
var players: Array = []
var huds: Array = []
var spawner: Node
var level = null
var _finishing := false


func _ready() -> void:
	randomize()
	Engine.time_scale = 1.0
	Sfx.preload_all()
	var count: int = GameConfig.players
	var cameras := _build_screens(count)

	var starts: Array
	if GameConfig.mode == GameConfig.Mode.ESCAPE:
		level = LevelGenerator.new()
		starts = level.build(world, GameConfig.floor_number, count, randi())["player_starts"]
	else:
		var layout: Dictionary = TestRoom.build(world)
		starts = layout["player_starts"]
		spawner = SpawnerScript.new()
		spawner.world = world
		spawner.players = count
		spawner.spawn_points = layout["zombie_spawns"]
		spawner.pickup_points = layout["pickup_points"]
		spawner.wave_started.connect(_on_wave_started)
		add_child(spawner)

	var pads := Input.get_connected_joypads()
	for i in count:
		var player = PlayerScript.new()
		player.setup(i, _pad_for(i, count, pads), cameras[i], huds[i])
		world.add_child(player)
		player.global_position = starts[i]
		if i < GameConfig.loadouts.size():
			player.set_loadout(GameConfig.loadouts[i])
		players.append(player)

	if level != null:
		for hud in huds:
			hud.set_level("ЭТАЖ %d" % GameConfig.floor_number)
			hud.show_message("НАЙДИ ВЫХОД", 3.0)


## Игрок 1 всегда может играть на клавиатуре и мыши. Если геймпадов хватает на всех,
## у каждого свой геймпад; если нет — игрок 1 без геймпада, остальные берут их по порядку.
static func _pad_for(i: int, count: int, pads: Array) -> int:
	if pads.size() >= count:
		return pads[i]
	if i == 0:
		return -1
	return pads[i - 1] if i - 1 < pads.size() else -1


## Делит экран: один игрок — весь экран, двое — пополам, трое и четверо — на четыре части.
func _build_screens(count: int) -> Array:
	var shared_world := World3D.new()
	# Белый фон проступает тонкими полосами между частями экрана.
	var background := ColorRect.new()
	background.color = Color.WHITE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var grid := GridContainer.new()
	grid.columns = 1 if count == 1 else 2
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)

	world = Node3D.new()
	world.name = "World"
	var cameras: Array = []
	var cells := 4 if count == 3 else count
	for i in cells:
		var half := Control.new()
		half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		half.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(half)
		if i >= count:
			# Пустая четвёртая клетка при трёх игроках.
			var filler := ColorRect.new()
			filler.color = Color.BLACK
			filler.set_anchors_preset(Control.PRESET_FULL_RECT)
			half.add_child(filler)
			continue

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
	return cameras


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		players[0].add_mouse_look(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			players[0].cycle_weapon(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			players[0].cycle_weapon(1)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_to_menu()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		_to_menu()


func _process(_delta: float) -> void:
	if _finishing:
		return
	var alive := 0
	var at_exit := 0
	for p in players:
		if not p.downed:
			alive += 1
			if level != null and Vector2(p.global_position.x - level.exit_position.x, p.global_position.z - level.exit_position.z).length() < EXIT_RADIUS:
				at_exit += 1
	if alive == 0:
		_restart()
	elif level != null and at_exit == alive:
		_floor_complete()
	elif level != null and at_exit > 0:
		for hud in huds:
			hud.show_message("ВЫХОД НАЙДЕН — ВСЕ К ВЫХОДУ", 0.3)


func _floor_complete() -> void:
	_finishing = true
	GameConfig.loadouts = players.map(func(p): return p.get_loadout())
	GameConfig.floor_number += 1
	for hud in huds:
		hud.show_message("ЭТАЖ ПРОЙДЕН", 3.0)
	await get_tree().create_timer(1.5, true, false, true).timeout
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


## Все пали: этаж начинается заново (новая планировка, снаряжение как было на входе),
## волны — с первой.
func _restart() -> void:
	_finishing = true
	if GameConfig.mode == GameConfig.Mode.WAVES:
		GameConfig.loadouts = []
	for hud in huds:
		hud.show_message("ВСЕ ПАЛИ", 3.0)
	await get_tree().create_timer(2.5, true, false, true).timeout
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _to_menu() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_wave_started(number: int) -> void:
	for hud in huds:
		hud.set_level("ВОЛНА %d" % number)
		hud.show_message("ВОЛНА %d" % number)
