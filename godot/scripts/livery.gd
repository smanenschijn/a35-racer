class_name Livery
## Racing liveries: stickers, start numbers, stripes and sponsor decals per driver, painted once into a
## texture the car shader projects onto the body (see shaders/car.gdshader).
##
## Layout (1024×1024): top half is the side view (x = rear → front, y = roof → sill), bottom half is seen
## from above (x = rear → front, y = left → right side of the car). Everything is drawn in metres through
## the Ctx helpers, so the stickers keep their shape on long and short cars alike.

const SIZE := 1024

static var _cache := {}


## Mapping from body metres to texture pixels for one car.
class Ctx:
	var c: Control
	var z0: float # body rear (m)
	var z1: float # body front
	var y0: float # sill
	var y1: float # roof
	var hw: float # half width
	var font_num: Font
	var font_txt: Font
	var font_fun: Font

	func sx(z: float) -> float:
		return (z - z0) / (z1 - z0) * SIZE

	func sy(y: float) -> float:
		return (y1 - y) / (y1 - y0) * SIZE * 0.5

	func ty(x: float) -> float:
		return SIZE * 0.5 + (hw - x) / (2.0 * hw) * SIZE * 0.5

	## Pixels per metre along the car, across the side band and across the top band.
	func ppm_z() -> float:
		return SIZE / (z1 - z0)

	func ppm_y() -> float:
		return SIZE * 0.5 / (y1 - y0)

	func ppm_x() -> float:
		return SIZE * 0.5 / (2.0 * hw)

	func side_rect(za: float, zb: float, ya: float, yb: float, col: Color) -> void:
		c.draw_rect(Rect2(Vector2(sx(minf(za, zb)), sy(maxf(ya, yb))), Vector2(absf(sx(zb) - sx(za)), absf(sy(ya) - sy(yb)))), col)

	func top_rect(za: float, zb: float, xa: float, xb: float, col: Color) -> void:
		c.draw_rect(Rect2(Vector2(sx(minf(za, zb)), ty(maxf(xa, xb))), Vector2(absf(sx(zb) - sx(za)), absf(ty(xa) - ty(xb)))), col)

	## A slanted band along the side (parallelogram), slant in metres.
	func side_band(za: float, zb: float, ya: float, yb: float, slant: float, col: Color) -> void:
		var pts := PackedVector2Array([
			Vector2(sx(za), sy(ya)), Vector2(sx(zb), sy(ya)), Vector2(sx(zb + slant), sy(yb)), Vector2(sx(za + slant), sy(yb))])
		c.draw_colored_polygon(pts, col)

	## Text on the side, centred at (z, y), h metres tall, at most w metres wide.
	func side_text(text: String, z: float, y: float, h: float, col: Color, font: Font, w := 99.0, outline := Color(0, 0, 0, 0)) -> void:
		var px := int(h * ppm_y() * 1.25)
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		# The side band is squashed along the car: draw in vertical pixels, then scale x.
		var k := ppm_z() / ppm_y()
		var scale := minf(1.0, (w * ppm_z()) / maxf(1.0, size.x * k))
		c.draw_set_transform(Vector2(sx(z), sy(y)), 0.0, Vector2(k * scale, scale))
		var at := Vector2(-size.x / 2.0, font.get_ascent(px) / 2.0 - font.get_descent(px) * 0.4)
		if outline.a > 0:
			c.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(2, px / 7), outline)
		c.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
		c.draw_set_transform(Vector2.ZERO)

	## Text on the bonnet or roof, readable from the chase camera (glyphs point forward).
	func top_text(text: String, z: float, x: float, h: float, col: Color, font: Font, w := 99.0, outline := Color(0, 0, 0, 0)) -> void:
		var px := int(h * ppm_z() * 1.25)
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		var k := ppm_x() / ppm_z()
		var scale := minf(1.0, (w * ppm_x()) / maxf(1.0, size.x * k))
		# Rotated a quarter turn: glyph up = forward (+x in the texture), reading left to right across the car.
		c.draw_set_transform_matrix(Transform2D(Vector2(0, k * scale), Vector2(-scale, 0), Vector2(sx(z), ty(x))))
		var at := Vector2(-size.x / 2.0, font.get_ascent(px) / 2.0 - font.get_descent(px) * 0.4)
		if outline.a > 0:
			c.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(2, px / 7), outline)
		c.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
		c.draw_set_transform(Vector2.ZERO)

	## Round start-number plate on the door.
	func side_roundel(z: float, y: float, r: float, bg: Color, fg: Color, num: String, ring := Color.BLACK) -> void:
		var k := ppm_z() / ppm_y()
		c.draw_set_transform(Vector2(sx(z), sy(y)), 0.0, Vector2(k, 1.0))
		c.draw_circle(Vector2.ZERO, r * ppm_y() * 1.08, ring)
		c.draw_circle(Vector2.ZERO, r * ppm_y(), bg)
		c.draw_set_transform(Vector2.ZERO)
		side_text(num, z, y, r * 1.15, fg, font_num, r * 1.7)

	func top_roundel(z: float, x: float, r: float, bg: Color, fg: Color, num: String, ring := Color.BLACK) -> void:
		var k := ppm_x() / ppm_z()
		c.draw_set_transform(Vector2(sx(z), ty(x)), 0.0, Vector2(1.0, k))
		c.draw_circle(Vector2.ZERO, r * ppm_z() * 1.08, ring)
		c.draw_circle(Vector2.ZERO, r * ppm_z(), bg)
		c.draw_set_transform(Vector2.ZERO)
		top_text(num, z, x, r * 1.15, fg, font_num, r * 1.7)

	## A rectangular sponsor sticker with a border.
	func sticker(text: String, z: float, y: float, w: float, h: float, bg: Color, fg: Color, font: Font) -> void:
		side_rect(z - w / 2 - 0.015, z + w / 2 + 0.015, y - h / 2 - 0.012, y + h / 2 + 0.012, Color(1, 1, 1, 0.95))
		side_rect(z - w / 2, z + w / 2, y - h / 2, y + h / 2, bg)
		side_text(text, z, y, h * 0.62, fg, font, w * 0.9)

	## Licks of flame from the nose backwards, between heights ya and yb.
	func side_flames(z_from: float, length: float, ya: float, yb: float, outer: Color, inner: Color) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 35
		for layer in 2:
			var col := outer if layer == 0 else inner
			var shrink := 1.0 if layer == 0 else 0.6
			var tongues := 6
			for i in tongues:
				var yc := ya + (yb - ya) * (i + 0.5) / tongues
				var half := (yb - ya) / tongues * 0.9 * shrink
				var reach := length * (0.55 + rng.randf() * 0.45) * shrink
				# Upper edge out to the tip, lower edge back: both follow the same wavy centre line.
				var pts := PackedVector2Array()
				var steps := 10
				for k in steps + 1:
					var tt := float(k) / steps
					var cy := yc + sin(tt * 6.0 + i) * half * 0.4 * tt
					pts.append(Vector2(sx(z_from - reach * tt), sy(cy + half * pow(1.0 - tt, 0.8))))
				for k in range(steps - 1, -1, -1):
					var tt := float(k) / steps
					var cy := yc + sin(tt * 6.0 + i) * half * 0.4 * tt
					pts.append(Vector2(sx(z_from - reach * tt), sy(cy - half * pow(1.0 - tt, 0.8))))
				c.draw_colored_polygon(pts, col)

	## A checkered band along the side.
	func side_checker(za: float, zb: float, ya: float, yb: float, cell: float, col: Color) -> void:
		var rows := maxi(1, roundi((yb - ya) / cell))
		var h := (yb - ya) / rows
		var z := za
		var i := 0
		while z < zb:
			for r in rows:
				if (i + r) % 2 == 0:
					side_rect(z, minf(zb, z + h), ya + r * h, ya + (r + 1) * h, col)
			z += h
			i += 1


