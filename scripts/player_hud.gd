extends Control
## Интерфейс одной половины экрана: прицел, здоровье, патроны, сообщения.
## Белый текст; красный только для попаданий и урона.

const BLOOD := Color(0.9, 0.0, 0.03)

var _crosshair: Label
var _status: Label
var _message: Label
var _damage: ColorRect
var _hit_timer := 0.0
var _message_timer := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_damage = ColorRect.new()
	_damage.color = Color(BLOOD, 0.0)
	_damage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage)

	_crosshair = _label(32)
	_crosshair.text = "+"
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_right = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.anchor_bottom = 0.5
	_crosshair.offset_left = -30
	_crosshair.offset_right = 30
	_crosshair.offset_top = -30
	_crosshair.offset_bottom = 30
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_status = _label(22)
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = 24
	_status.offset_top = -70
	_status.offset_right = 500
	_status.offset_bottom = -20

	_message = _label(40)
	_message.anchor_right = 1.0
	_message.offset_top = 60
	_message.offset_bottom = 120
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func set_status(hp: float, ammo: int, mag: int, reloading: bool, kills: int, downed: bool, revive: float) -> void:
	var ammo_text := "перезарядка" if reloading else "%d / %d" % [ammo, mag]
	_status.text = "ЗДОРОВЬЕ %d     ПАТРОНЫ %s     УБИТО %d" % [int(hp), ammo_text, kills]
	if downed:
		_message_timer = 0.2
		if revive > 0.0:
			_message.text = "ПОДНИМАЮТ… %d%%" % int(revive * 100.0)
		else:
			_message.text = "ТЫ ПАЛ — ЖДИ НАПАРНИКА"


func flash_hit(headshot: bool) -> void:
	_crosshair.text = "✕" if headshot else "+"
	_crosshair.add_theme_color_override("font_color", BLOOD)
	_hit_timer = 0.15


func flash_damage() -> void:
	_damage.color.a = 0.45


func show_message(text: String, seconds := 2.0) -> void:
	_message.text = text
	_message_timer = seconds


func _process(delta: float) -> void:
	_damage.color.a = maxf(0.0, _damage.color.a - delta * 1.5)
	if _hit_timer > 0.0:
		_hit_timer -= delta
		if _hit_timer <= 0.0:
			_crosshair.text = "+"
			_crosshair.add_theme_color_override("font_color", Color.WHITE)
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message.text = ""


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
