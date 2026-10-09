class_name Creature
extends Node3D
## Общее у существ (GDD §5.4): ссылки на мир и машину, позиция на сетке, урон машине сигналом,
## потеря интереса. FaunaDirector вызывает step() в физическом кадре; finished — существо можно убрать.

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

var _best_d := INF                       ## ближе всего к машине за погоню
var _no_progress := 0.0                  ## сколько секунд не удаётся подобраться ближе


func _init() -> void:
	name = "Creature"


func step(_dt: float) -> void:
	pass


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
