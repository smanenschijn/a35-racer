class_name Tex
## Procedural textures (port of src/track/textures.ts and the canvas textures in CarModel.ts).
## Each one is drawn like a 2D canvas in a SubViewport that renders once; the returned ImageTexture
## is a placeholder until flush() has copied the pixels in, so materials can use it right away.

static var host: Node
static var _pending: Array = [] # [viewport, texture, mipmaps]
static var _cache := {}
static var font_sign: Font
static var font_banner: Font


class Painter:
	extends Control
	var fn: Callable

	func _draw() -> void:
		fn.call(self)


## Queue a w×h texture drawn by fn(canvas: Control).
static func paint(w: int, h: int, fn: Callable, mipmaps := true, transparent := false) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 0.0 if transparent else 1.0))
	var tex := ImageTexture.create_from_image(img)
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.disable_3d = true
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := Painter.new()
	c.fn = fn
	c.size = Vector2(w, h)
	vp.add_child(c)
	host.add_child(vp)
	_pending.append([vp, tex, mipmaps])
	return tex


## Wait until every queued texture has been rendered and copied.
static func flush() -> void:
	if _pending.is_empty():
		return
	var jobs := _pending
	_pending = []
	if DisplayServer.get_name() == "headless":
		# Nothing gets drawn without a GPU (tests): keep the grey placeholders.
		for j in jobs:
			j[0].queue_free()
		return
	await RenderingServer.frame_post_draw
	for j in jobs:
		var vp: SubViewport = j[0]
		var img := vp.get_texture().get_image()
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			if j[2]:
				img.generate_mipmaps()
			(j[1] as ImageTexture).set_image(img)
		vp.queue_free()


static func cached(key: String, w: int, h: int, fn: Callable, mipmaps := true, transparent := false) -> ImageTexture:
	if not _cache.has(key):
		_cache[key] = paint(w, h, fn, mipmaps, transparent)
	return _cache[key]


static func _fonts() -> void:
	if font_sign == null:
		font_sign = load("res://assets/fonts/LiberationSans-Bold.ttf")
		font_banner = load("res://assets/fonts/Bangers-Regular.ttf")


static func _noise(c: Control, w: float, h: float, amount: int, alpha: float) -> void:
	for i in amount:
		var v := randf()
		c.draw_rect(Rect2(randf() * w, randf() * h, 1 + randf() * 2, 1 + randf() * 2), Color(v, v, v, alpha))


