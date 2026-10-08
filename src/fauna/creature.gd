class_name Creature
extends Node3D
## Общее у существ (GDD §5.4): ссылки на мир и машину, позиция на сетке, урон машине сигналом.
## FaunaDirector вызывает step() в физическом кадре; finished — существо можно убрать.

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


func _init() -> void:
	name = "Creature"


func step(_dt: float) -> void:
	pass


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
