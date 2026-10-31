extends Control
## Главное меню: режим игры и число игроков. Управляется мышью, клавиатурой (стрелки,
## Enter) и геймпадом (крестовина, A). Всё чёрно-белое, выбранное — инверсией.

const GameConfig := preload("res://scripts/game_config.gd")
const GAME_SCENE := "res://scenes/main.tscn"
const BLOOD := Color(0.9, 0.0, 0.03)

var _mode: int = GameConfig.Mode.ESCAPE
var _players := 2
var _mode_buttons: Array = []
var _player_buttons: Array = []
var start_button: Button


func _ready() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mode = GameConfig.mode
	_players = GameConfig.players

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	var title := _label("ZOMBIE COOP", 64, Color.WHITE)
	box.add_child(title)
	box.add_child(_label("кооператив против зомби", 22, BLOOD))
	box.add_child(_spacer(20))

	box.add_child(_label("РЕЖИМ", 20, Color(0.6, 0.6, 0.6)))
	var modes := HBoxContainer.new()
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_theme_constant_override("separation", 12)
	box.add_child(modes)
	for m in [[GameConfig.Mode.ESCAPE, "ВЫБРАТЬСЯ ИЗ ЗДАНИЯ"], [GameConfig.Mode.WAVES, "ВОЛНЫ"]]:
		var b := _button(m[1], 360)
		b.pressed.connect(_set_mode.bind(m[0]))
		b.set_meta("value", m[0])
		modes.add_child(b)
		_mode_buttons.append(b)
	var hint := _label("", 18, Color(0.6, 0.6, 0.6))
	hint.name = "ModeHint"
	box.add_child(hint)

	box.add_child(_spacer(6))
	box.add_child(_label("ИГРОКОВ", 20, Color(0.6, 0.6, 0.6)))
	var counts := HBoxContainer.new()
	counts.alignment = BoxContainer.ALIGNMENT_CENTER
	counts.add_theme_constant_override("separation", 12)
	box.add_child(counts)
	for n in range(1, 5):
		var b := _button(str(n), 90)
		b.pressed.connect(_set_players.bind(n))
		b.set_meta("value", n)
		counts.add_child(b)
		_player_buttons.append(b)

	box.add_child(_spacer(16))
	start_button = _button("НАЧАТЬ", 360)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.pressed.connect(start_game)
	box.add_child(start_button)

	box.add_child(_spacer(10))
	box.add_child(_label(
		"Игрок 1 — клавиатура и мышь (или геймпад, если их хватает на всех), остальные — геймпады.\n"
		+ "Стрельба — ЛКМ / RT, смена оружия — 1–4, Q, колесо / Y, перезарядка — R / X,\n"
		+ "отдать патроны напарнику — G / B, поднять упавшего — стоять рядом, меню — Esc / Back.",
		16, Color(0.55, 0.55, 0.55)))

	_set_mode(_mode)
	_set_players(_players)
	start_button.grab_focus()


func _set_mode(value: int) -> void:
	_mode = value
	_refresh(_mode_buttons, value)
	var hint: Label = find_child("ModeHint", true, false)
	hint.text = ("Этажи растут, зомби бродят по комнатам. Ищи оружие, патроны и выход."
		if value == GameConfig.Mode.ESCAPE else "Один зал, зомби лезут волнами. Продержись как можно дольше.")


func _set_players(value: int) -> void:
	_players = value
	_refresh(_player_buttons, value)


func start_game() -> void:
	GameConfig.new_game(_mode, _players)
	get_tree().change_scene_to_file(GAME_SCENE)


func _refresh(buttons: Array, value: int) -> void:
	for b in buttons:
		var on: bool = b.get_meta("value") == value
		var fg := Color.BLACK if on else Color.WHITE
		var bgc := Color.WHITE if on else Color.BLACK
		for state in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = bgc
			sb.border_color = BLOOD if state == "focus" else Color.WHITE
			sb.set_border_width_all(3 if state == "focus" else 2)
			sb.content_margin_top = 10
			sb.content_margin_bottom = 10
			b.add_theme_stylebox_override(state, sb)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, fg)


func _button(text: String, width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 0)
	b.add_theme_font_size_override("font_size", 26)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("value", -1)
	_refresh([b], -2)
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
