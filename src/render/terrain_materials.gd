class_name TerrainMaterials
extends RefCounted
## Общие материалы и меши рельефа: создаются один раз и делятся между всеми чанками.

const TREE_TYPES := 2
const TOPS_ATLAS := "res://assets/textures/terrain_tops.png"   ## генерирует tools/textures/gen_terrain_tops.gd
const WALLS_ATLAS := "res://assets/textures/cliff_walls.png"   ## генерирует tools/textures/gen_cliff_walls.gd
const WATER_CYCLE := "res://assets/textures/water_cycle.png"   ## генерирует tools/textures/gen_water_cycle.gd
const SPRITES_ATLAS := "res://assets/textures/ground_sprites.png"   ## генерирует tools/textures/gen_ground_sprites.gd

var terrain: ShaderMaterial
var water: ShaderMaterial
var trunk_mesh: Mesh
var crown_meshes: Array[Mesh] = []
var log_mesh: Mesh
var sprite_mesh: Mesh                    ## квад мелочи на земле (полтайла, низ — у земли)


func _init() -> void:
	terrain = ShaderMaterial.new()
	terrain.shader = load("res://src/render/shaders/terrain.gdshader")
	terrain.set_shader_parameter("tier_h", Grid.TIER_H)
	terrain.set_shader_parameter("tops", load(TOPS_ATLAS))     # пиксельные текстуры верха тайлов (M5)
	terrain.set_shader_parameter("walls", load(WALLS_ATLAS))   # …и стенок обрывов
	water = ShaderMaterial.new()
	water.shader = load("res://src/render/shaders/water.gdshader")
	water.set_shader_parameter("cycle", load(WATER_CYCLE))     # рябь перебором палитры (M5)

	var tree_shader: Shader = load("res://src/render/shaders/tree.gdshader")
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.05
	trunk.bottom_radius = 0.08
	trunk.height = 0.65
	trunk.radial_segments = 5
	trunk.rings = 0
	trunk.material = _tree_material(tree_shader, Color(0.36, 0.24, 0.34), 0.0, 1)          # кора
	trunk_mesh = trunk

	var coral := SphereMesh.new()       # кораллоподобная крона
	coral.radius = 0.28
	coral.height = 0.45
	coral.radial_segments = 6
	coral.rings = 3
	coral.material = _tree_material(tree_shader, Color(0.26, 0.5, 0.48), 0.06, 2)   # приглушённая бирюза, полипы
	crown_meshes.append(coral)

	var shroom := CylinderMesh.new()    # грибовидная крона
	shroom.top_radius = 0.36
	shroom.bottom_radius = 0.08
	shroom.height = 0.18
	shroom.radial_segments = 7
	shroom.rings = 0
	shroom.material = _tree_material(tree_shader, Color(0.52, 0.35, 0.5), 0.05, 3)   # приглушённый пурпур, крапины
	crown_meshes.append(shroom)

	var fallen := CylinderMesh.new()
	fallen.top_radius = 0.07
	fallen.bottom_radius = 0.07
	fallen.height = 0.85
	fallen.radial_segments = 5
	fallen.rings = 0
	fallen.material = trunk.material
	log_mesh = fallen

	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)                    # 8 текселей по 1/16 тайла — как у рельефа
	quad.center_offset = Vector3(0.0, 0.25, 0.0)     # низ квада — у земли
	var sprite_mat := ShaderMaterial.new()
	sprite_mat.shader = load("res://src/render/shaders/ground_sprite.gdshader")
	sprite_mat.set_shader_parameter("atlas", load(SPRITES_ATLAS))
	quad.material = sprite_mat
	sprite_mesh = quad


## pattern — пиксельный узор tree.gdshader: 1 — кора, 2 — коралл, 3 — гриб.
static func _tree_material(shader: Shader, color: Color, glow: float, pattern: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("pattern", pattern)
	return m
