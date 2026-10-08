class_name Worm
extends Creature
## Песчаный червь (GDD §5.4) — как в «Дюне». Живёт под песком (материал SAND) и только там ходит.
## Слышит машину на песке — идёт к ней под землёй: песок над ним вспучивается валом (деформация рельефа,
## «обратная» борозде смерча, не выше яруса) и оседает обратно в RIDGE_KEEP тайлах позади; летит пыль,
## гудит. Деревья на пути валятся.
## Догнал — за worm_telegraph_s до броска песок вокруг машины трескается кольцом и дрожит. Бросок:
## огромный червь вырывается прямо под машиной с раскрытой пастью — три челюсти-лепестка, внутри
## кольцо зубов и глотка; челюсти захлопываются над машиной (урон worm_damage) и выплёвывают её на
## worm_toss тайла; червь вздымается над песком и уходит обратно, оставив яму. Сомкнутые челюсти —
## округлая морда. Спасение — уйти с песка: червь теряет след.

enum State { IDLE, HUNT, TELEGRAPH, STRIKE, COOLDOWN }

const SAND_COLOR := Color(0.55, 0.42, 0.56)      ## вал — в тон лилового песка, темнее
const BODY_COLOR := Color(0.7, 0.6, 0.52)
const RING_COLOR := Color(0.47, 0.39, 0.34)
const THROAT_COLOR := Color(0.16, 0.06, 0.07)
const TOOTH_COLOR := Color(0.95, 0.92, 0.82)
const CRACK_COLOR := Color(0.18, 0.1, 0.12)

const R := 1.05                          ## радиус тела и пасти — машина помещается в пасть
const STRIKE_S := 2.4
const RISE_S := 0.35                     ## вырывается с раскрытой пастью
const BITE_S := 0.55                     ## челюсти захлопнулись
const HOLD_S := 1.6                      ## держится над песком, потом уходит
const TOP_Y := 3.6                       ## насколько вздымается голова над песком
const COOLDOWN_S := 4.0
const LOSE_S := 4.0
const STRIKE_R := 1.6
const JAW_OPEN := -1.55                  ## лепесток откинут наружу почти плашмя
const SEGMENTS := 9
const RIDGE_EVERY_S := 0.25
const RIDGE_HALF_W := 0.7
const RIDGE_KEEP := 3.5                  ## дальше позади вал оседает

var state := State.IDLE

var _timer := 0.0
var _lost := 0.0
var _strike_at := Vector2.ZERO
var _ground := 0.0
var _bitten := false
var _time := 0.0
var _heading := Vector2.RIGHT
var _wake: CPUParticles3D
var _ridge_from := Vector2.ZERO
var _ridge_timer := 0.0
var _raised: Dictionary = {}             ## поднятые углы: Vector3i(tx, tz, угол) → исходный ярус
var _ring: Node3D
var _ring_mat: StandardMaterial3D
var _burst: CPUParticles3D
var _body: Node3D
var _jaws: Array[Node3D] = []


func _init() -> void:
	name = "Worm"


func setup(at: Vector2) -> void:
	pos = at
	_build()
	_ring.visible = false
	_body.visible = false


func on_sand(p: Vector2) -> bool:
	var t := Grid.tile_of_world(p.x, p.y)
	return query.is_loaded(t.x, t.y) and query.material(t.x, t.y) == ChunkData.Mat.SAND \
			and query.water_tier(t.x, t.y) == TerrainQuery.NO_WATER


