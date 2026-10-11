class_name HopperPack
extends Creature
## Стая скакунов (GDD §5.4): 3–4 зверька держатся тесной группой в одном тайле и ходят только по
## склонам (ни стенки вверх, ни обрыва вниз), в воду не заходят. Пока не слышат машину — стая бродит у
## дома, зверьки переминаются и подпрыгивают. Услышали (шум, гнездо, посадка челнока) — визг, и стая
## гонится (hopper_speed — быстрее танка, медленнее ровера) по общему полю путей вида HOPPER. Догнали —
## встают рядом с машиной, и передний бросается вперёд и кусает (раз в hopper_bite_cd_s); машину
## укусы не двигают — только раскачивают корпус. Танк на ходу расшвыривает стаю. Не подобраться к машине
## fauna_give_up_s (или погоня дольше hopper_chase_s / дальше hopper_chase_dist) — стая уходит и пропадает.

enum State { IDLE, ALERT, CHASE, RETREAT }

const BODY_COLOR := Color(0.86, 0.95, 0.72)
const LEG_COLOR := Color(0.55, 0.62, 0.45)
const EYE_COLOR := Color(1.0, 0.25, 0.2)
const ALERT_S := 0.6
const SEE_R := 8.0                       ## тайлов: в погоне машину ближе этого стая видит и без шума
const STANDOFF := 0.8                    ## стая встаёт на таком расстоянии от центра машины
const REACH := 1.05                      ## отсюда передний достаёт машину броском
const RETREAT_S := 6.0
const LUNGE_S := 0.3
const LUNGE_LEN := 0.42
const STUN_S := 1.0
## Места в строю (x, z) относительно центра стаи; перед — по −z, первый — передний (он и кусает).
const FORMATION: Array[Vector2] = [Vector2(0, -0.2), Vector2(-0.17, 0.07), Vector2(0.17, 0.07), Vector2(0, 0.28)]

var state := State.IDLE
var home := Vector2.ZERO
var source: Variant = null               ## шумное событие, к которому идёт стая (посадка челнока)

var _members: Array[Dictionary] = []     ## {node, phase, idle, hop, yaw}
var _heading := Vector2(0, -1)
var _goal := Vector2.ZERO
var _moving := false
var _timer := 0.0
var _chase_from := Vector2.ZERO
var _chase_t := 0.0
var _cd := 0.0
var _lunge := 0.0
var _stun := 0.0


func _init() -> void:
	name = "HopperPack"


func setup(at: Vector2, count: int) -> void:
	home = at
	pos = at
	_goal = at
	_heading = Vector2.from_angle(rng.randf() * TAU)
	for i in clampi(count, 1, FORMATION.size()):
		var node := _build_model()
		add_child(node)
		_members.append({"node": node, "phase": rng.randf() * TAU, "idle": rng.randf_range(0.2, 1.5),
				"hop": 0.0, "yaw": 0.0})
	_place_all(0.0)
	for m in _members:
		(m["node"] as Node3D).reset_physics_interpolation()


## Бегство (испуг): стая уходит прочь и исчезает.
func flee() -> void:
	state = State.RETREAT
	aggressive = false
	_timer = RETREAT_S


## Разбудить (гнездо, шумное событие): визг и погоня.
func wake(toward: Variant = null) -> void:
	source = toward
	if state == State.IDLE:
		_alert()


func step(dt: float) -> void:
	_cd = maxf(_cd - dt, 0.0)
	_lunge = maxf(_lunge - dt, 0.0)
	_stun = maxf(_stun - dt, 0.0)
	_moving = false
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
			_face(vehicle.state.pos - pos)
			if _timer <= 0.0:
				state = State.CHASE
				aggressive = true
				_chase_from = pos
				_chase_t = 0.0
				reset_interest()
		State.CHASE:
			_chase(dt)
		State.RETREAT:
			_timer -= dt
			var away := (pos - vehicle.state.pos).normalized()
			_move_pack(pos + away * 3.0, rules.hopper_wander_speed * 2.5, dt)
			if _timer <= 0.0:
				finished = true
	_place_all(dt)


func _alert() -> void:
	state = State.ALERT
	_timer = ALERT_S
	EventBus.fauna_alerted.emit(&"hopper", Vector3(pos.x, ground_y(pos), pos.y))


