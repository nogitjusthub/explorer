class_name VehicleInput
extends RefCounted
## Ввод относительно экрана (GDD §8): W/A/S/D или левый стик → направление в мире (x, z),
## длина вектора — газ. «Вверх» — от камеры в глубину экрана.


static func world_direction(camera: Camera3D) -> Vector2:
	var v := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if v == Vector2.ZERO or camera == null:
		return Vector2.ZERO
	var b := camera.global_transform.basis
	var right := Vector2(b.x.x, b.x.z).normalized()
	var forward := Vector2(-b.z.x, -b.z.z).normalized()
	return right * v.x - forward * v.y