func step(dt: float) -> void:
	_time += dt
	var vp := vehicle.state.pos
	match state:
		State.IDLE:
			if on_sand(vp) and noise.hears_vehicle(pos):
				start_hunt()
		State.HUNT:
			if not on_sand(vp):
				_lost += dt
				if _lost > LOSE_S:
					state = State.IDLE
					aggressive = false
			else:
				_lost = 0.0
				var delta := vp - pos
				if delta.length() > 0.01:
					_heading = delta.normalized()
				var np := pos + delta.limit_length(rules.worm_speed * dt)
				if on_sand(np):
					pos = np
				_ridge_timer -= dt
				if _ridge_timer <= 0.0:
					_ridge_timer = RIDGE_EVERY_S
					_raise_ridge()
			if pos.distance_to(vp) < 1.0 and on_sand(vp):
				state = State.TELEGRAPH
				_timer = rules.worm_telegraph_s
				_strike_at = vp
				_ground = ground_y(_strike_at)
				_ring.visible = true
				_ring.position = Vector3(_strike_at.x, _ground + 0.04, _strike_at.y)
		State.TELEGRAPH:
			_timer -= dt
			var k := 1.0 - _timer / rules.worm_telegraph_s
			_ring.scale = Vector3.ONE * lerpf(0.5, 1.0, k)
			_ring.rotation.y = sin(_time * 30.0) * 0.03 * k            # песок дрожит
			_ring_mat.albedo_color.a = 0.3 + 0.6 * k
			if fmod(_time, 0.2) < dt:
				EventBus.camera_shake_requested.emit(0.15 + 0.4 * k, 0.25)
			if _timer <= 0.0:
				_strike()
		State.STRIKE:
			_timer += dt
			_animate_strike(_timer)
			if not _bitten and _timer >= BITE_S:
				_bitten = true
				_bite()
			if _timer >= STRIKE_S:
				_body.visible = false
				state = State.COOLDOWN
				_timer = COOLDOWN_S
		State.COOLDOWN:
			_timer -= dt
			if _timer <= 0.0:
				if on_sand(vp):
					start_hunt()
				else:
					state = State.IDLE
					aggressive = false
	var underground := state == State.HUNT or state == State.TELEGRAPH
	if not underground:
		_settle(-1.0)            # ушёл в глубину — вал оседает целиком
	_wake.emitting = underground
	if underground:
		_wake.position = Vector3(pos.x, ground_y(pos) + 0.1, pos.y)
		_wake.rotation.y = atan2(-_heading.x, -_heading.y)


## Вал за червём: песок поднимается на ярус вдоль пройденного отрезка, деревья рядом валятся.
func _raise_ridge() -> void:
	if _ridge_from.distance_to(pos) > 0.3:
		Deformation.raise_vertices(terrain, Deformation.vertices_near_segment(_ridge_from, pos, RIDGE_HALF_W), _raised)
		_ridge_from = pos
	_settle(RIDGE_KEEP)
	_fell_trees(pos, 1.2)


## Вал позади оседает: углы дальше keep от червя возвращаются к исходной высоте (keep < 0 — все).
func _settle(keep: float) -> void:
	if _raised.is_empty():
		return
	var verts: Array[Vector2i] = []
	var seen := {}
	for key: Vector3i in _raised:
		var v := Deformation.recorded_vertex(key)
		if not seen.has(v) and (keep < 0.0 or Vector2(v).distance_to(pos) > keep):
			seen[v] = true
			verts.append(v)
	if not verts.is_empty():
		Deformation.restore_vertices(terrain, verts, _raised)


func _exit_tree() -> void:
	_settle(-1.0)


func _fell_trees(at: Vector2, radius: float) -> void:
	var c := Grid.tile_of_world(at.x, at.y)
	var r := ceili(radius)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := c + Vector2i(dx, dz)
			if query.has_standing_tree(t.x, t.y) and query.tree_position(t.x, t.y).distance_to(at) < radius:
				query.fell_tree(t.x, t.y)


## Начать охоту (услышал машину или отладка): гул и вал по песку.
func start_hunt() -> void:
	state = State.HUNT
	aggressive = true
	_lost = 0.0
	_ridge_from = pos
	EventBus.fauna_alerted.emit(&"worm", Vector3(pos.x, ground_y(pos), pos.y))


