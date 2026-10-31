extends RefCounted
## Настройки партии, которые живут между сценами: режим, число игроков, номер этажа
## и снаряжение игроков на начало этажа (чтобы после гибели всё вернулось как было).

enum Mode { ESCAPE, WAVES }

static var mode: Mode = Mode.ESCAPE
static var players := 2
static var floor_number := 1
## Снаряжение на начало этажа: по словарю на игрока, пустой массив — новая партия.
static var loadouts: Array = []


static func new_game(new_mode: Mode, player_count: int) -> void:
	mode = new_mode
	players = clampi(player_count, 1, 4)
	floor_number = 1
	loadouts = []
