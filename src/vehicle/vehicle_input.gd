class_name VehicleInput
extends RefCounted
## Ввод (GDD §8, меню настроек). «Относительно мира»: W/A/S/D или левый стик → направление в мире (x, z),
## длина вектора — газ, «вверх» — от камеры в глубину экрана. «Относительно машины»: W / S (стик вверх / вниз) —
## вперёд / назад, A / D (стик влево / вправо) — поворот.


static func world_direction(camera: Camera3D) -> Vector2:
	var v := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if v == Vector2.ZERO or camera == null:
		return Vector2.ZERO
	var b := camera.global_transform.basis
	var right := Vector2(b.x.x, b.x.z).normalized()
	var forward := Vector2(-b.z.x, -b.z.z).normalized()
	return right * v.x - forward * v.y


## «Относительно машины»: x — поворот (−1 влево … 1 вправо), y — ход (1 вперёд … −1 назад).
static func drive_turn() -> Vector2:
	return Vector2(Input.get_axis(&"move_left", &"move_right"), Input.get_axis(&"move_down", &"move_up"))
