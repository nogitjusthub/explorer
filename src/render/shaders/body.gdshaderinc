// Техника и фауна (M5): цвет детали × яркость пиксельного узора. Общий код body.gdshader (фауна),
// body_xray.gdshader (машины: пишет 1 в stencil — силуэт сквозь препятствия) и body_faces.gdshader
// (челноки и капсула десанта). Узор — по координатам
// самого меша (держится на детали), квантованным в сетку px; палитра прежняя. Свет — как у
// StandardMaterial3D по умолчанию (roughness, metallic — те же параметры). Узоры (BodyMaterial.Pattern):
// 1 — обшивка техники по граням (кромка, двери, люки, решётки — см. plates), 2 — траки гусеницы (грунтозацепы поперёк
// ленты), 3 — юбка ховера (секции-«пальцы»), 4 — щитки панциря (пояса щитков с тёмными швами и светлой
// серединой), 5 — шкура (морщинистая: светлые и тёмные крапины), 6 — кольчатое тело (бороздки с
// разрывами, редкие поры), 7 — чешуя (ряды со сдвигом, тень под чешуйкой, блик), 8 — мокрый ил (комки
// и блёстки), 9 — галька (камешки 2×2 разной яркости), 10 — хитин (пластины 2×2 разной яркости, тёмный
// шов, пиксели отлива на гранях, глядящих вверх).

uniform vec4 base_color : source_color = vec4(1.0);
uniform int pattern = 0;
uniform float px = 0.0625;              // шаг пиксельной сетки узора в единицах меша: пиксель мира (1/16 тайла)
                                        // с поправкой на масштаб узла (BodyMaterial, Grid.ART_PX)
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;   // как metallic_specular у StandardMaterial3D
uniform bool vertex_tint = false;       // цвет детали — ещё и в вершинах меша (× base_color, sRGB, как
                                        // vertex_color_is_srgb у StandardMaterial3D): у скакунов хитин,
                                        // кромка и кость — один материал (BodyMaterial.tinted)

varying vec3 obj_pos;
varying vec3 obj_nrm;
#ifdef FACE_DETAILS
varying vec4 detail0;
varying vec4 detail1;
#endif

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
#ifdef FACE_DETAILS
	detail0 = CUSTOM0;
	detail1 = CUSTOM1;
#endif
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
	return hash2(p.xy + p.z * 17.31);
}

// Координаты в плоскости грани (low-poly — грани плоские): x — по горизонтали грани, y — вверх по ней;
// у горизонтальной грани — x, z меша.
vec2 face_uv(vec3 p, vec3 n) {
	if (abs(n.y) > 0.9) {
		return p.xz;
	}
	vec3 t = normalize(vec3(-n.z, 0.0, n.x));
	return vec2(dot(p, t), dot(p, cross(t, n)));
}

// Обшивка техники — по граням (меш размечен MeshKit.face_mapped): uv — точка относительно центра грани,
// h — полуразмеры грани. Грань делится на целое число текселей ≈ px, детали встают по сетке
// симметрично. Кромка в тексель: у стенки верх светлее, низ темнее, бока чуть темнее; у крыши — светлая
// по кругу. До двух деталей на грань (codes — их коды: вид × 4 + 2, если ручка к −x грани, + 1, если
// петли к +y; rect0, rect1 — центр и полуразмеры в координатах грани): 1 — дверь (шов по контуру,
// тёмное окно сверху, ручка у края), 2 — крышка люка (шов, крышка светлее, петли у одного края, ручка у
// другого), 3 — решётка (шов, щели).
float cells(float h) {
	return max(round(2.0 * h / px), 1.0);
}

// Деталь на оси грани: первый тексель и длина в текселях. Середина — по сетке полутекселей, длина — той
// же чётности: деталь посередине грани встаёт ровно посередине.
vec2 span(float c, float w, float h, float n) {
	float cell = 2.0 * h / n;
	float mid = round((c + h) / cell * 2.0) * 0.5;
	float len = max(round(2.0 * w / cell), 1.0);
	if (mod(len, 2.0) != mod(mid * 2.0, 2.0)) {
		len += 1.0;
	}
	return vec2(mid - len * 0.5, len);
}

