class_name Creature
extends Node3D
## Общее у существ (GDD §5.4): ссылки на мир и машину, позиция на сетке, урон машине сигналом,
## потеря интереса, таран машиной (тела RamBody: удар, мигание, гибель). FaunaDirector вызывает step() в
## физическом кадре и ram() после шагов всех существ; finished — существо можно убрать.

signal damaged(amount: int, source: StringName)

var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var noise: NoiseField
var director: Node                       ## FaunaDirector — поля путей
var rng: RandomNumberGenerator

var pos := Vector2.ZERO
var finished := false
var aggressive := false                  ## атакует (не уйдёт за кольцо, пока гоняется)
var bodies: Array[RamBody] = []          ## тела под тараном: у стаи — по особи; пусто — таран не берёт (червь, Несса)
var dead := false                        ## все тела убиты тараном: не атакует, мигает и пропадает
var kills := 0                           ## тел убито тараном

var _best_d := INF                       ## ближе всего к машине за погоню
var _no_progress := 0.0                  ## сколько секунд не удаётся подобраться ближе


func _init() -> void:
	name = "Creature"


func step(_dt: float) -> void:
	pass


# --- Таран машиной (GDD §5.4) --------------------------------------------------------------------


## Машина (центр at, днище на высоте vy, скорость vel) въехала в тела существа; fast — не медленнее порога
## валки деревьев своего класса (VehicleKinematics.fells). Удар — по каждому телу, которого коснулась
## впервые (RamBody.struck); отклик — _on_rammed, все тела убиты — _on_died. Возвращает число ударов.
func ram(at: Vector2, vy: float, vel: Vector2, fast: bool) -> int:
	var hits := 0
	for b in bodies:
		if not b.struck(at, vy, vel, fast, ram_reachable(b)):
			continue
		hits += 1
		var killed := b.hit()
		if killed:
			kills += 1
		EventBus.fauna_alerted.emit(&"rammed", Vector3(b.pos.x, b.y, b.pos.y))
		_on_rammed(b, vel.normalized(), killed)
	if hits > 0 and not dead and bodies.all(func(b: RamBody) -> bool: return not b.alive()):
		dead = true
		aggressive = false
		_on_died()
	return hits


## Тело b досягаемо для тарана (илозуб — только над поверхностью).
func ram_reachable(_b: RamBody) -> bool:
	return true


## Отклик на удар по телу b (dir — куда ехала машина); killed — тело гибнет.
func _on_rammed(_b: RamBody, _dir: Vector2, _killed: bool) -> void:
	pass


## Все тела убиты: существо не атакует (step дальше только доигрывает гибель).
func _on_died() -> void:
	pass


## Новое тело под тараном: hits ударов выдержит, model мигает и пропадает, облачко — цвета puff_color.
func add_body(hits: int, radius: float, model: Node3D, puff_color: Color) -> RamBody:
	var b := RamBody.new(hits, radius, rules, model, self, puff_color)
	bodies.append(b)
	return b


## Мигание и гибель тел — в начале step(). Убитое существо уходит (finished), когда все тела пропали и
## облачка погасли.
func tick_bodies(dt: float) -> void:
	for b in bodies:
		b.tick(dt)
	if dead and bodies.all(func(b: RamBody) -> bool: return b.done()):
		finished = true


## Прогрев шейдеров: наложение мигания на всех телах.
func preview_flash() -> void:
	for b in bodies:
		b.preview_flash()


## Потеря интереса (GDD §5.4): погоня идёт, пока существо подбирается к машине. Не стало ближе на
## INTEREST_STEP за fauna_give_up_s (машина ушла — она быстрее; забралась туда, куда не пройти) — true,
## существо сдаётся. reached — атакует вплотную: интерес не теряет.
const INTEREST_STEP := 0.5


func lost_interest(dt: float, d: float, reached: bool = false) -> bool:
	if reached or d < _best_d - INTEREST_STEP:
		_best_d = minf(_best_d, d) if not reached else d
		_no_progress = 0.0
		return false
	_no_progress += dt
	return _no_progress > rules.fauna_give_up_s


func reset_interest() -> void:
	_best_d = INF
	_no_progress = 0.0


## Один уровень (GDD §5.4): атака достаёт машину, только если существо и машина на одном уровне — по прямой
## от a до b поверхность (над водой — её зеркало) нигде не скачет на LEVEL_GAP яруса и больше: ни стенки
## вверх, ни обрыва вниз. Со скалы на машину под ней (и снизу на скалу) не кусают и не таранят; склон —
## тот же уровень, если концы разнятся по высоте меньше LEVEL_SPAN. Машина в мелкой воде — на уровне
## зеркала: с берега вровень с водой её достают, из-под уступа берега — нет.
const LEVEL_GAP := 0.5
const LEVEL_SPAN := 1.0


static func same_level(q: TerrainQuery, a: Vector2, b: Vector2) -> bool:
	var ta := Grid.tile_of_world(a.x, a.y)
	var tb := Grid.tile_of_world(b.x, b.y)
	if not q.is_loaded(ta.x, ta.y) or not q.is_loaded(tb.x, tb.y):
		return false
	var prev := q.surface_tier_float(a.x, a.y)
	if absf(prev - q.surface_tier_float(b.x, b.y)) >= LEVEL_SPAN:
		return false
	var n := ceili(a.distance_to(b) / Grid.ART_PX)          # шаг — пиксель мира: стенку не перешагнуть
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / n)
		var h := q.surface_tier_float(p.x, p.y)
		if absf(h - prev) >= LEVEL_GAP:
			return false
		prev = h
	return true


## Труба от a до b (лапы, рога): тонкий цилиндр.
static func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	if b.y < a.y:
		var tmp := a
		a = b
		b = tmp
	var d := b - a
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = d.length() + radius
	c.radial_segments = 4
	c.rings = 0
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	parent.add_child(mi)
	return mi


func ground_y(p: Vector2) -> float:
	var t := Grid.tile_of_world(p.x, p.y)
	return query.surface_y(p.x, p.y) if query.is_loaded(t.x, t.y) else 0.0


## Сдвиг по плоскости с проверкой рёбер вида: в соседний тайл — только по проходимому ребру.
static func move_on_grid(q: TerrainQuery, mode: FlowField.Mode, from: Vector2, to: Vector2) -> Vector2:
	var a := Grid.tile_of_world(from.x, from.y)
	var b := Grid.tile_of_world(to.x, to.y)
	if a == b:
		return to
	var step := b - a
	if absi(step.x) + absi(step.y) == 1:
		var dir := Grid.DIR_OFFSETS.find(step)
		return to if FlowField.passable(q, mode, a, dir) else from
	# По диагонали — через любой из двух промежуточных тайлов.
	var via_x := a + Vector2i(step.x, 0)
	var via_z := a + Vector2i(0, step.y)
	var dx := Grid.DIR_OFFSETS.find(Vector2i(step.x, 0))
	var dz := Grid.DIR_OFFSETS.find(Vector2i(0, step.y))
	if (FlowField.passable(q, mode, a, dx) and FlowField.passable(q, mode, via_x, dz)) \
			or (FlowField.passable(q, mode, a, dz) and FlowField.passable(q, mode, via_z, dx)):
		return to
	return from


static func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m


## Покров с пиксельным узором (M5): панцирь, шкура, чешуя, ил. Цвет — BodyMaterial.set_color.
static func skin(color: Color, pattern: BodyMaterial.Pattern, px: float, roughness: float = 0.8) -> ShaderMaterial:
	return BodyMaterial.make(color, pattern, px, roughness)