## Стая бродит у дома: переходит на новое место и подолгу стоит.
func _wander(dt: float) -> void:
	if pos.distance_to(_goal) < 0.1:
		_timer -= dt
		if _timer <= 0.0:
			_timer = rng.randf_range(1.5, 4.0)
			_goal = home + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.5, 3.0)
		return
	_move_pack(_goal, rules.hopper_wander_speed, dt)


func _chase(dt: float) -> void:
	_chase_t += dt
	var vp := vehicle.state.pos
	var d := pos.distance_to(vp)
	var hunting := noise.hears_vehicle(pos) or d < SEE_R
	if _stun <= 0.0:
		var goal: Vector2
		if not hunting and source != null:
			goal = source as Vector2
		elif d > 2.0:
			var field: FlowField = director.call(&"field", FlowField.Mode.HOPPER)
			var t := Grid.tile_of_world(pos.x, pos.y)
			var next := field.next_tile(query, t) if field != null else t
			goal = Vector2(next.x + 0.5, next.y + 0.5) if next != t else vp
		else:
			goal = vp + (pos - vp).normalized() * STANDOFF
		_move_pack(goal, rules.hopper_speed, dt)
		if d < 2.0:
			_face(vp - pos)                      # вблизи — передним к машине
	_tank_bump(vp)
	var reach := d <= REACH and not vehicle.state.falling and not vehicle.state.drowning
	if reach and _cd <= 0.0 and _stun <= 0.0:
		_bite(vp)
	if lost_interest(dt, d, reach) or _chase_t > rules.hopper_chase_s \
			or pos.distance_to(_chase_from) > rules.hopper_chase_dist:
		flee()


## Укус: передний бросается вперёд; машину не двигает — только раскачивает корпус.
func _bite(vp: Vector2) -> void:
	_cd = rules.hopper_bite_cd_s
	_lunge = LUNGE_S
	_face(vp - pos)
	damaged.emit(rules.hopper_bite, &"hopper")
	vehicle.rock(Vehicle.ROCK_BITE, (vp - pos).normalized())


## Танк на ходу расшвыривает стаю массой.
func _tank_bump(vp: Vector2) -> void:
	if vehicle.cls.mass < 2.0 or vehicle.state.vel.length() < 1.5 or pos.distance_to(vp) > 0.7:
		return
	var away := (pos - vp).normalized() if pos.distance_to(vp) > 0.01 else Vector2.RIGHT
	pos = Creature.move_on_grid(query, FlowField.Mode.HOPPER, pos, pos + away * 1.6)
	_stun = STUN_S


func _move_pack(goal: Vector2, speed: float, dt: float) -> void:
	var delta := goal - pos
	if delta.length() < 0.03:
		return
	var np := Creature.move_on_grid(query, FlowField.Mode.HOPPER, pos, pos + delta.limit_length(speed * dt))
	_moving = np != pos
	pos = np
	_face(delta)


func _face(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		_heading = dir.normalized()


## Строй вокруг центра стаи, развёрнутый по курсу. На ходу все скачут; стоя — переминаются и изредка
## подпрыгивают; передний при укусе бросается вперёд.
func _place_all(dt: float) -> void:
	var yaw := atan2(-_heading.x, -_heading.y)
	for i in _members.size():
		var m := _members[i]
		var off: Vector2 = FORMATION[i]
		var local := Vector3(off.x, 0, off.y).rotated(Vector3.UP, yaw)
		var p := pos + Vector2(local.x, local.z)
		var lift := 0.0
		if _moving:
			m["phase"] += dt * 14.0
			lift = absf(sin(m["phase"])) * 0.12
			m["yaw"] = 0.0
		else:
			m["idle"] -= dt
			if m["idle"] <= 0.0:
				m["idle"] = rng.randf_range(0.4, 1.6)
				m["hop"] = 0.25
				m["yaw"] = rng.randf_range(-0.5, 0.5)
			m["hop"] = maxf(m["hop"] - dt, 0.0)
			lift = sin(m["hop"] / 0.25 * PI) * 0.05
		if i == 0 and _lunge > 0.0:
			var k := sin((1.0 - _lunge / LUNGE_S) * PI)
			p += _heading * k * LUNGE_LEN
			lift += k * 0.08
		var node: Node3D = m["node"]
		node.position = Vector3(p.x, ground_y(p) + lift, p.y)
		node.rotation.y = yaw + m["yaw"]


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