## Livery texture for a racer, or null for plain cars (traffic, police).
## box = (z min, z max, y min, y max) of the painted body in body space, hw = half width.
static func for_car(id: String, box: Vector4, hw: float) -> Texture2D:
	if not DESIGNS.has(id):
		return null
	var key := "%s|%.2f|%.2f" % [id, box.y - box.x, box.w]
	if _cache.has(key):
		return _cache[key]
	Tex._fonts()
	var num_font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var tex := Tex.paint(SIZE, SIZE, func(c: Control) -> void:
		var x := Ctx.new()
		x.c = c
		x.z0 = box.x
		x.z1 = box.y
		x.y0 = box.z
		x.y1 = box.w
		x.hw = hw
		x.font_num = num_font
		x.font_txt = Tex.font_sign
		x.font_fun = Tex.font_banner
		c.draw_rect(Rect2(0, 0, SIZE, SIZE), Color(0, 0, 0, 0))
		Callable(Livery, DESIGNS[id]).call(x)
	, true, true)
	_cache[key] = tex
	return tex


const DESIGNS := {
	"rx": "_rx", "supremo": "_supremo", "golv": "_golv", "civik": "_civik", "corso": "_corso",
	"spacewagen": "_spacewagen", "calibro": "_calibro", "volvi": "_volvi",
}

const WHITE := Color(0.96, 0.96, 0.94)
const BLACK := Color(0.05, 0.05, 0.06)
const ORANGE := Color("ff7a00")
const YELLOW := Color("ffd400")