static func _text(c: Control, font: Font, text: String, x: float, y: float, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var px := x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		width = 2000.0
		px = x - 1000.0
	c.draw_string(font, Vector2(px, y), text, align, width, size, col)


## Carriageway texture: u spans the asphalt (-PAVED..PAVED), v repeats every 12 m.
## Dutch motorway markings: solid edge lines, 3 m dash / 9 m gap between lanes, a wide hard shoulder.
static func road() -> ImageTexture:
	return cached("road", 1024, 512, func(c: Control) -> void:
		var W := 1024.0
		var H := 512.0
		var P := Config.PAVED
		c.draw_rect(Rect2(0, 0, W, H), Color("3b3c3f"))
		_noise(c, W, H, 52000, 0.08)
		var m := func(d: float) -> float: return (d + P) / (2.0 * P) * W
		_wheel_tracks(c, m, H)
		# Hard shoulder (and the strip left of the fast lane) a touch lighter, with patched asphalt.
		var e: Array = Config.LANE_EDGES
		c.draw_rect(Rect2(0, 0, m.call(e[0]), H), Color(120 / 255.0, 120 / 255.0, 110 / 255.0, 0.22))
		c.draw_rect(Rect2(m.call(e[2]), 0, W - m.call(e[2]), H), Color(120 / 255.0, 120 / 255.0, 110 / 255.0, 0.2))
		_patches(c, m, H, e[2] + 0.5, P - 0.6)
		var line := func(d: float, wid: float, dash: bool) -> void:
			var lw: float = m.call(wid) - m.call(0.0)
			c.draw_rect(Rect2(m.call(d) - lw / 2.0, 0, lw, H * 0.25 if dash else H), Color("e9e9e2"))
		line.call(e[0], 0.15, false)
		line.call(e[1], 0.15, true)
		line.call(e[2], 0.22, false)
		# Rumble dashes along the shoulder edge line.
		for k in 8:
			c.draw_rect(Rect2(m.call(e[2] + 0.25), k * H / 8.0, m.call(0.35) - m.call(0.0), H / 16.0), Color(0.85, 0.85, 0.8, 0.35))
	)


## Single-carriageway N-road (N35): edge lines, and the Dutch "groene as" in the centre:
## two solid lines with green paint between them, paved verges outside. Same width/UV layout as road().
static func single_road() -> ImageTexture:
	return cached("single_road", 1024, 512, func(c: Control) -> void:
		var W := 1024.0
		var H := 512.0
		var P := Config.PAVED
		c.draw_rect(Rect2(0, 0, W, H), Color("3e3f42"))
		_noise(c, W, H, 52000, 0.08)
		var m := func(d: float) -> float: return (d + P) / (2.0 * P) * W
		_wheel_tracks(c, m, H)
		var e: Array = Config.LANE_EDGES
		# Paved verges (redresseerstroken) in a lighter, older asphalt.
		c.draw_rect(Rect2(0, 0, m.call(e[0]), H), Color(130 / 255.0, 125 / 255.0, 112 / 255.0, 0.3))
		c.draw_rect(Rect2(m.call(e[2]), 0, W - m.call(e[2]), H), Color(130 / 255.0, 125 / 255.0, 112 / 255.0, 0.3))
		_patches(c, m, H, e[2] + 0.4, P - 0.5)
		_patches(c, m, H, -P + 0.5, e[0] - 0.4)
		var mid: float = e[1]
		c.draw_rect(Rect2(m.call(mid - 0.25), 0, m.call(mid + 0.25) - m.call(mid - 0.25), H), Color("3f7d3a"))
		var line := func(d: float, wid: float) -> void:
			var lw: float = m.call(wid) - m.call(0.0)
			c.draw_rect(Rect2(m.call(d) - lw / 2.0, 0, lw, H), Color("e9e9e2"))
		line.call(mid - 0.25, 0.12)
		line.call(mid + 0.25, 0.12)
		# Edge lines: dashed (blokmarkering) as on Dutch N-roads.
		for d in [e[0], e[2]]:
			for k in 4:
				var lw: float = m.call(0.15) - m.call(0.0)
				c.draw_rect(Rect2(m.call(d) - lw / 2.0, k * H / 4.0, lw, H / 4.0 * 0.75), Color("e9e9e2"))
	)


## Darker wheel tracks in the middle of each lane.
static func _wheel_tracks(c: Control, m: Callable, H: float) -> void:
	var w05: float = m.call(0.5) - m.call(0.0)
	for lane in Config.LANE_CENTERS:
		c.draw_rect(Rect2(m.call(lane - 1.1), 0, w05, H), Color(20 / 255.0, 20 / 255.0, 22 / 255.0, 0.18))
		c.draw_rect(Rect2(m.call(lane + 0.6), 0, w05, H), Color(20 / 255.0, 20 / 255.0, 22 / 255.0, 0.18))


## Asphalt repairs and tar seams between d0 and d1.
static func _patches(c: Control, m: Callable, H: float, d0: float, d1: float) -> void:
	for i in 5:
		var x: float = m.call(d0 + randf() * (d1 - d0))
		var w: float = (m.call(1.2) - m.call(0.0)) * (0.5 + randf())
		c.draw_rect(Rect2(x - w / 2, randf() * H, w, 20 + randf() * 90), Color(0.1, 0.1, 0.11, 0.25))
	for i in 3:
		var x: float = m.call(d0 + randf() * (d1 - d0))
		var y := randf() * H
		var pts := PackedVector2Array()
		for k in 6:
			pts.append(Vector2(x + (randf() - 0.5) * 30, y + k * 22))
		c.draw_polyline(pts, Color(0.06, 0.06, 0.07, 0.5), 2.0)


static func grass() -> ImageTexture:
	return cached("grass", 256, 256, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 256, 256), Color("4f6f2a"))
		for i in 9000:
			c.draw_rect(Rect2(randf() * 256, randf() * 256, 1, 2 + randf() * 3),
				Color.from_hsv((70 + randf() * 40) / 360.0, 0.45, 0.25 + randf() * 0.2, 0.5))
	)


