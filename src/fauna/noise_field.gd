class_name NoiseField
extends RefCounted
## Шум (GDD §5.4): уровень машины от 0 до 1 пропорционален скорости (1,0 от noise_full_frac·Vmax);
## пассивная фауна в радиусе уровень × noise_range слышит машину и переходит в атаку. События —
## посадка основного и аварийного челнока — шумят в своём радиусе заданное время и стягивают фауну.

var noise_range := 12.0
var full_frac := 0.8

var vehicle_pos := Vector2.ZERO
var vehicle_level := 0.0
var sources: Array[Dictionary] = []      ## {pos: Vector2, radius, left}


func update_vehicle(pos: Vector2, speed: float, max_speed: float) -> void:
	vehicle_pos = pos
	vehicle_level = clampf(speed / (full_frac * max_speed), 0.0, 1.0)


func add(pos: Vector2, radius: float, seconds: float) -> void:
	sources.append({"pos": pos, "radius": radius, "left": seconds})


func tick(dt: float) -> void:
	for s in sources:
		s["left"] -= dt
	sources = sources.filter(func(s: Dictionary) -> bool: return s["left"] > 0.0)


## Слышна ли машина из точки p.
func hears_vehicle(p: Vector2) -> bool:
	return p.distance_to(vehicle_pos) <= vehicle_level * noise_range


## Шумное событие, которое слышно из точки p (ближайшее), или null.
func heard_source(p: Vector2) -> Variant:
	var best: Variant = null
	var best_d := INF
	for s in sources:
		var d: float = p.distance_to(s["pos"])
		if d <= s["radius"] and d < best_d:
			best_d = d
			best = s["pos"]
	return best