## Door centre and the band the stickers live in (metres).
static func _door(x: Ctx) -> float:
	return (x.z0 + x.z1) / 2.0 - 0.12


## The player: A35 Racer works team, number 35, white and black stripes.
static func _rx(x: Ctx) -> void:
	var d := _door(x)
	x.side_band(x.z0 + 0.2, x.z1 - 0.15, 0.33, 0.44, -0.25, WHITE)
	x.side_band(x.z0 + 0.25, x.z1 - 0.2, 0.45, 0.48, -0.25, BLACK)
	x.side_roundel(d, 0.58, 0.2, WHITE, BLACK, "35")
	x.sticker("GAS GEAVEN!", x.z1 - 0.62, 0.66, 0.6, 0.11, YELLOW, BLACK, x.font_fun)
	x.sticker("SALLAND OLIE", x.z0 + 0.55, 0.66, 0.55, 0.09, BLACK, YELLOW, x.font_txt)
	x.side_text("A35 RACER", d, 0.385, 0.08, BLACK, x.font_fun, 1.2)
	# Bonnet and roof: twin stripes and the number.
	for side in [-1.0, 1.0]:
		x.top_rect(x.z0, x.z1, side * 0.12, side * 0.3, WHITE)
	x.top_roundel(d + 0.05, 0.0, 0.26, WHITE, BLACK, "35")
	x.top_text("TUKKER POWER", x.z1 - 0.45, 0.0, 0.11, BLACK, x.font_fun, 1.0)


## Sanne: yellow Supremo with a black checkered band, number 1, Grolsj sponsorship.
static func _supremo(x: Ctx) -> void:
	var d := _door(x)
	x.side_checker(x.z0 + 0.3, x.z1 - 0.25, 0.3, 0.4, 0.05, BLACK)
	x.side_roundel(d, 0.58, 0.19, BLACK, YELLOW, "1", WHITE)
	x.sticker("GROLSJ", x.z1 - 0.6, 0.66, 0.5, 0.11, Color("0b6b2e"), WHITE, x.font_fun)
	x.sticker("ENSCHEDE SPEED", x.z0 + 0.6, 0.66, 0.65, 0.09, BLACK, YELLOW, x.font_txt)
	x.side_text("SANNE", d, 0.79, 0.07, BLACK, x.font_txt, 0.6)
	x.top_rect(x.z0, x.z1, -0.08, 0.08, BLACK)
	x.top_roundel(d + 0.05, 0.0, 0.26, BLACK, YELLOW, "1", WHITE)


## Henk-Jan: blue Golv G60 with flames licking back from the nose.
static func _golv(x: Ctx) -> void:
	var d := _door(x)
	x.side_flames(x.z1 - 0.1, 1.7, 0.32, 0.72, ORANGE, YELLOW)
	x.side_roundel(d - 0.15, 0.6, 0.17, WHITE, Color("1d4fd8"), "60")
	x.sticker("G60 TUNING", x.z0 + 0.5, 0.66, 0.55, 0.1, BLACK, Color("29c5ff"), x.font_txt)
	x.side_text("HENK-JAN", d - 0.15, 0.36, 0.07, WHITE, x.font_fun, 0.7)
	for side in [-1.0, 1.0]:
		x.top_rect(x.z1 - 1.3, x.z1, side * 0.15, side * 0.26, ORANGE)
	x.top_text("G60", x.z1 - 0.4, 0.0, 0.18, YELLOW, x.font_fun, 0.6, BLACK)


## Joost: UT student, JDM stickers everywhere.
static func _civik(x: Ctx) -> void:
	var d := _door(x)
	for i in 3:
		x.side_band(x.z0 + 0.4 + i * 0.16, x.z0 + 0.48 + i * 0.16, 0.32, 0.7, 0.35, Color("ff2d8b") if i % 2 == 0 else WHITE)
	x.side_roundel(d + 0.1, 0.58, 0.17, WHITE, BLACK, "01", Color("ff2d8b"))
	x.sticker("UT RACING", x.z1 - 0.6, 0.66, 0.52, 0.1, Color("e4002b"), WHITE, x.font_fun)
	x.sticker("YOLO", x.z1 - 0.95, 0.42, 0.28, 0.09, YELLOW, BLACK, x.font_fun)
	x.sticker("STUDENTENKORTING", d + 0.1, 0.36, 0.7, 0.07, BLACK, WHITE, x.font_txt)
	x.top_text("TENTAMEN? NEE!", x.z1 - 0.4, 0.0, 0.1, BLACK, x.font_fun, 1.1)
	x.top_roundel(d + 0.1, 0.0, 0.22, WHITE, BLACK, "01", Color("ff2d8b"))


