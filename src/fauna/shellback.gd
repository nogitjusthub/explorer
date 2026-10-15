class_name Shellback
extends Creature
## Панцирник (GDD §5.4): размером с машину — купол-панцирь с полосами, рог, шесть ног. Ходит, как
## скакуны, только склонами: ни на стенку, ни с обрыва, в воду не заходит (shellback_speed — быстрее
## танка, медленнее ровера). Территориальный: бродит у своего места; услышав машину рядом с ним
## (ближе shellback_territory_r), подбирается по полю путей; когда до неё прямой путь короче рывка —
## роет землю shellback_dig_s (телеграф) и бросается по прямой на shellback_charge_dist со скоростью
## shellback_charge_speed (медленнее ровера). Сдвинуть машину может только таран: урон, отброс и
## раскачка корпуса — только на одном с ней уровне (Creature.same_level); в стенку — оглушён. Машина за
## уступом — подбирается в обход по полю путей. Отстаёт (shellback_calm_s не слышит машину и уходит к себе),
## если: протаранил её — прогнал; она ушла с его территории; не подобраться fauna_give_up_s; погоня
## дольше shellback_chase_s. Спасение — уйти с линии атаки или уехать от его места.
## Машина на скорости валки деревьев таранит его (RamBody): удар — мигает, отлетает на ram_knockback по ходу
## машины и оглушён, после — снова в погоне; ram_hits_shellback ударов — гибель.

enum State { IDLE, APPROACH, DIG, CHARGE, STUN }

const SHELL_COLOR := Color(0.27, 0.33, 0.3)
const STRIPE_COLOR := Color(0.5, 0.6, 0.45)
const LEG_COLOR := Color(0.16, 0.18, 0.17)
const SIZE := 0.68                       ## модель ужата по плоскости — размером с машину
const CONTACT := 0.75
const STUN_S := 1.5
const WANDER_SPEED := 0.8
const WANDER_R := 3.0                    ## бродит в стольких тайлах от своего места
const RAM_R := 0.4                       ## радиус тела под тараном машины
const KNOCK_S := 0.25                    ## удар тараном: отлетает за столько
const PUFF_COLOR := Color(0.5, 0.6, 0.45)

var state := State.IDLE

var _timer := 0.0
var _calm := 0.0
var _charge_dir := Vector2.ZERO
var _charge_left := 0.0
var _hit := false
var _goal := Vector2.ZERO
var _home := Vector2.ZERO                ## его место — точка появления
var _chase := 0.0                        ## сколько секунд гонится
var _rammed := false                     ## в этой погоне протаранил машину
var _model: Node3D
var _dust: CPUParticles3D
var _knock := Vector2.ZERO               ## удар тараном: скорость отлёта
var _knock_t := 0.0


func _init() -> void:
	name = "Shellback"


func setup(at: Vector2) -> void:
	pos = at
	_goal = at
	_home = at
	_model = _build_model()
	add_child(_model)
	add_body(rules.ram_hits_shellback, RAM_R, _model, PUFF_COLOR)
	_place(0.0)
	_model.reset_physics_interpolation()