## Large-scale patchwork of Twente fields, used on the ground plane.
static func field() -> ImageTexture:
	return cached("field", 1024, 1024, func(c: Control) -> void:
		var colors := ["5a7a2e", "6b8a35", "4e6b28", "8a8a3a", "6f7f30", "7d6a3c", "557833"]
		for y in range(0, 1024, 128):
			for x in range(0, 1024, 128):
				var ox := randf() * 30 - 15
				c.draw_rect(Rect2(x + ox, y, 128 + 30, 128), Color(colors[randi() % colors.size()]))
		for i in range(0, 1025, 128):
			c.draw_line(Vector2(i, 0), Vector2(i, 1024), Color(40 / 255.0, 55 / 255.0, 20 / 255.0, 0.6), 3)
			c.draw_line(Vector2(0, i), Vector2(1024, i), Color(40 / 255.0, 55 / 255.0, 20 / 255.0, 0.6), 3)
		_noise(c, 1024, 1024, 60000, 0.05)
	)


static func concrete() -> ImageTexture:
	return cached("concrete", 256, 256, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 256, 256), Color("9c9a94"))
		_noise(c, 256, 256, 12000, 0.12)
	)


static func checker() -> ImageTexture:
	return cached("checker", 256, 64, func(c: Control) -> void:
		for y in 2:
			for x in 8:
				c.draw_rect(Rect2(x * 32, y * 32, 32, 32), Color("111111") if (x + y) % 2 else Color("f2f2f2"))
	, false)


## Blue Dutch motorway sign (ANWB style) with a red route shield.
static func sign(lines: Array, route: String) -> ImageTexture:
	_fonts()
	return cached("sign|%s|%s" % ["|".join(lines), route], 512, 256, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 512, 256), Color("123f8c"))
		c.draw_rect(Rect2(10, 10, 492, 236), Color("f2f2f2"), false, 6)
		for i in lines.size():
			c.draw_set_transform(Vector2(36, 90 + i * 72), 0, Vector2(0.86, 1))
			_text(c, font_sign, lines[i], 0, 0, 54, Color.WHITE)
		c.draw_set_transform(Vector2.ZERO)
		# Route shield
		c.draw_rect(Rect2(390, 168, 96, 56), Color("c4161c"))
		c.draw_rect(Rect2(392, 170, 92, 52), Color.WHITE, false, 4)
		_text(c, font_sign, route, 438, 210, 38, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		# Arrow
		c.draw_colored_polygon(PackedVector2Array([Vector2(438, 40), Vector2(468, 80), Vector2(448, 80), Vector2(448, 140),
			Vector2(428, 140), Vector2(428, 80), Vector2(408, 80)]), Color.WHITE)
	)


## Dutch place-name sign: blue with white border.
static func place_sign(place: String, sub := "") -> ImageTexture:
	_fonts()
	return cached("place|%s|%s" % [place, sub], 512, 224, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 512, 224), Color("123f8c"))
		c.draw_rect(Rect2(14, 14, 484, 196), Color.WHITE, false, 10)
		var size := 78
		while size > 40 and font_sign.get_string_size(place, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.86 > 460:
			size -= 4
		c.draw_set_transform(Vector2(256, 120 if sub != "" else 140), 0, Vector2(0.86, 1))
		_text(c, font_sign, place, 0, 0, size, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		c.draw_set_transform(Vector2.ZERO)
		if sub != "":
			_text(c, font_sign, sub, 256, 180, 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	)


static func banner(text: String) -> ImageTexture:
	_fonts()
	return cached("banner|" + text, 1024, 160, func(c: Control) -> void:
		c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1024, 0), Vector2(1024, 160), Vector2(0, 160)]),
			PackedColorArray([Color("ff3d00"), Color("ffb300"), Color("ffb300"), Color("ff3d00")]))
		for x in range(0, 1024, 40):
			var odd := (x / 40) % 2 == 1
			c.draw_rect(Rect2(x, 0, 40, 18), Color("111111") if odd else Color.WHITE)
			c.draw_rect(Rect2(x, 142, 40, 18), Color.WHITE if odd else Color("111111"))
		var size := 104
		while size > 50 and font_banner.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > 960:
			size -= 4
		var w := font_banner.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		c.draw_string_outline(font_banner, Vector2(512 - w / 2, 118), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 16, Color("111111"))
		c.draw_string(font_banner, Vector2(512 - w / 2, 118), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
	, false)


