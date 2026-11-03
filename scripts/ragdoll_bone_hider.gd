extends SkeletonModifier3D
## Для тестовой модели с рэгдоллом: сжимает оторванные кости в ноль после анимации
## и физики, так что исчезают и все дочерние (кисть, ступня).

var hidden := {}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for bone in hidden:
		var i := sk.find_bone(bone)
		if i >= 0:
			sk.set_bone_pose_scale(i, Vector3.ONE * 0.001)