// Яркость детали с кодом code в текселе q грани (cnt текселей, полуразмеры h); вне детали — −1.
float face_detail(vec2 q, vec2 cnt, vec2 h, float code, vec4 rect) {
	float kind = floor(code / 4.0);
	if (kind < 0.5) {
		return -1.0;
	}
	vec2 sx = span(rect.x, rect.z, h.x, cnt.x);
	vec2 sy = span(rect.y, rect.w, h.y, cnt.y);
	vec2 size = vec2(sx.y, sy.y);
	vec2 l = q - vec2(sx.x, sy.x);
	if (l.x < 0.0 || l.y < 0.0 || l.x >= size.x || l.y >= size.y) {
		return -1.0;
	}
	if (mod(floor(code / 2.0), 2.0) > 0.5) {
		l.x = size.x - 1.0 - l.x;                     // ручка — к −x грани
	}
	if (mod(code, 2.0) > 0.5) {
		l.y = size.y - 1.0 - l.y;                     // петли — к +y грани
	}
	// Мелкие детали (пиксель узора — пиксель мира) — без петель, ручек и окон: только шов и крышка.
	if (l.x == 0.0 || l.y == 0.0 || l.x == size.x - 1.0 || l.y == size.y - 1.0) {
		if (kind == 2.0 && size.x >= 7.0 && l.y == 0.0 && (l.x == 2.0 || l.x == size.x - 3.0)) {
			return 1.25;                              // петли
		}
		return 0.72;                                  // шов по контуру
	}
	if (kind == 1.0) {
		float win = max(floor((size.y - 2.0) * 0.4), 1.0);
		if (size.y >= 5.0 && size.x >= 5.0 && l.y >= size.y - 1.0 - win && l.x >= 2.0 && l.x <= size.x - 3.0) {
			return 0.55;                              // окно
		}
		if (size.x >= 4.0 && size.y >= 4.0 && l.x == size.x - 2.0 && l.y == floor((size.y - 1.0) * 0.5)) {
			return 1.3;                               // ручка
		}
		return 1.0;
	}
	if (kind == 2.0) {
		if (size.y >= 5.0 && l.y == size.y - 2.0 && abs(l.x - (size.x - 1.0) * 0.5) < 0.6) {
			return 1.3;                               // ручка
		}
		return 1.06;
	}
	return mod(l.y, 2.0) == 0.0 ? 0.6 : 1.0;          // щели решётки
}

float plates(vec2 uv, vec2 h, vec3 n, vec2 codes, vec4 rect0, vec4 rect1) {
	vec2 cnt = vec2(cells(h.x), cells(h.y));
	vec2 q = clamp(floor((uv + h) / max(2.0 * h, vec2(1e-5)) * cnt), vec2(0.0), cnt - 1.0);
	bool side = cnt.x >= 3.0 && (q.x == 0.0 || q.x == cnt.x - 1.0);
	bool top = cnt.y >= 3.0 && q.y == cnt.y - 1.0;
	bool bottom = cnt.y >= 3.0 && q.y == 0.0;
	if (n.y > 0.9) {
		if (side || top || bottom) {
			return 1.12;
		}
	} else if (n.y > -0.9) {
		if (top) {
			return 1.15;
		}
		if (bottom) {
			return 0.82;
		}
		if (side) {
			return 0.92;
		}
	}
	float d = face_detail(q, cnt, h, codes.x, rect0);
	if (d < 0.0) {
		d = face_detail(q, cnt, h, codes.y, rect1);
	}
	return d < 0.0 ? 1.0 : d;
}

// Гусеница: призма профиля, выдавленная по y меша; лента — грани с нормалью поперёк y.
float track(vec3 p, vec3 n) {
	if (abs(n.y) > 0.5) {
		return 0.9;                                   // борт ленты
	}
	return mod(floor(face_uv(p, n).x / px), 3.0) == 0.0 ? 1.8 : 1.0;
}

// Юбка: капсула вдоль y меша, положена набок (вертикаль — z меша) — секции по углу вокруг вертикали.
float skirt(vec3 p) {
	float col = floor((atan(p.y, p.x) / 6.2831853 + 0.5) * 28.0);
	return mod(col, 2.0) == 0.0 ? 1.45 : 1.0;
}

// Панцирь: полусфера — три пояса щитков от края к макушке; граница щитка — шов, у шва — кольцо роста.
float scutes(vec3 p) {
	vec3 q = (floor(p / px) + 0.5) * px;
	vec3 d = normalize(q);
	float lat = asin(clamp(d.y, -1.0, 1.0)) / 1.5707963 * 3.0;
	float row = floor(lat);
	float cols = row < 1.0 ? 9.0 : (row < 2.0 ? 6.0 : 1.0);
	float lon = (atan(d.z, d.x) / 6.2831853 + 0.5) * cols + row * 0.5;
	float fr = min(fract(lat), 1.0 - fract(lat));
	float fc = cols > 1.0 ? min(fract(lon), 1.0 - fract(lon)) : 1.0;
	if (fr < 0.1 || fc < 0.07) {
		return 0.7;
	}
	if (fr < 0.22 || fc < 0.16) {
		return 0.92;
	}
	return hash3(floor(p / px)) > 0.9 ? 1.18 : 1.08;
}

