extends RefCounted
## Характеристики оружия. Нож есть всегда и не тратит патроны,
## остальное нужно найти на уровне вместе с патронами.
## knockback — на сколько м/с одно попадание (одна дробина) толкает живого зомби,
## impulse — толчок трупу или оторванной части. У дробовика восемь дробин, поэтому
## в упор он толкает сильнее всего.

const ORDER := ["knife", "pistol", "smg", "shotgun"]

const STATS := {
	"knife": {
		"name": "НОЖ", "melee": true, "damage": 45.0, "interval": 0.45, "range": 1.9,
		"mag": 0, "auto": false, "pellets": 1, "spread": 0.0, "reload": 0.0,
		"pickup_ammo": 0, "max_reserve": 0, "noise": 0.0,
		"knockback": 1.4, "impulse": 3.0,
	},
	"pistol": {
		"name": "ПИСТОЛЕТ", "melee": false, "damage": 34.0, "interval": 0.22, "range": 60.0,
		"mag": 12, "auto": false, "pellets": 1, "spread": 0.004, "reload": 1.1,
		"pickup_ammo": 24, "max_reserve": 96, "noise": 18.0,
		"knockback": 1.8, "impulse": 4.0,
	},
	"smg": {
		"name": "АВТОМАТ", "melee": false, "damage": 22.0, "interval": 0.09, "range": 60.0,
		"mag": 30, "auto": true, "pellets": 1, "spread": 0.025, "reload": 1.6,
		"pickup_ammo": 60, "max_reserve": 240, "noise": 22.0,
		"knockback": 0.9, "impulse": 2.5,
	},
	"shotgun": {
		"name": "ДРОБОВИК", "melee": false, "damage": 16.0, "interval": 0.8, "range": 30.0,
		"mag": 6, "auto": false, "pellets": 8, "spread": 0.075, "reload": 1.8,
		"pickup_ammo": 12, "max_reserve": 48, "noise": 26.0,
		"knockback": 1.1, "impulse": 3.5,
	},
}


static func stat(weapon: String, key: String):
	return STATS[weapon][key]


static func display_name(weapon: String) -> String:
	return STATS[weapon]["name"]
