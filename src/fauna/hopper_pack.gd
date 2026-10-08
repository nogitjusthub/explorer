class_name HopperPack
extends Creature
## Стая скакунов (GDD §5.4): 4–6 быстрых зверьков, ходят только по склонам (ни стенки вверх, ни обрыва
## вниз), в воду не заходят. Пока не слышат машину — бродят у дома. Услышали (шум, гнездо, посадка
## челнока) — визг, и стая гонится (hopper_speed): окружает машину, кусает (не больше трёх разом, у
## каждого перезарядка) и толкает. Танк отбрасывает их массой. Через hopper_chase_s или hopper_chase_dist
## отстают и уходят. Путь — общее поле путей вида HOPPER от FaunaDirector.

enum State { IDLE, ALERT, CHASE, RETREAT }

const BODY_COLOR := Color(0.86, 0.95, 0.72)
const LEG_COLOR := Color(0.55, 0.62, 0.45)
const EYE_COLOR := Color(1.0, 0.25, 0.2)
const ALERT_S := 0.6
const CONTACT := 0.7
const SLOT_R := 0.8
const RETREAT_S := 6.0
const LUNGE_S := 0.22

var state := State.IDLE
var home := Vector2.ZERO
var source: Variant = null               ## шумное событие, к которому идёт стая (посадка челнока)

var _members: Array[Dictionary] = []     ## {node, pos, goal, hop, cd, stun, slot}
var _timer := 0.0
var _chase_from := Vector2.ZERO
var _chase_t := 0.0
var _time := 0.0


func _init() -> void:
	name = "HopperPack"


func setup(at: Vector2, count: int) -> void:
	home = at
	pos = at
	for i in count:
		var p := at + Vector2.from_angle(TAU * i / count) * rng.randf_range(0.4, 1.4)
		var t := Grid.tile_of_world(p.x, p.y)
		if not query.is_loaded(t.x, t.y) or query.water_tier(t.x, t.y) != TerrainQuery.NO_WATER:
			p = at
		var node := _build_model()
		add_child(node)
		_members.append({"node": node, "pos": p, "goal": p, "hop": rng.randf() * TAU, "cd": 0.0, "stun": 0.0,
				"slot": TAU * i / count, "lunge": 0.0})
	_place_all(0.0)
	for m in _members:
		(m["node"] as Node3D).reset_physics_interpolation()


## Разбудить (гнездо, шумное событие): визг и погоня.
func wake(toward: Variant = null) -> void:
	source = toward
	if state == State.IDLE:
		_alert()


func step(dt: float) -> void:
	_time += dt
	for m in _members:
		m["cd"] = maxf(m["cd"] - dt, 0.0)
		m["stun"] = maxf(m["stun"] - dt, 0.0)
		m["lunge"] = maxf(m["lunge"] - dt, 0.0)
	match state:
		State.IDLE:
			_wander(dt)
			if noise.hears_vehicle(pos):
				_alert()
			else:
				var heard: Variant = noise.heard_source(pos)
				if heard != null:
					wake(heard)
		State.ALERT:
			_timer -= dt
			if _timer <= 0.0:
				state = State.CHASE
				aggressive = true
				_chase_from = pos
				_chase_t = 0.0
		State.CHASE:
			_chase(dt)
		State.RETREAT:
			_timer -= dt
			_retreat(dt)
			if _timer <= 0.0:
				finished = true
	_place_all(dt)


func _alert() -> void:
	state = State.ALERT
	_timer = ALERT_S
	EventBus.fauna_alerted.emit(&"hopper", Vector3(pos.x, ground_y(pos), pos.y))


func _wander(dt: float) -> void:
	for m in _members:
		var p: Vector2 = m["pos"]
		if p.distance_to(m["goal"]) < 0.2:
			m["goal"] = home + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.5, 3.5)
		_move_member(m, m["goal"], rules.hopper_wander_speed, dt)


