class_name DropPod
extends Node3D
## Десант (GDD §2.1): капсула с машиной падает с орбиты. На земле заранее растёт тень и мигает маркер
## посадки. Капсула падает с разгоном, у самой земли включает тормозные двигатели — струи пламени вниз,
## подсветка, пыль с земли, рёв — и мягко садится: глухой удар, кольцо пыли, лёгкая тряска (звук удара —
## AudioDirector по EventBus.drop_landed). Затем капсула раскрывается тремя лепестками, машина свободна.

signal landed                            ## касание земли
signal opened                            ## лепестки разлетелись — машина видна

const FREE_FALL_S := 1.4                 ## свободное падение с разгоном…
const BURN_H := 10.0                     ## …до этой высоты; дальше — торможение двигателями до касания
const START_H := 30.0
const OPEN_S := 0.6
const POD_SCALE := 0.7                   ## капсула чуть больше машины
const SHELL_COLOR := Color(0.55, 0.57, 0.62)
const BASE_COLOR := Color(0.24, 0.24, 0.28)
const FLAME_COLOR := Color(1.0, 0.72, 0.35)
const FLAME_CORE := Color(1.0, 0.95, 0.8)
const MARK_COLOR := Color(0.45, 1.0, 0.95, 0.8)
const SHADOW_COLOR := Color(0.05, 0.03, 0.06, 0.5)
const NOZZLES := 3

var _t := 0.0
var _ground := Vector3.ZERO
var _phase := 0                          ## 0 — падение, 1 — раскрытие, 2 — готово
var _pod: Node3D
var _petals: Array[Node3D] = []
var _flames: Array[Node3D] = []          ## опора струи у сопла: масштаб по y тянет пламя вниз
var _flame_light: OmniLight3D
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D
var _marker: Node3D
var _marker_mat: StandardMaterial3D
var _blast: CPUParticles3D               ## пыль, которую струи поднимают с земли
var _dust: CPUParticles3D                ## кольцо пыли при касании
var _roar: AudioStreamPlayer
var _burning := false


func _init() -> void:
	name = "DropPod"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func start(ground: Vector3) -> void:
	_ground = ground
	_build()
	_update()


## Высота над землёй через t секунд после начала: разгон до BURN_H, затем торможение с той же скоростью
## до нуля у земли (скорость непрерывна, касание мягкое).
static func height_at(t: float) -> float:
	if t <= FREE_FALL_S:
		var k := t / FREE_FALL_S
		return START_H - (START_H - BURN_H) * k * k
	var u := clampf((t - FREE_FALL_S) / burn_s(), 0.0, 1.0)
	return BURN_H * (1.0 - u) * (1.0 - u)


## Длительность торможения: равнозамедленно с той же скорости до нуля на высоте BURN_H.
static func burn_s() -> float:
	return 2.0 * BURN_H / (2.0 * (START_H - BURN_H) / FREE_FALL_S)


static func total_s() -> float:
	return FREE_FALL_S + burn_s()


## Прогрев шейдеров (Warmup): капсула стоит на земле с работающими двигателями, сцена не идёт.
func preview() -> void:
	set_process(false)
	_pod.position = _ground
	_burn(1.0)
	_blast.emitting = true


func _process(dt: float) -> void:
	if _phase == 2:
		return
	_t += dt
	_update()


func _update() -> void:
	if _phase == 0:
		var h := height_at(_t)
		var k := clampf(_t / total_s(), 0.0, 1.0)
		_pod.position = _ground + Vector3(0, h, 0)
		_shadow.scale = Vector3.ONE * lerpf(0.3, 1.0, k)
		_shadow_mat.albedo_color.a = SHADOW_COLOR.a * lerpf(0.3, 1.0, k)
		_marker_mat.albedo_color.a = MARK_COLOR.a * (0.5 + 0.5 * float(fmod(_t, 0.4) < 0.25))
		if _t >= FREE_FALL_S and not _burning:
			_burning = true
			_roar.play()
		if _burning:
			_burn(h)
		if _t >= total_s():
			_touchdown()
	elif _phase == 1:
		var k := clampf(_t / OPEN_S, 0.0, 1.0)
		for i in _petals.size():
			var p := _petals[i]
			p.rotation.z = -1.9 * k * k
			p.position.y = -0.6 * k * k
		if k >= 1.0:
			_phase = 2
			_pod.visible = false
			opened.emit()
			get_tree().create_timer(1.5).timeout.connect(queue_free)