func step(dt: float) -> void:
	tick_bodies(dt)
	if dead:
		_slide(dt)
		_place(dt)
		return
	var vp := vehicle.state.pos
	var d := pos.distance_to(vp)
	match state:
		State.IDLE:
			_calm = maxf(_calm - dt, 0.0)
			if pos.distance_to(_goal) < 0.3:
				_goal = _home + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * WANDER_R
			_walk_to(_goal, rules.shellback_speed * 0.5 if _calm > 0.0 else WANDER_SPEED, dt)
			if _calm <= 0.0 and _on_territory(vp) and noise.hears_vehicle(pos):
				state = State.APPROACH
				aggressive = true
				_chase = 0.0
				_rammed = false
				reset_interest()
				_alert(&"shellback")
		State.APPROACH:
			if d <= rules.shellback_charge_dist and _line_clear(pos, vp):
				lost_interest(dt, d, true)
				state = State.DIG
				_timer = rules.shellback_dig_s
				_charge_dir = (vp - pos).normalized()
				_dust.color = PixelFx.clod_color(query, pos.x, pos.y)
				_dust.emitting = true
				_alert(&"shellback_dig")
			else:
				var field: FlowField = director.call(&"field", FlowField.Mode.SHELLBACK)
				var t := Grid.tile_of_world(pos.x, pos.y)
				var next := field.next_tile(query, t) if field != null else t
				if d > CONTACT + 0.3:                           # вплотную не лезет — только таран
					_walk_to(Vector2(next.x + 0.5, next.y + 0.5) if next != t else vp, rules.shellback_speed, dt)
			if state == State.APPROACH and (lost_interest(dt, d) or d > 30.0):
				_give_up()
		State.DIG:
			_timer -= dt
			_model.rotation.z = sin(_timer * 40.0) * 0.08    # дрожит, роет
			_charge_dir = (vp - pos).normalized() if _timer > rules.shellback_dig_s * 0.5 else _charge_dir
			if _timer <= 0.0:
				state = State.CHARGE
				_charge_left = rules.shellback_charge_dist
				_hit = false
				_dust.emitting = false
				_model.rotation.z = 0.0
				_alert(&"shellback_charge")
		State.CHARGE:
			var step := rules.shellback_charge_speed * dt
			var np := pos + _charge_dir * step
			var moved := Creature.move_on_grid(query, FlowField.Mode.SHELLBACK, pos, np)
			_charge_left -= step
			if moved == pos:
				_stun()                                         # в стенку — оглушён
			else:
				pos = moved
				_face(_charge_dir)
			if not _hit and pos.distance_to(vp) < CONTACT and not vehicle.state.falling \
					and Creature.same_level(query, pos, vp):                # с уступа на машину под ним не таранит
				_hit = true
				damaged.emit(rules.shellback_damage, &"shellback")
				vehicle.state.push_vel += _charge_dir * 7.0 / vehicle.cls.mass
				vehicle.rock(Vehicle.ROCK_RAM, _charge_dir)
				# Удар останавливает рывок: отскок назад, оглушён — сквозь машину не проходит.
				pos = Creature.move_on_grid(query, FlowField.Mode.SHELLBACK, pos, pos - _charge_dir * 0.3)
				_rammed = true
				_stun()
				EventBus.camera_shake_requested.emit(0.7, 0.3)
			if _charge_left <= 0.0 and state == State.CHARGE:
				_stun()
		State.STUN:
			_timer -= dt
			_slide(dt)
			if _timer <= 0.0:
				state = State.APPROACH
	if aggressive:
		_chase += dt
		# Отстаёт, когда не роет и не бежит в рывок: протаранил, машина ушла с территории, устал.
		var busy := state == State.DIG or state == State.CHARGE or state == State.STUN
		if not busy and (_rammed or not _on_territory(vp) or _chase > rules.shellback_chase_s):
			_give_up()
	_fell_trees()
	_place(dt)


## Звук (AudioDirector): услышал машину — мычит, роет — ревёт, рывок — топот.
func _alert(kind: StringName) -> void:
	EventBus.fauna_alerted.emit(kind, Vector3(pos.x, ground_y(pos), pos.y))


## Машина на его территории.
func _on_territory(p: Vector2) -> bool:
	return p.distance_to(_home) <= rules.shellback_territory_r


## Испуг (удар капсулы десанта) — отстаёт, как сдавшийся.
func calm_down() -> void:
	_give_up()


## Отстал: shellback_calm_s не слышит машину и уходит к своему месту. Сорванные рытьё и рывок (испуг —
## calm_down) не оставляют ни пыли, ни дрожи корпуса.
func _give_up() -> void:
	state = State.IDLE
	aggressive = false
	_calm = rules.shellback_calm_s
	_goal = _home
	_dust.emitting = false
	_model.rotation.z = 0.0


func _stun() -> void:
	state = State.STUN
	_timer = STUN_S


## Таран машиной: отлетает по ходу машины на ram_knockback (убитый — тоже: мигает уже не под машиной);
## удар без гибели — оглушён (рытьё и рывок сорваны) и зол — после оглушения гонит машину, как услышавший её.
func _on_rammed(_b: RamBody, dir: Vector2, killed: bool) -> void:
	_knock = dir * rules.ram_knockback / KNOCK_S
	_knock_t = KNOCK_S
	if killed:
		return
	_dust.emitting = false
	_model.rotation.z = 0.0
	_stun()
	if not aggressive:
		aggressive = true
		_chase = 0.0
		_rammed = false
		_calm = 0.0
		reset_interest()