func _strike() -> void:
	state = State.STRIKE
	_timer = 0.0
	_bitten = false
	_ring.visible = false
	_body.visible = true
	_body.position = Vector3(_strike_at.x, _ground - 6.0, _strike_at.y)
	_body.rotation = Vector3.ZERO
	_burst.position = Vector3(_strike_at.x, _ground + 0.1, _strike_at.y)
	_burst.restart()
	_burst.emitting = true
	EventBus.camera_shake_requested.emit(1.2, 0.8)
	_fell_trees(_strike_at, R + 0.8)
	EventBus.fauna_alerted.emit(&"worm_strike", Vector3(_strike_at.x, _ground, _strike_at.y))


## Бросок: вырывается с раскрытой пастью, захлопывает её, вздымается, качается и уходит в песок.
func _animate_strike(t: float) -> void:
	var head_y: float          # высота основания головы над песком
	var jaw: float
	if t < RISE_S:
		head_y = lerpf(-4.0, 0.3, _ease_out(t / RISE_S))
		jaw = JAW_OPEN
	elif t < BITE_S:
		var k := (t - RISE_S) / (BITE_S - RISE_S)
		head_y = lerpf(0.3, 1.4, k)
		jaw = lerpf(JAW_OPEN, 0.0, k * k)
	elif t < HOLD_S:
		var k := (t - BITE_S) / (HOLD_S - BITE_S)
		head_y = lerpf(1.4, TOP_Y, _ease_out(minf(k * 1.6, 1.0)))
		jaw = 0.0
	else:
		var k := (t - HOLD_S) / (STRIKE_S - HOLD_S)
		head_y = lerpf(TOP_Y, -6.0, k * k)
		jaw = 0.0
	_body.position.y = _ground + head_y - SEGMENTS * 0.62
	var sway := clampf((t - BITE_S) / 0.5, 0.0, 1.0)
	_body.rotation = Vector3(sin(_time * 2.3) * 0.12 * sway, 0.0, sin(_time * 1.7) * 0.16 * sway)
	for hinge in _jaws:
		hinge.rotation.z = jaw


## Челюсти захлопнулись: если машина ещё в пасти — урон, червь выплёвывает её; в песке остаётся яма.
func _bite() -> void:
	EventBus.camera_shake_requested.emit(0.9, 0.4)
	Deformation.crater(terrain, _strike_at, 2.2, 1)
	var s := vehicle.state
	var d := s.pos.distance_to(_strike_at)
	if d > STRIKE_R or s.falling or s.drowning:
		return
	damaged.emit(rules.worm_damage, &"worm")
	var dir := (s.pos - _strike_at).normalized() if d > 0.05 else Vector2.from_angle(rng.randf() * TAU)
	var target := _strike_at + dir * rules.worm_toss
	var t := Grid.tile_of_world(target.x, target.y)
	if query.is_loaded(t.x, t.y):
		VehicleKinematics.launch(s, target, 2.4, vehicle.cls, query)


static func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)


func _build() -> void:
	_wake = _dust(SAND_COLOR.darkened(0.2), 70, 1.2, Vector3.UP, 60.0, 0.8, 2.4, 0.12)
	_wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_wake.emission_box_extents = Vector3(0.8, 0.05, 1.4)
	_build_ring()
	_build_body()
	_burst = _dust(Color(0.66, 0.52, 0.66), 90, 1.4, Vector3.UP, 30.0, 4.0, 9.0, 0.16)
	_burst.one_shot = true
	_burst.explosiveness = 0.8
	_burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_burst.emission_ring_axis = Vector3.UP
	_burst.emission_ring_radius = R + 0.3
	_burst.emission_ring_inner_radius = R * 0.6
	_burst.emission_ring_height = 0.1
	_burst.emitting = false


## Кольцо трещин вокруг точки броска.
func _build_ring() -> void:
	_ring = Node3D.new()
	add_child(_ring)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = CRACK_COLOR
	for i in 12:
		var crack := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.08, 0.02, 0.9)
		crack.mesh = cb
		crack.material_override = _ring_mat
		var a := TAU * i / 12.0
		crack.position = Vector3(cos(a), 0.0, sin(a)) * (R + 0.2)
		crack.rotation.y = -a + PI * 0.5
		_ring.add_child(crack)


