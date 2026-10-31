extends Area3D
## Предмет на уровне: оружие, патроны или аптечка. Подбирается, если игрок подошёл
## и предмет ему пригодится (полный запас патронов или полное здоровье — остаётся лежать).

const Sfx := preload("res://scripts/sfx.gd")
const Weapons := preload("res://scripts/weapons.gd")

const MEDKIT_HEAL := 40.0

## "weapon", "ammo" или "medkit".
var kind := "ammo"
var weapon := "pistol"
var _model: Node3D
var _recheck := 0.0


func _ready() -> void:
	add_to_group("pickups")
	collision_layer = 0
	collision_mask = 8
	monitoring = true
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	col.shape = sphere
	col.position.y = 0.6
	add_child(col)
	_build_model()
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_model.rotation.y += delta * 1.5
	_model.position.y = 0.55 + sin(Time.get_ticks_msec() * 0.003) * 0.05
	# Если игрок стоял на предмете с полным запасом, а потом потратил патроны —
	# подберёт, не сходя с места.
	_recheck -= delta
	if _recheck <= 0.0:
		_recheck = 0.5
		for body in get_overlapping_bodies():
			if body.is_in_group("players") and try_give(body):
				return


func label_text() -> String:
	match kind:
		"weapon":
			return Weapons.display_name(weapon)
		"ammo":
			return "ПАТРОНЫ: " + Weapons.display_name(weapon)
	return "АПТЕЧКА"


## Пытается отдать предмет игроку. true — предмет подобран.
func try_give(player) -> bool:
	if player.downed:
		return false
	var taken := false
	match kind:
		"weapon":
			taken = player.give_weapon(weapon, Weapons.stat(weapon, "pickup_ammo"))
		"ammo":
			taken = player.give_ammo(weapon, Weapons.stat(weapon, "pickup_ammo"))
		"medkit":
			taken = player.heal(MEDKIT_HEAL)
	if taken:
		Sfx.play_flat(player, "pickup", -4.0)
		if player.hud:
			player.hud.show_message("+ " + label_text(), 1.5)
		queue_free()
	return taken


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("players"):
		try_give(body)


func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	var light := _mat(Color(0.95, 0.95, 0.95), 0.6)
	var dark := _mat(Color(0.12, 0.12, 0.12), 0.1)
	match kind:
		"weapon":
			var length: float = {"pistol": 0.35, "smg": 0.6, "shotgun": 0.9}.get(weapon, 0.4)
			_block(Vector3(0.1, 0.12, length), Vector3.ZERO, light)
			_block(Vector3(0.08, 0.2, 0.1), Vector3(0, -0.14, length * 0.25), light)
		"ammo":
			_block(Vector3(0.4, 0.25, 0.28), Vector3.ZERO, light)
			_block(Vector3(0.42, 0.06, 0.3), Vector3.ZERO, dark)
		"medkit":
			_block(Vector3(0.45, 0.3, 0.3), Vector3.ZERO, light)
			_block(Vector3(0.3, 0.32, 0.08), Vector3(0, 0, 0), dark)
			_block(Vector3(0.08, 0.32, 0.3), Vector3(0, 0, 0), dark)
	var label := Label3D.new()
	label.text = label_text()
	label.font_size = 40
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 1.2
	add_child(label)
	# Слабый свет, чтобы предмет было видно в тёмной комнате.
	var glow := OmniLight3D.new()
	glow.omni_range = 2.0
	glow.light_energy = 0.6
	glow.position.y = 0.9
	add_child(glow)


func _block(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	_model.add_child(mesh)


func _mat(color: Color, emission: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color * emission
	return m