## Guard rail (W-profile): u runs bottom → top across the beam, v along the road. Light and shadow
## bands fake the corrugation; a dull galvanised finish with streaks of road dirt.
static func rail() -> ImageTexture:
	return cached("rail", 64, 256, func(c: Control) -> void:
		var bands := [[0.0, 0.12, 0.55], [0.12, 0.3, 0.95], [0.3, 0.42, 0.62], [0.42, 0.58, 0.4], [0.58, 0.7, 0.62],
			[0.7, 0.88, 1.0], [0.88, 1.0, 0.6]]
		for b in bands:
			var v: float = b[2]
			c.draw_rect(Rect2(b[0] * 64.0, 0, (b[1] - b[0]) * 64.0, 256), Color(0.72 * v, 0.74 * v, 0.76 * v))
		for i in 60:
			var y := randf() * 256
			c.draw_rect(Rect2(0, y, 64, 1 + randf() * 3), Color(0.25, 0.22, 0.18, 0.12 + randf() * 0.15))
		# Bolts where the sections overlap.
		for x in [18.0, 46.0]:
			c.draw_circle(Vector2(x, 128), 2.5, Color(0.3, 0.3, 0.32))
	)


## Soft dark blob for under a car (contact shadow).
static func blob() -> ImageTexture:
	return cached("blob", 64, 64, func(c: Control) -> void:
		for i in 16:
			var k := 1.0 - i / 16.0
			c.draw_rect(Rect2(32 - 30 * k, 32 - 30 * k, 60 * k, 60 * k), Color(0, 0, 0, 0.07))
	, true, true)


## ANWB direction sign before a junction: blue, white text, an arrow per side road.
static func direction_sign(left: String, right: String) -> ImageTexture:
	_fonts()
	return cached("dir|%s|%s" % [left, right], 512, 256, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 512, 256), Color("123f8c"))
		c.draw_rect(Rect2(8, 8, 496, 240), Color("f2f2f2"), false, 5)
		var rows := []
		if left != "":
			rows.append([left, -1])
		if right != "":
			rows.append([right, 1])
		for i in rows.size():
			var y := 92 + i * 96 if rows.size() > 1 else 140
			var txt: String = rows[i][0]
			var size := 50
			while size > 26 and font_sign.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.86 > 330:
				size -= 2
			c.draw_set_transform(Vector2(120, y), 0, Vector2(0.86, 1))
			_text(c, font_sign, txt, 0, 0, size, Color.WHITE)
			c.draw_set_transform(Vector2.ZERO)
			# Arrow pointing to the side the road leaves on.
			var ax := 60.0 if rows[i][1] < 0 else 452.0
			var dir := float(rows[i][1])
			c.draw_colored_polygon(PackedVector2Array([Vector2(ax + dir * 34, y - 18), Vector2(ax, y - 44), Vector2(ax, y - 30),
				Vector2(ax - dir * 34, y - 30), Vector2(ax - dir * 34, y - 6), Vector2(ax, y - 6), Vector2(ax, y + 8)]), Color.WHITE)
	)


## Road works board on a closed slip road: red/white with "AFGESLOTEN".
static func closed_sign() -> ImageTexture:
	_fonts()
	return cached("closed", 512, 256, func(c: Control) -> void:
		for i in 12:
			var x := i * 48.0
			c.draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 24, 0), Vector2(x + 24 - 60, 64), Vector2(x - 60, 64)]), Color("d71920"))
		c.draw_rect(Rect2(0, 0, 512, 64), Color(1, 1, 1, 0.0))
		c.draw_rect(Rect2(0, 64, 512, 192), Color("f7d117"))
		c.draw_rect(Rect2(6, 70, 500, 180), Color("111111"), false, 6)
		_text(c, font_sign, "AFGESLOTEN", 256, 160, 74, Color("111111"), HORIZONTAL_ALIGNMENT_CENTER)
		_text(c, font_sign, "volg de race", 256, 224, 40, Color("111111"), HORIZONTAL_ALIGNMENT_CENTER)
	)