## Тело — кольчатые сегменты толщиной с пасть; голова — три челюсти-лепестка (сектора купола),
## внутри — глотка и кольцо зубов.
func _build_body() -> void:
	_body = Node3D.new()
	add_child(_body)
	var mat := Creature.material(BODY_COLOR)
	var ring := Creature.material(RING_COLOR)
	for i in SEGMENTS:
		var y := i * 0.62
		var seg := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = R
		c.bottom_radius = R * 1.04
		c.height = 0.58
		c.radial_segments = 14
		c.rings = 0
		seg.mesh = c
		seg.material_override = mat
		seg.position = Vector3(0, y + 0.29, 0)
		_body.add_child(seg)
		var band := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = R * 1.07
		bc.bottom_radius = R * 1.07
		bc.height = 0.08
		bc.radial_segments = 14
		bc.rings = 0
		band.mesh = bc
		band.material_override = ring
		band.position = Vector3(0, y + 0.6, 0)
		_body.add_child(band)
	var top := SEGMENTS * 0.62
	var throat := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = R * 0.9
	tc.bottom_radius = R * 0.9
	tc.height = 0.04
	tc.radial_segments = 14
	tc.rings = 0
	throat.mesh = tc
	throat.material_override = Creature.material(THROAT_COLOR)
	throat.position = Vector3(0, top + 0.02, 0)
	_body.add_child(throat)
	var tooth := Creature.material(TOOTH_COLOR)
	for i in 16:     # кольцо зубов по краю глотки, остриём внутрь и вверх
		var a := TAU * i / 16.0
		var t := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.06
		cone.height = 0.24
		cone.radial_segments = 4
		cone.rings = 0
		t.mesh = cone
		t.material_override = tooth
		t.position = Vector3(cos(a) * R * 0.8, top + 0.1, sin(a) * R * 0.8)
		t.rotation = Vector3(0, -a, 0.9)
		_body.add_child(t)
	var petal_mesh := _petal_mesh()
	var jaw_mat := Creature.material(BODY_COLOR.darkened(0.08))
	jaw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 3:
		var turn := Node3D.new()
		turn.position = Vector3(0, top, 0)
		turn.rotation.y = -TAU * i / 3.0
		_body.add_child(turn)
		var hinge := Node3D.new()
		hinge.position = Vector3(R, 0, 0)
		turn.add_child(hinge)
		var petal := MeshInstance3D.new()
		petal.mesh = petal_mesh
		petal.material_override = jaw_mat
		hinge.add_child(petal)
		for j in 3:      # зубы на внутренней стороне челюсти
			var t := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.05
			cone.height = 0.2
			cone.radial_segments = 4
			cone.rings = 0
			t.mesh = cone
			t.material_override = tooth
			t.position = Vector3(-0.18, 0.25 + j * 0.22, (j - 1) * 0.3)
			t.rotation.z = PI * 0.5
			hinge.add_child(t)
		_jaws.append(hinge)


## Челюсть — сектор купола радиуса R в 120° (вокруг оси Y) от основания до макушки, в координатах
## шарнира: шарнир — середина нижней кромки сектора, ось поворота — касательная к ней (локальная Z).
static func _petal_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nt := 6
	var ne := 5
	var pts: Array[Vector3] = []
	for ie in ne + 1:
		var e := PI * 0.5 * ie / ne
		for it in nt + 1:
			var t := lerpf(-PI / 3.0, PI / 3.0, float(it) / nt)
			pts.append(Vector3(R * cos(e) * cos(t), R * 1.05 * sin(e), R * cos(e) * sin(t)) - Vector3(R, 0, 0))
	for ie in ne:
		for it in nt:
			var a := ie * (nt + 1) + it
			var b := a + 1
			var c := a + nt + 1
			var d := c + 1
			for v in [pts[a], pts[c], pts[b], pts[b], pts[c], pts[d]]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _dust(color: Color, amount: int, lifetime: float, direction: Vector3, spread: float,
		v_min: float, v_max: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.direction = direction
	p.spread = spread
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = Vector3(0, -7.0, 0)
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	q.material = m
	p.mesh = q
	add_child(p)
	return p
