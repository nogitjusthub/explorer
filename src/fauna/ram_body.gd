class_name RamBody
extends RefCounted
## Тело существа под тараном машины (GDD §5.4): у панцирника и илозуба — одно, у стаи скакунов — по особи.
## Машина въехала в тело (касание: центры ближе ram_vehicle_r + radius — до носа модели, высоты рядом) на
## скорости тарана своего класса, двигаясь к нему, — удар. Удар засчитывается только с нового касания и не в
## неуязвимости после прошлого (ram_invuln_s): один контакт — один удар. Урон — мигание модели: белое
## наложение поверх всех её материалов (material_overlay, как у разряда по машине — ShockFx) сменяется
## обычным видом ступенями FLASH_STEP_S, без плавных переходов, ram_flash_s. Последний удар — гибель: тело
## мигает ram_death_s, затем модель пропадает облачком пиксельной пыли (PixelFx).

enum Life { ALIVE, DYING, GONE }

const FLASH_STEP_S := 0.05               ## мигание: белое и обычное сменяются через столько
const FLASH_COLOR := Color(1.0, 1.0, 1.0, 0.85)
const REACH_DY := 0.45                   ## таран достаёт тело, если его основание не дальше этого по высоте от днища
const PUFF_S := 0.55                     ## облачко гибели живёт столько — потом существо можно убрать
const PUFF_TEXELS := 3                   ## клубы облачка — круги 3×3 пикселя мира

static var _flash_mat: StandardMaterial3D

var hits_left := 1
var radius := 0.3                        ## тайлов
var pos := Vector2.ZERO                  ## центр тела на плоскости — существо обновляет каждый кадр
var y := 0.0                             ## высота основания тела (мировая) — для касания и облачка
var life := Life.ALIVE
var touching := false                    ## машина касалась тела в прошлый раз (удар — только с нового касания)

var _vehicle_r := 0.4                    ## тайлов: досягаемость тарана от центра машины
var _invuln_s := 0.5
var _flash_s := 0.4
var _death_s := 0.5
var _invuln := 0.0
var _flash := 0.0
var _clock := 0.0                        ## с удара — фаза мигания
var _left := 0.0                         ## DYING — до исчезновения, GONE — пока летит облачко
var _lit := false
var _model: Node3D
var _parts: Array[GeometryInstance3D] = []
var _puff: CPUParticles3D


## hits — сколько ударов выдержит; model — модель тела (мигает, пропадает); puff_parent — куда положить
## облачко гибели (частицы в мировых координатах).
func _init(hits: int, body_radius: float, rules: BalanceRules, model: Node3D, puff_parent: Node3D,
		puff_color: Color) -> void:
	hits_left = hits
	radius = body_radius
	_vehicle_r = rules.ram_vehicle_r
	_invuln_s = rules.ram_invuln_s
	_flash_s = rules.ram_flash_s
	_death_s = rules.ram_death_s
	_model = model
	if model != null:
		_collect(model)
	if puff_parent != null:
		_puff = _make_puff(puff_color)
		puff_parent.add_child(_puff)


## Белое наложение мигания — общее у всех тел: без освещения, с прозрачностью (ключ шейдера уже прогрет).
static func flash_material() -> StandardMaterial3D:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.albedo_color = FLASH_COLOR
	return _flash_mat


func alive() -> bool:
	return life == Life.ALIVE


## Тело пропало, и облачко погасло.
func done() -> bool:
	return life == Life.GONE and _left <= 0.0


## Сейчас мигает (неуязвимость после удара или гибель).
func flashing() -> bool:
	return life == Life.DYING or _flash > 0.0


## Машина (центр at, днище на высоте vy, скорость vel) въехала в тело: касание новое (в прошлый раз не
## касалась), не в неуязвимости, машина движется к телу; fast — не медленнее порога тарана своего класса;
## reach — тело досягаемо (илозуба в иле таран не достаёт). Касание запоминается в любом случае.
func struck(at: Vector2, vy: float, vel: Vector2, fast: bool, reach: bool) -> bool:
	var near := alive() and reach and at.distance_to(pos) < reach_dist() \
			and absf(y - vy) < REACH_DY
	var fresh := near and not touching
	touching = near
	return fresh and fast and _invuln <= 0.0 and vel.dot(pos - at) > 0.0


## Касание: центр машины ближе этого к центру тела (досягаемость тарана + радиус тела).
func reach_dist() -> float:
	return _vehicle_r + radius


## Удар: −1 к запасу, неуязвимость и мигание; запас кончился — гибель (true).
func hit() -> bool:
	hits_left -= 1
	_invuln = _invuln_s
	_clock = 0.0
	if hits_left <= 0:
		life = Life.DYING
		_left = _death_s
		touching = false
	else:
		_flash = _flash_s
	_show()
	return life == Life.DYING


func tick(dt: float) -> void:
	_invuln = maxf(_invuln - dt, 0.0)
	_flash = maxf(_flash - dt, 0.0)
	_clock += dt
	match life:
		Life.DYING:
			_left -= dt
			if _left <= 0.0:
				_vanish()
		Life.GONE:
			_left -= dt
	_show()


## Отладка и прогрев шейдеров: наложение мигания включено (до следующего tick).
func preview_flash() -> void:
	_set_lit(true)


## Белое — первые FLASH_STEP_S после удара, потом через раз.
func _show() -> void:
	_set_lit(flashing() and fmod(_clock, FLASH_STEP_S * 2.0) < FLASH_STEP_S)


func _set_lit(on: bool) -> void:
	if on == _lit:
		return
	_lit = on
	for g in _parts:
		if is_instance_valid(g):
			g.material_overlay = flash_material() if on else null


## Модель пропадает, на её месте — облачко пиксельной пыли.
func _vanish() -> void:
	life = Life.GONE
	_left = PUFF_S
	_set_lit(false)
	if _model != null:
		_model.visible = false
	if _puff != null and _puff.is_inside_tree():
		_puff.position = Vector3(pos.x, y + 0.15, pos.y)
		_puff.restart()
		_puff.emitting = true


func set_puff_color(color: Color) -> void:
	if _puff != null:
		((_puff.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = color


func _collect(n: Node) -> void:
	if n is GeometryInstance3D and not n is CPUParticles3D:
		_parts.append(n)
	for c in n.get_children():
		_collect(c)


## Облачко: разовый выброс клубов-кругов PixelFx, разлетаются и оседают; гаснут разом (без угасания).
func _make_puff(color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 12
	p.lifetime = PUFF_S
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.5
	p.emitting = false
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.7
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.gravity = Vector3(0, -1.5, 0)
	p.mesh = PixelFx.quad(PUFF_TEXELS, color)
	return p