func _chase(dt: float) -> void:
	_chase_t += dt
	var vp := vehicle.state.pos
	var hunting := noise.hears_vehicle(pos) or pos.distance_to(vp) < 12.0
	var field: FlowField = director.call(&"field", FlowField.Mode.HOPPER)
	var biters := 0
	for m in _members:
		if m["cd"] > rules.hopper_bite_cd_s - 0.4:
			biters += 1
	for m in _members:
		if m["stun"] > 0.0:
			continue
		var p: Vector2 = m["pos"]
		var goal: Vector2
		if not hunting and source != null:
			goal = (source as Vector2) + Vector2.from_angle(m["slot"]) * 2.0
		elif p.distance_to(vp) > 2.5:
			var t := Grid.tile_of_world(p.x, p.y)
			var next := field.next_tile(query, t) if field != null else t
			goal = Vector2(next.x + 0.5, next.y + 0.5) if next != t else vp
		else:
			goal = vp + Vector2.from_angle(m["slot"] + _time * 0.8) * SLOT_R
		_move_member(m, goal, rules.hopper_speed, dt)
		_contact(m, vp, biters)
	if _chase_t > rules.hopper_chase_s or pos.distance_to(_chase_from) > rules.hopper_chase_dist:
		state = State.RETREAT
		aggressive = false
		_timer = RETREAT_S


## Укус и толчок; танк отбрасывает зверька массой.
func _contact(m: Dictionary, vp: Vector2, biters: int) -> void:
	var p: Vector2 = m["pos"]
	var d := p.distance_to(vp)
	if d > CONTACT or vehicle.state.falling or vehicle.state.drowning:
		return
	var away := (p - vp).normalized() if d > 0.01 else Vector2.RIGHT
	if vehicle.cls.mass >= 2.0 and vehicle.state.vel.length() > 1.5:
		m["pos"] = Creature.move_on_grid(query, FlowField.Mode.HOPPER, p, p + away * 1.6)
		m["stun"] = 1.0
		return
	if m["cd"] <= 0.0 and biters < rules.hopper_max_biters:
		m["cd"] = rules.hopper_bite_cd_s
		m["lunge"] = LUNGE_S
		(m["node"] as Node3D).rotation.y = atan2(away.x, away.y)    # мордой к машине
		damaged.emit(rules.hopper_bite, &"hopper")
		vehicle.state.push_vel += -away * 1.2 / vehicle.cls.mass


func _retreat(dt: float) -> void:
	var away := (pos - vehicle.state.pos).normalized()
	for m in _members:
		_move_member(m, (m["pos"] as Vector2) + away * 3.0, rules.hopper_wander_speed * 2.5, dt)


func _move_member(m: Dictionary, goal: Vector2, speed: float, dt: float) -> void:
	var p: Vector2 = m["pos"]
	var delta := goal - p
	var len := delta.length()
	if len < 0.02:
		return
	var np := p + delta / len * minf(len, speed * dt)
	m["pos"] = Creature.move_on_grid(query, FlowField.Mode.HOPPER, p, np)
	m["hop"] += dt * (16.0 if speed > 3.0 else 9.0)
	(m["node"] as Node3D).rotation.y = atan2(-delta.x, -delta.y)


func _place_all(_dt: float) -> void:
	var sum := Vector2.ZERO
	for m in _members:
		var p: Vector2 = m["pos"]
		sum += p
		var hop := absf(sin(m["hop"])) * (0.0 if state == State.IDLE and p.distance_to(m["goal"]) < 0.2 else 0.22)
		var node: Node3D = m["node"]
		node.position = Vector3(p.x, ground_y(p) + hop, p.y)
		# Выпад: голова рывком вперёд и назад (модель смотрит по −Z).
		var lunge: float = m["lunge"]
		var head: Node3D = node.get_child(1)
		head.position.z = -0.15 - sin((1.0 - lunge / LUNGE_S) * PI) * 0.12 * float(lunge > 0.0)
	if not _members.is_empty():
		pos = sum / _members.size()


## Скакун: светлое тельце, голова с красными глазами, мощные задние лапы.
func _build_model() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.13
	s.height = 0.22
	s.radial_segments = 8
	s.rings = 4
	body.mesh = s
	body.material_override = Creature.material(BODY_COLOR)
	body.position = Vector3(0, 0.16, 0)
	body.scale = Vector3(1.0, 0.85, 1.3)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.08
	hs.height = 0.15
	hs.radial_segments = 8
	hs.rings = 4
	head.mesh = hs
	head.material_override = body.material_override
	head.position = Vector3(0, 0.24, -0.15)
	root.add_child(head)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = EYE_COLOR
	var leg_mat := Creature.material(LEG_COLOR)
	for x in [-0.04, 0.04]:
		var eye := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(0.03, 0.03, 0.02)
		eye.mesh = eb
		eye.material_override = eye_mat
		eye.position = Vector3(x, 0.27, -0.215)
		root.add_child(eye)
	for x in [-0.1, 0.1]:
		var leg := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.05, 0.12, 0.15)
		leg.mesh = lb
		leg.material_override = leg_mat
		leg.position = Vector3(x, 0.07, 0.08)
		root.add_child(leg)
	return root