## Red/white striped barrier board (hekwerk) and the chevrons on an arrow trailer.
static func barrier_stripes() -> ImageTexture:
	return cached("barrier", 256, 64, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 256, 64), Color.WHITE)
		for i in 10:
			var x := i * 52.0 - 40
			c.draw_colored_polygon(PackedVector2Array([Vector2(x, 64), Vector2(x + 26, 64), Vector2(x + 52, 0), Vector2(x + 26, 0)]), Color("d71920"))
	)


## A brand board (petrol station, snack bar): big letters on a colour.
static func brand(text: String, bg: Color, fg: Color) -> ImageTexture:
	_fonts()
	return cached("brand|%s|%s" % [text, bg.to_html()], 512, 256, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 512, 256), bg)
		c.draw_rect(Rect2(10, 10, 492, 236), fg, false, 8)
		var size := 120
		while size > 40 and font_banner.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > 460:
			size -= 4
		var w := font_banner.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		c.draw_string(font_banner, Vector2(256 - w / 2, 128 + size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fg)
	)


## Apartment/office facade: a window grid, some windows lit (returns [colour map, emission map]).
static func facade(seed_value: int, wall: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 9301 + 49297
	var lit := []
	for i in 72:
		lit.append(rng.randf() < 0.35)
	var draw_grid := func(c: Control, glow: bool) -> void:
		var W := 128.0
		var H := 256.0
		if glow:
			c.draw_rect(Rect2(0, 0, W, H), Color.BLACK)
		else:
			c.draw_rect(Rect2(0, 0, W, H), Color(wall))
			_noise(c, W, H, 1500, 0.06)
		for y in 12:
			for x in 6:
				var px := 6 + x * (W - 12) / 6.0
				var py := 6 + y * (H - 12) / 12.0
				var w := (W - 12) / 6.0 - 6
				var h := (H - 12) / 12.0 - 8
				var on: bool = lit[y * 6 + x]
				if glow:
					if on:
						c.draw_rect(Rect2(px, py, w, h), Color("ffb860"))
				else:
					c.draw_rect(Rect2(px, py, w, h), Color("ffd9a0") if on else Color("1c2733"))
	var map := cached("facade%d" % seed_value, 128, 256, func(c: Control) -> void: draw_grid.call(c, false))
	var glow := cached("facade_glow%d" % seed_value, 128, 256, func(c: Control) -> void: draw_grid.call(c, true))
	return [map, glow]


## Dutch number plate: yellow with the blue NL strip.
static func plate(text: String) -> ImageTexture:
	_fonts()
	return cached("plate|" + text, 256, 56, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, 256, 56), Color("f4c400"))
		c.draw_rect(Rect2(0, 0, 30, 56), Color("1b3fa0"))
		_text(c, font_sign, "NL", 6, 48, 14, Color("f4c400"))
		var size := 38
		while size > 20 and font_sign.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.86 > 214:
			size -= 2
		c.draw_set_transform(Vector2(143, 42), 0, Vector2(0.86, 1))
		_text(c, font_sign, text, 0, 0, size, Color("111111"), HORIZONTAL_ALIGNMENT_CENTER)
		c.draw_set_transform(Vector2.ZERO)
		c.draw_rect(Rect2(1.5, 1.5, 253, 53), Color("111111"), false, 3)
	)


## Lettering for liveries and trailers.
static func text(label: String, bg: Color, fg: Color, w := 512, h := 128, size := 72, italic := false) -> ImageTexture:
	_fonts()
	return cached("text|%s|%s|%s|%d|%d|%d" % [label, bg.to_html(), fg.to_html(), w, h, size], w, h, func(c: Control) -> void:
		c.draw_rect(Rect2(0, 0, w, h), bg)
		var s := size
		while s > 16 and font_sign.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > w * 0.94:
			s -= 4
		var tw := font_sign.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
		var skew := Transform2D(Vector2(1, 0), Vector2(-0.2 if italic else 0.0, 1), Vector2(w / 2.0, h / 2.0 + s * 0.36))
		c.draw_set_transform_matrix(skew)
		c.draw_string(font_sign, Vector2(-tw / 2, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, s, fg)
		c.draw_set_transform(Vector2.ZERO)
	)
