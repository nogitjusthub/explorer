class_name PixelFx
extends RefCounted
## Пиксельные частицы. Пиксель всей игры — тексель рельефа (Grid.ART_PX = 1/16 тайла, около 1,8 пикселя
## рендера): квад частицы — целое число таких пикселей. Облачка пыли и брызги от 3 пикселей — спрайтом
## круга из этих пикселей, мельче — сплошным квадратом. Прозрачность — отсечением: ни полупрозрачных краёв,
## ни плавного угасания — частица гаснет разом, когда альфа (цвета или рампы) падает ниже половины.

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