## Торможение: струи мерцают и бьют в землю — чем ниже капсула, тем больше пыли и ярче подсветка.
func _burn(h: float) -> void:
	var near := 1.0 - clampf(h / BURN_H, 0.0, 1.0)
	for i in _flames.size():
		var f := _flames[i]
		f.visible = true
		var flick := 0.8 + 0.35 * sin(_t * 47.0 + i * 2.1)
		f.scale = Vector3(1.0, flick * lerpf(1.4, 0.8, near), 1.0)
	_flame_light.visible = true
	_flame_light.light_energy = 1.2 + 1.5 * near
	_blast.emitting = h < BURN_H * 0.7
	_blast.initial_velocity_max = lerpf(1.5, 4.5, near)      # ниже — струи бьют сильнее
	if fmod(_t, 0.12) < 0.02:
		EventBus.camera_shake_requested.emit(0.15 + 0.25 * near, 0.15)


func _touchdown() -> void:
	_phase = 1
	_t = 0.0
	_burning = false
	for f in _flames:
		f.visible = false
	_flame_light.visible = false
	_blast.emitting = false
	_marker.visible = false
	_shadow.visible = false
	_roar.stop()
	_dust.restart()
	_dust.emitting = true
	landed.emit()


func _build() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = SHELL_COLOR
	shell.roughness = 0.5
	shell.metallic = 0.4
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = BASE_COLOR
	base_mat.roughness = 0.7
	_pod = Node3D.new()
	_pod.scale = Vector3.ONE * POD_SCALE
	add_child(_pod)
	# Капсула из трёх лепестков-секторов вокруг оси: после посадки они откидываются наружу.
	for i in 3:
		var turn := Node3D.new()
		turn.rotation.y = -TAU * i / 3.0
		_pod.add_child(turn)
		var hinge := Node3D.new()
		hinge.position = Vector3(0.45, 0.05, 0)
		turn.add_child(hinge)
		var petal := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 1.1, 0.72)
		petal.mesh = box
		petal.material_override = shell
		petal.position = Vector3(-0.06, 0.55, 0)
		hinge.add_child(petal)
		var cap := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.42
		cone.height = 0.5
		cone.radial_segments = 3
		cone.rings = 0
		cap.mesh = cone
		cap.material_override = shell
		cap.position = Vector3(-0.3, 1.3, 0)
		cap.scale = Vector3(0.7, 1.0, 1.0)
		hinge.add_child(cap)
		_petals.append(hinge)
	# Днище с соплами тормозных двигателей; под каждым — струя пламени (видна только при торможении).
	var base := MeshInstance3D.new()
	var plate := CylinderMesh.new()
	plate.top_radius = 0.6
	plate.bottom_radius = 0.5
	plate.height = 0.14
	plate.radial_segments = 9
	plate.rings = 0
	base.mesh = plate
	base.material_override = base_mat
	base.position = Vector3(0, 0.0, 0)
	_pod.add_child(base)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = FLAME_COLOR
	var core_mat := flame_mat.duplicate() as StandardMaterial3D
	core_mat.albedo_color = FLAME_CORE
	for i in NOZZLES:
		var a := TAU * (i + 0.5) / NOZZLES
		var at := Vector3(cos(a), 0, sin(a)) * 0.3
		var nozzle := MeshInstance3D.new()
		var nz := CylinderMesh.new()
		nz.top_radius = 0.08
		nz.bottom_radius = 0.12
		nz.height = 0.14
		nz.radial_segments = 6
		nz.rings = 0
		nozzle.mesh = nz
		nozzle.material_override = base_mat
		nozzle.position = at + Vector3(0, -0.12, 0)
		_pod.add_child(nozzle)
		# Пламя: внешний конус и яркая сердцевина свисают из опоры у сопла — масштаб опоры тянет их вниз.
		var flame := Node3D.new()
		flame.position = at + Vector3(0, -0.19, 0)
		for spec: Array in [[0.11, 0.9, flame_mat], [0.05, 0.6, core_mat]]:
			var cone := CylinderMesh.new()
			cone.top_radius = spec[0]
			cone.bottom_radius = 0.0
			cone.height = spec[1]
			cone.radial_segments = 6
			cone.rings = 0
			var mi := MeshInstance3D.new()
			mi.mesh = cone
			mi.material_override = spec[2]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(0, -0.5 * float(spec[1]), 0)
			flame.add_child(mi)
		flame.visible = false
		_pod.add_child(flame)
		_flames.append(flame)
	_flame_light = OmniLight3D.new()
	_flame_light.light_color = FLAME_COLOR
	_flame_light.omni_range = 3.0
	_flame_light.shadow_enabled = false
	_flame_light.position = Vector3(0, -0.6, 0)
	_flame_light.visible = false
	_pod.add_child(_flame_light)

	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_color = SHADOW_COLOR
	var disc := CylinderMesh.new()
	disc.top_radius = 0.8
	disc.bottom_radius = 0.8
	disc.height = 0.02
	disc.radial_segments = 16
	disc.rings = 0
	_shadow = MeshInstance3D.new()
	_shadow.mesh = disc
	_shadow.material_override = _shadow_mat
	_shadow.position = _ground + Vector3(0, 0.05, 0)
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)

	_marker = Node3D.new()
	_marker.position = _ground + Vector3(0, 0.07, 0)
	add_child(_marker)
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.albedo_color = MARK_COLOR
	_marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := TorusMesh.new()
	ring.inner_radius = 1.25
	ring.outer_radius = 1.38
	ring.rings = 24
	ring.ring_segments = 4
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = _marker_mat
	ring_mi.scale = Vector3(1, 0.3, 1)
	_marker.add_child(ring_mi)
	for i in 4:     # перекрестье
		var tick := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.45, 0.02, 0.08)
		tick.mesh = tb
		tick.material_override = _marker_mat
		var a := TAU * i / 4.0
		tick.position = Vector3(cos(a), 0, sin(a)) * 0.95
		tick.rotation.y = -a
		_marker.add_child(tick)

	# Пыль из-под струй: по кольцу на земле, разлетается в стороны.
	_blast = _particles(Color(0.66, 0.54, 0.48), 70, 0.9, Vector3.UP, 80.0, 1.5, 4.0, 0.2)
	_blast.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_blast.emission_ring_axis = Vector3.UP
	_blast.emission_ring_radius = 1.0
	_blast.emission_ring_inner_radius = 0.2
	_blast.emission_ring_height = 0.1
	_blast.radial_accel_min = 4.0
	_blast.radial_accel_max = 7.0
	_blast.position = _ground + Vector3(0, 0.1, 0)
	_blast.emitting = false

	_dust = _particles(Color(0.62, 0.5, 0.45), 60, 1.2, Vector3.UP, 70.0, 1.5, 4.0, 0.2)
	_dust.one_shot = true
	_dust.explosiveness = 0.9
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_dust.emission_ring_axis = Vector3.UP
	_dust.emission_ring_radius = 1.1
	_dust.emission_ring_inner_radius = 0.4
	_dust.emission_ring_height = 0.1
	_dust.position = _ground + Vector3(0, 0.1, 0)
	_dust.emitting = false

	_roar = AudioStreamPlayer.new()
	_roar.stream = Sfx.thrust(burn_s() + 0.2)
	_roar.volume_db = -6.0
	add_child(_roar)


func _particles(color: Color, amount: int, lifetime: float, direction: Vector3, spread: float,
		v_min: float, v_max: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.direction = direction
	p.spread = spread
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = Vector3(0, -6.0, 0)
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