## Убит тараном: рытьё стихло, отлетает, мигает и пропадает облачком.
func _on_died() -> void:
	_dust.emitting = false
	_model.rotation.z = 0.0


## Отлёт от удара тараном — KNOCK_S, по рёбрам вида (в стенку не уходит).
func _slide(dt: float) -> void:
	if _knock_t > 0.0:
		_knock_t -= dt
		pos = Creature.move_on_grid(query, FlowField.Mode.SHELLBACK, pos, pos + _knock * dt)


## Прямой путь до цели проходим (рывок не упрётся в стенку).
func _line_clear(a: Vector2, b: Vector2) -> bool:
	var steps := ceili(a.distance_to(b) / 0.4)
	var p := a
	for i in range(1, steps + 1):
		var np := a.lerp(b, float(i) / steps)
		if Creature.move_on_grid(query, FlowField.Mode.SHELLBACK, p, np) == p:
			return false
		p = np
	return true


func _walk_to(goal: Vector2, speed: float, dt: float) -> void:
	var delta := goal - pos
	if delta.length() < 0.02:
		return
	var np := pos + delta.limit_length(speed * dt)
	pos = Creature.move_on_grid(query, FlowField.Mode.SHELLBACK, pos, np)
	_face(delta)


func _face(dir: Vector2) -> void:
	_model.rotation.y = atan2(-dir.x, -dir.y)


## Деревья перед панцирником падают — он ломится сквозь лес, как танк.
func _fell_trees() -> void:
	var c := Grid.tile_of_world(pos.x, pos.y)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t := c + Vector2i(dx, dz)
			if query.has_standing_tree(t.x, t.y) and query.tree_position(t.x, t.y).distance_to(pos) < 0.8:
				query.fell_tree(t.x, t.y)


func _place(_dt: float) -> void:
	_model.position = Vector3(pos.x, ground_y(pos), pos.y)
	_dust.position = _model.position + Vector3(0, 0.1, 0)
	for b in bodies:
		b.pos = pos
		b.y = _model.position.y


## Панцирник: тёмный купол-панцирь с полосами, рог, шесть ног. По плоскости ужат до размера машины
## (SIZE), высота прежняя.
func _build_model() -> Node3D:
	var top := Node3D.new()
	var root := Node3D.new()
	root.scale = Vector3(SIZE, 1.0, SIZE)
	top.add_child(root)
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.42
	sm.is_hemisphere = true
	sm.radial_segments = 10
	sm.rings = 3
	shell.mesh = sm
	shell.material_override = Creature.skin(SHELL_COLOR, BodyMaterial.Pattern.SCUTES, Grid.ART_PX / SIZE)
	shell.position = Vector3(0, 0.12, 0)
	shell.scale = Vector3(1.0, 0.85, 1.25)
	root.add_child(shell)
	var stripe := Creature.material(STRIPE_COLOR)
	for z in [-0.18, 0.05, 0.28]:
		var band := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.62, 0.06, 0.06)
		band.mesh = b
		band.material_override = stripe
		band.position = Vector3(0, 0.38 - absf(z) * 0.5, z)
		root.add_child(band)
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.24, 0.16, 0.18)
	head.mesh = hb
	var hide := Creature.skin(LEG_COLOR, BodyMaterial.Pattern.HIDE, Grid.ART_PX / SIZE)   # модель ужата SIZE
	head.material_override = hide
	head.position = Vector3(0, 0.14, -0.55)
	root.add_child(head)
	var horn := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = 0.0
	hc.bottom_radius = 0.05
	hc.height = 0.22
	hc.radial_segments = 5
	hc.rings = 0
	horn.mesh = hc
	horn.material_override = Creature.material(Color(0.85, 0.82, 0.7))
	horn.position = Vector3(0, 0.22, -0.68)
	horn.rotation.x = -1.1
	root.add_child(horn)
	var leg := hide
	for x in [-0.4, 0.4]:
		for z in [-0.25, 0.0, 0.25]:
			var l := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.14, 0.06, 0.06)
			l.mesh = lb
			l.material_override = leg
			l.position = Vector3(x, 0.05, z)
			root.add_child(l)
	_dust = PixelFx.clods(20, 0.6)               # роет — комья (PixelFx, как у всех), цвет грунта
	_dust.spread = 60.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 2.4
	add_child(_dust)
	return top

