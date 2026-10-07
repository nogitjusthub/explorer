class_name VehicleState
extends RefCounted
## Состояние машины для кинематики. Плоскость движения — (x, z) мира, хранится как Vector2.

var pos := Vector2.ZERO          ## x, z мира
var y := 0.0                     ## мировая высота днища
var vel := Vector2.ZERO          ## тайл/с в плоскости x-z
var heading := 0.0               ## радианы; направление движения = Vector2.from_angle(heading)
var throttle := 0.0              ## 0..1 — доля газа в этом кадре (для топлива и звука)
var tile := Vector2i.ZERO        ## текущий тайл
var uphill_tiles := 0            ## тайлов подъёма подряд (предел скорости на подъёме)

var falling := false
var fall_vy := 0.0
var fall_from_tier := 0.0
var fall_tile := Vector2i.ZERO


func forward() -> Vector2:
	return Vector2.from_angle(heading)