## Mehmet: orange Corso in full Thuisbesteld.nl delivery colours.
static func _corso(x: Ctx) -> void:
	var d := _door(x)
	x.side_rect(x.z0 + 0.15, x.z1 - 0.15, 0.4, 0.66, WHITE)
	x.side_text("Thuisbesteld.nl", d + 0.05, 0.53, 0.15, ORANGE, x.font_fun, x.z1 - x.z0 - 0.9)
	x.side_text("SNEL BEZORGD!", d, 0.34, 0.06, WHITE, x.font_txt, 1.0)
	x.side_roundel(x.z1 - 0.6, 0.73, 0.1, BLACK, WHITE, "24")
	x.top_rect(x.z0 + 0.4, x.z1 - 0.3, -0.35, 0.35, WHITE)
	x.top_text("THUISBESTELD", d, 0.0, 0.17, ORANGE, x.font_fun, 1.5)


## Tante Riek: flowers, hearts and bumper stickers on the purple Space Wagen.
static func _spacewagen(x: Ctx) -> void:
	var d := _door(x)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1953
	var cols := [Color("ffd1e8"), YELLOW, Color("ffffff"), Color("ff8fc8")]
	for i in 14:
		var z := x.z0 + 0.3 + rng.randf() * (x.z1 - x.z0 - 0.6)
		var y := 0.35 + rng.randf() * 0.35
		var r := 0.05 + rng.randf() * 0.05
		var k := x.ppm_z() / x.ppm_y()
		x.c.draw_set_transform(Vector2(x.sx(z), x.sy(y)), 0.0, Vector2(k, 1.0))
		for p in 5:
			var a := p * TAU / 5
			x.c.draw_circle(Vector2(cos(a), sin(a)) * r * x.ppm_y() * 0.9, r * x.ppm_y() * 0.6, cols[i % cols.size()])
		x.c.draw_circle(Vector2.ZERO, r * x.ppm_y() * 0.45, ORANGE)
		x.c.draw_set_transform(Vector2.ZERO)
	x.sticker("OMA AAN BOORD", x.z0 + 0.6, 0.62, 0.62, 0.09, Color("ffd1e8"), Color("8a1c5c"), x.font_txt)
	x.sticker("IK REM OOK VOOR DIEREN", d, 0.36, 0.95, 0.07, WHITE, BLACK, x.font_txt)
	x.side_roundel(d + 0.35, 0.6, 0.15, WHITE, Color("b03a7a"), "7")
	x.top_text("NAAR DE JUMBO", d, 0.0, 0.14, Color("ffd1e8"), x.font_fun, 1.3)


## Bennie: black Calibro in Heraklus black and white.
static func _calibro(x: Ctx) -> void:
	var d := _door(x)
	x.side_rect(x.z0 + 0.1, x.z1 - 0.1, 0.32, 0.4, WHITE)
	x.side_rect(x.z0 + 0.1, x.z1 - 0.1, 0.44, 0.47, WHITE)
	x.side_roundel(d, 0.6, 0.18, WHITE, BLACK, "18")
	x.sticker("HERAKLUS ALMELO", x.z1 - 0.7, 0.68, 0.75, 0.1, WHITE, BLACK, x.font_fun)
	x.sticker("ERVE ASITOH", x.z0 + 0.55, 0.68, 0.55, 0.08, Color("d30f1c"), WHITE, x.font_txt)
	x.top_text("HERAKLUS", d, 0.0, 0.2, WHITE, x.font_fun, 1.4)


## Gerrit: green Volvi farm estate, contractor lettering and mud.
static func _volvi(x: Ctx) -> void:
	var d := _door(x)
	x.side_text("Loonbedrijf", d + 0.1, 0.66, 0.08, YELLOW, x.font_txt, 1.4)
	x.side_text("OUDE EGBERINK", d + 0.1, 0.55, 0.12, WHITE, x.font_fun, 1.9)
	x.side_text("Wierden  ·  06-1234 5678", d + 0.1, 0.45, 0.05, WHITE, x.font_txt, 1.6)
	x.sticker("KUMP WAL GOED", x.z0 + 0.5, 0.36, 0.55, 0.07, Color("5b3a1a"), WHITE, x.font_txt)
	# Mud flung up from the fields.
	var rng := RandomNumberGenerator.new()
	rng.seed = 240
	for i in 160:
		var z := x.z0 + rng.randf() * (x.z1 - x.z0)
		var y := 0.2 + pow(rng.randf(), 2.2) * 0.35
		x.c.draw_circle(Vector2(x.sx(z), x.sy(y)), 2 + rng.randf() * 7, Color(0.27, 0.19, 0.1, 0.55 + rng.randf() * 0.4))
	x.top_text("BOER ZOEKT VAART", d, 0.0, 0.12, YELLOW, x.font_fun, 1.5)
