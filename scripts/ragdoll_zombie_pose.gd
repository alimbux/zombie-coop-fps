extends SkeletonModifier3D
## Для тестовой модели «human»: из обычной походки человека делает зомби.
## Поверх анимации сгибает спину, роняет голову набок и тянет руки вперёд.
## Стоит перед рэгдоллом, так что физика его перекрывает.

const HUNCH := 0.5
const ARM_PULL := 0.8

var _tilt := randf_range(-0.25, 0.25)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_rotate(sk, "spine_02", Basis(Vector3.RIGHT, HUNCH))
	_rotate(sk, "neck_01", Basis(Vector3.FORWARD, _tilt) * Basis(Vector3.RIGHT, -0.2))
	# Модель смотрит в +Z: руки тянутся вперёд и чуть вниз, слегка врозь.
	for side in ["l", "r"]:
		var out := 0.18 if side == "l" else -0.18
		_aim(sk, "upperarm_" + side, Vector3(out, -0.2, 1.0).normalized(), ARM_PULL)
		_aim(sk, "lowerarm_" + side, Vector3(out * 0.5, -0.3, 1.0).normalized(), ARM_PULL)


func _rotate(sk: Skeleton3D, bone: String, rot: Basis) -> void:
	var i := sk.find_bone(bone)
	if i < 0:
		return
	var g := sk.get_bone_global_pose(i)
	g.basis = rot * g.basis
	sk.set_bone_global_pose(i, g)


## Поворачивает кость так, чтобы её ось (+Y) смотрела в сторону dir.
func _aim(sk: Skeleton3D, bone: String, dir: Vector3, amount: float) -> void:
	var i := sk.find_bone(bone)
	if i < 0:
		return
	var g := sk.get_bone_global_pose(i)
	var y := g.basis.y.normalized()
	var target := y.slerp(dir, amount).normalized()
	if y.cross(target).length() < 0.0001:
		return
	g.basis = Basis(Quaternion(y, target)) * g.basis
	sk.set_bone_global_pose(i, g)
