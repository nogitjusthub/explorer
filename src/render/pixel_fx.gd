class_name PixelFx
extends RefCounted
## Пиксельные частицы. Пиксель всей игры — тексель рельефа (Grid.ART_PX = 1/16 тайла, около 1,8 пикселя
## рендера): квад частицы — целое число таких пикселей. Облачка пыли и брызги от 3 пикселей — спрайтом
## круга из этих пикселей, мельче — сплошным квадратом. Прозрачность — отсечением: ни полупрозрачных краёв,
## ни плавного угасания — частица гаснет разом, когда альфа (цвета или рампы) падает ниже половины. Пыль и
## комья — общие для всех эффектов (dust, clods): одинаковый вид, разная сила.

static var _puffs: Dictionary[int, ImageTexture] = {}


## Квад частицы-билборда стороной texels пикселей. Цвет — albedo (color) или цвет частицы
## (vertex_color: color / color_ramp у CPUParticles3D). Материал — StandardMaterial3D (цвет можно менять).
static func quad(texels: int, color: Color = Color.WHITE, vertex_color: bool = false) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * texels * Grid.ART_PX
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_color = color
	m.vertex_color_use_as_albedo = vertex_color
	if texels >= 3:
		m.albedo_texture = puff(texels)
	q.material = m
	return q


## Круг n×n пикселей: пиксель внутри, если его центр не дальше n/2 − 0,25 от середины (у 3×3 — крест,
## у 4×4 — без углов).
static func puff(n: int) -> ImageTexture:
	if _puffs.has(n):
		return _puffs[n]
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := n * 0.5
	for y in n:
		for x in n:
			var inside := Vector2(x + 0.5 - c, y + 0.5 - c).length() <= c - 0.25
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if inside else 0.0))
	var tex := ImageTexture.create_from_image(img)
	_puffs[n] = tex
	return tex


# --- Пыль и комья: одни на всех ---------------------------------------------------------------------------
# Машина, червь, смерч, землетрясение, капсула десанта, челнок, панцирник: облачко пыли и ком грязи выглядят
# одинаково — разное только сколько, как быстро и откуда (форму испускания, направление и скорость задаёт
# вызывающий). Цвет — от грунта под эффектом (dust_color, clod_color), задаётся цветом частиц (CPUParticles3D.color).

const DUST_TEXELS := 4                   ## облачко пыли — круг 4×4 пикселя
const CLOD_TEXELS := 2                   ## ком грязи — квадрат 2×2
const DUST_GRAVITY := -1.0               ## пыль медленно оседает (и тормозится воздухом)…
const CLOD_GRAVITY := -9.0               ## …комья падают по дуге


## Пыль: облачка, медленно оседают, тормозятся воздухом; тени не отбрасывают.
static func dust(amount: int, lifetime: float) -> CPUParticles3D:
	var p := _emitter(amount, lifetime, DUST_TEXELS)
	p.gravity = Vector3(0, DUST_GRAVITY, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	return p


## Комья грязи: квадратики, падают по дуге.
static func clods(amount: int, lifetime: float) -> CPUParticles3D:
	var p := _emitter(amount, lifetime, CLOD_TEXELS)
	p.gravity = Vector3(0, CLOD_GRAVITY, 0)
	return p


## Цвет пыли над точкой (x, z) мира: материал грунта, светлее.
static func dust_color(q: TerrainQuery, x: float, z: float) -> Color:
	return Color(_ground(q, x, z).lightened(0.18), 1.0)


## Цвет комьев над точкой (x, z): материал грунта, темнее; зыбун — мокрый, ещё темнее.
static func clod_color(q: TerrainQuery, x: float, z: float) -> Color:
	var tx := floori(x)
	var tz := floori(z)
	var mire := q != null and q.is_loaded(tx, tz) and (q.flags(tx, tz) & ChunkData.FLAG_MIRE) != 0
	return Color(_ground(q, x, z).darkened(0.45 if mire else 0.3), 1.0)


static func _ground(q: TerrainQuery, x: float, z: float) -> Color:
	var tx := floori(x)
	var tz := floori(z)
	if q == null or not q.is_loaded(tx, tz):
		return ChunkMesher.MATERIAL_COLORS[0]
	return ChunkMesher.MATERIAL_COLORS[clampi(q.material(tx, tz), 0, 3)]


static func _emitter(amount: int, lifetime: float, texels: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.direction = Vector3.UP
	p.mesh = quad(texels, Color.WHITE, true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