float hide(vec3 p) {
	float r = hash3(floor(p / px));
	return r > 0.86 ? 1.14 : (r < 0.14 ? 0.84 : 1.0);
}

// Кольчатое тело: диски-призмы стоят по y — поперёк бороздки, по кругу — с разрывами; торцы — кольца.
float grooves(vec3 p, vec3 n) {
	if (abs(n.y) > 0.9) {
		return mod(floor(length(p.xz) / px), 3.0) == 0.0 ? 0.85 : 1.0;
	}
	vec2 q = floor(face_uv(p, n) / px);
	if (mod(q.y, 3.0) == 0.0 && hash2(vec2(floor(q.x / 2.0), q.y)) > 0.25) {
		return 0.8;
	}
	return hash2(q + 7.3) > 0.95 ? 1.15 : 1.0;
}

// Чешуя: ряды по два текселя, сдвиг через ряд; чешуйка — три текселя, нижний ряд — тень, угол — блик.
float scales(vec3 p, vec3 n) {
	vec2 q = floor(face_uv(p, n) / px);
	float row = floor(q.y / 2.0);
	float x = q.x + mod(row, 2.0) * 1.5;
	float fx = mod(floor(x), 3.0);
	float fy = mod(q.y, 2.0);
	if (fy == 0.0) {
		return fx == 1.0 ? 1.0 : 0.82;
	}
	return fx == 0.0 ? 1.12 : 1.0;
}

float mud(vec3 p) {
	vec3 q = floor(p / px);
	float clod = hash3(q + 11.0);                     // комок — в пиксель, как и всё вокруг
	float r = hash3(q);
	if (r > 0.93) {
		return 1.3;                                   // мокрая блёстка
	}
	return clod > 0.78 ? 0.84 : (clod < 0.2 ? 1.08 : 1.0);
}

float pebble(vec3 p) {
	vec3 q = floor(p / (px * 2.0));
	float r = hash3(q);
	return r < 0.25 ? 0.86 : (r < 0.5 ? 0.95 : (r < 0.8 ? 1.03 : 1.12));
}

// Хитин: по сетке грани (трубы скакуна — узкие плоские грани) пластины 2×2 пикселя разной яркости, нижний
// ряд пластины — тёмный шов; на гранях, глядящих вверх, — редкие светлые пиксели отлива.
float chitin(vec3 p, vec3 n) {
	vec2 q = floor(face_uv(p, n) / px);
	if (n.y > 0.45 && hash2(q + 5.7) > 0.74) {
		return 1.65;                                  // отлив
	}
	float r = hash2(floor(q / 2.0) + 3.1);
	float tone = r < 0.35 ? 0.85 : (r < 0.8 ? 1.0 : 1.2);
	return mod(q.y, 2.0) == 0.0 ? tone * 0.78 : tone;     // шов между поясами пластин
}

float body_detail(vec3 p, vec3 n, vec2 uv, vec2 uv2, vec4 col, vec4 rect0, vec4 rect1) {
	if (pattern == 1) {
		return plates(uv, uv2, n, round(col.rg * 16.0), rect0, rect1);
	} else if (pattern == 2) {
		return track(p, n);
	} else if (pattern == 3) {
		return skirt(p);
	} else if (pattern == 4) {
		return scutes(p);
	} else if (pattern == 5) {
		return hide(p);
	} else if (pattern == 6) {
		return grooves(p, n);
	} else if (pattern == 7) {
		return scales(p, n);
	} else if (pattern == 8) {
		return mud(p);
	} else if (pattern == 9) {
		return pebble(p);
	} else if (pattern == 10) {
		return chitin(p, n);
	}
	return 1.0;
}

void fragment() {
#ifdef FACE_DETAILS
	vec4 rect0 = detail0;
	vec4 rect1 = detail1;
#else
	vec4 rect0 = vec4(0.0);
	vec4 rect1 = vec4(0.0);
#endif
	vec3 tint = base_color.rgb;
	if (vertex_tint) {
		vec3 c = COLOR.rgb;
		if (!OUTPUT_IS_SRGB) {
			c = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
		}
		tint *= c;
	}
	ALBEDO = tint * body_detail(obj_pos, obj_nrm, UV, UV2, COLOR, rect0, rect1);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
}
