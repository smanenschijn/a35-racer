class_name Hud
extends CanvasLayer
## In-race HUD built in code, styled like the web version (port of src/ui/Hud.ts + style.css).

signal reset_pressed

const YELLOW := Color("ffd400")
const ORANGE := Color("ff7a00")
const RED := Color("ff2a2a")
const BLUE := Color("1d6fff")
const INK := Color("0b0d14")
const PANEL := Color(8 / 255.0, 10 / 255.0, 20 / 255.0, 0.55)

var font_ui: Font
var font_big: Font
var font_text: Font
## Phone in landscape: smaller screen, bigger thumbs.
var compact := false
var touch := false

var root: Control
var _game: Control
var _pos_num: Label
var _pos_total: Label
var _standings: VBoxContainer
var _stage_name: Label
var _stage_info: Label
var _speed: Label
var _gauge: Gauge
var _dmg: DamageCar
var _dmg_pct: Label
var _nitro: Bar
var _bullet: Bar
var _ram_l: Label
var _ram_r: Label
var _clock_box: VBoxContainer
var _clock: Label
var _wanted: Label
var _bust: Bar
var _messages: VBoxContainer
var _countdown_box: Control
var _help: Label
var _side_l: Label
var _side_r: Label
var _look_back: Label
var _restart: PanelContainer
var _restart_label: Label
var _restart_bar: ColorRect
var _police_glow: PoliceGlow
var _flash: ColorRect
var _bullet_tint: TextureRect
var _now_playing: PanelContainer
var _now_title: Label
var _reset_btn: Button
var _reset_key := "F"
var _bl: Control
var _br: Control
var _last_pos := 0
var _last_stars := -1
var _t := 0.0


# ------------------------------------------------------------------ drawn widgets

class Gauge:
	extends Control
	var frac := 0.0
	var nitro := false

	func _draw() -> void:
		var c := Vector2(size.x / 2, size.y - 10)
		var r := size.x / 2 - 12
		draw_arc(c, r, PI, TAU, 48, Color(1, 1, 1, 0.12), 14, true)
		if frac > 0.002:
			var col := Color("36c6ff") if nitro else Color("ff7a00")
			draw_arc(c, r, PI, PI + PI * frac, 48, Color(col, 0.35), 22, true)
			draw_arc(c, r, PI, PI + PI * frac, 48, col, 14, true)


class DamageCar:
	extends Control
	var levels := {"front": 0.0, "rear": 0.0, "left": 0.0, "right": 0.0}

	static func zone_color(d: float) -> Color:
		# green → yellow → red
		var h := maxf(0.0, 120 - d * 1.2) / 360.0
		return Color.from_hsv(h, 0.9, 0.5 if d >= 100 else 0.95)

	func _draw() -> void:
		var k := size.x / 60.0
		var rects := {"front": Rect2(8, 2, 44, 22), "left": Rect2(2, 26, 12, 58), "right": Rect2(46, 26, 12, 58), "rear": Rect2(8, 86, 44, 22)}
		for z in rects:
			var r: Rect2 = rects[z]
			var rr := Rect2(r.position * k, r.size * k)
			var sb := StyleBoxFlat.new()
			sb.bg_color = zone_color(levels[z])
			sb.border_color = Color(0, 0, 0, 0.6)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(int(5 * k))
			draw_style_box(sb, rr)
		var cabin := StyleBoxFlat.new()
		cabin.bg_color = Color(1, 1, 1, 0.15)
		cabin.set_corner_radius_all(int(4 * k))
		draw_style_box(cabin, Rect2(Vector2(16, 30) * k, Vector2(28, 50) * k))


## Skewed meter with a label (nitro, slowmo, busted).
class Bar:
	extends Control
	var value := 0.0
	var fill_a := Color("0a5cff")
	var fill_b := Color("36c6ff")
	var border := Color(1, 1, 1, 0.6)
	var text := ""
	var font: Font
	var font_size := 11
	var glow := false
	var blink := false

	func _draw() -> void:
		var skew := Transform2D(Vector2(1, 0), Vector2(-0.32, 1), Vector2(size.y * 0.32, 0))
		draw_set_transform_matrix(skew)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
		var w := size.x * clampf(value, 0, 1)
		if w > 0:
			var a := fill_a
			var b := fill_b
			if blink and fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0:
				a = a.lightened(0.35)
				b = b.lightened(0.35)
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, size.y), Vector2(0, size.y)]),
				PackedColorArray([a, b, b, a]))
			if glow:
				draw_rect(Rect2(Vector2(-2, -2), Vector2(w + 4, size.y + 4)), Color(b, 0.35), false, 3)
		draw_rect(Rect2(Vector2.ZERO, size), border, false, 2)
		draw_set_transform(Vector2.ZERO)
		if text != "" and font != null:
			draw_string(font, Vector2(8, size.y / 2 + font_size * 0.38), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


## Blue/red flashing light from the screen edges while a siren is close.
class PoliceGlow:
	extends Control
	var on := false
	var alpha := 0.0

	func _draw() -> void:
		if alpha < 0.01:
			return
		var left := fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.0
		var w := 130.0
		var c := Color(40 / 255.0, 90 / 255.0, 1.0, 0.85 * alpha) if left else Color(1.0, 30 / 255.0, 30 / 255.0, 0.85 * alpha)
		var x0 := 0.0 if left else size.x - w
		var pts := PackedVector2Array([Vector2(x0, 0), Vector2(x0 + w, 0), Vector2(x0 + w, size.y), Vector2(x0, size.y)])
		var clear := Color(c, 0)
		var cols := PackedColorArray([c, clear, clear, c]) if left else PackedColorArray([clear, c, c, clear])
		draw_polygon(pts, cols)


# ------------------------------------------------------------------ build

func _ready() -> void:
	layer = 2
	font_ui = load("res://assets/fonts/RussoOne-Regular.ttf")
	font_big = load("res://assets/fonts/Bangers-Regular.ttf")
	font_text = load("res://assets/fonts/LiberationSans-Bold.ttf")
	touch = Config.is_touch()
	var pts := DisplayServer.window_get_size().y / maxf(1.0, DisplayServer.screen_get_scale())
	compact = touch and pts < 600
	root = _full(self)
	_build()


static func make_label(text: String, f: Font, size: int, col := Color.WHITE, shadow := 3) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", f)
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", col)
	if shadow > 0:
		lb.add_theme_color_override("font_shadow_color", INK)
		lb.add_theme_constant_override("shadow_offset_x", shadow)
		lb.add_theme_constant_override("shadow_offset_y", shadow)
		lb.add_theme_color_override("font_outline_color", INK)
		lb.add_theme_constant_override("outline_size", maxi(2, shadow))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb


static func panel_box(col := PANEL, pad := Vector4(10, 4, 10, 4)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _full(parent: Node) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


func _anchor(c: Control, preset: int, offset: Vector2, grow_left := false, grow_up := false) -> void:
	c.set_anchors_preset(preset)
	c.position = offset
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if grow_left else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if grow_up else Control.GROW_DIRECTION_END


func _build() -> void:
	# Screen-wide overlays first (under the readouts).
	var vignette := TextureRect.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.05, 1.05)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.55))
	grad.add_point(0.55, Color(0, 0, 0, 0))
	g.gradient = grad
	vignette.texture = g
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	_game = _full(root)
	_bullet_tint = TextureRect.new()
	var bg := GradientTexture2D.new()
	bg.fill = GradientTexture2D.FILL_RADIAL
	bg.fill_from = Vector2(0.5, 0.5)
	bg.fill_to = Vector2(1.0, 1.0)
	var bgrad := Gradient.new()
	bgrad.set_color(0, Color(170 / 255.0, 120 / 255.0, 1.0, 0))
	bgrad.set_color(1, Color(90 / 255.0, 40 / 255.0, 220 / 255.0, 0.58))
	bgrad.add_point(0.45, Color(170 / 255.0, 120 / 255.0, 1.0, 0))
	bgrad.add_point(0.82, Color(130 / 255.0, 80 / 255.0, 1.0, 0.34))
	bg.gradient = bgrad
	_bullet_tint.texture = bg
	_bullet_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bullet_tint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bullet_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bullet_tint.modulate.a = 0
	_game.add_child(_bullet_tint)
	_police_glow = PoliceGlow.new()
	_police_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_police_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(_police_glow)
	_flash = ColorRect.new()
	_flash.color = Color.WHITE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0
	_game.add_child(_flash)

	var s := 0.8 if compact else 1.0
	# --- Top left: position and standings ---
	var tl := VBoxContainer.new()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_theme_constant_override("separation", 0)
	_anchor(tl, Control.PRESET_TOP_LEFT, Vector2(22, 14))
	_game.add_child(tl)
	tl.add_child(make_label("POSITIE", font_ui, 16, YELLOW, 2))
	var pos_row := HBoxContainer.new()
	pos_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pos_num = make_label("8", font_ui, int(72 * s), Color.WHITE, 4)
	_pos_total = make_label("/8", font_ui, int(30 * s), Color(1, 1, 1, 0.85), 3)
	_pos_total.size_flags_vertical = Control.SIZE_SHRINK_END
	pos_row.add_child(_pos_num)
	pos_row.add_child(_pos_total)
	tl.add_child(pos_row)
	_standings = VBoxContainer.new()
	_standings.add_theme_constant_override("separation", 2)
	_standings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_standings.visible = not compact
	tl.add_child(_standings)
	for i in 8:
		var row := panel_box(PANEL, Vector4(4, 1, 10, 1))
		row.custom_minimum_size = Vector2(210, 0)
		var lb := make_label("", font_ui, 13, Color.WHITE, 0)
		row.add_child(lb)
		_standings.add_child(row)

	# --- Top right: stage ---
	var tr := VBoxContainer.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	_anchor(tr, Control.PRESET_TOP_RIGHT, Vector2(-22, 18), true)
	_game.add_child(tr)
	var stage_panel := panel_box(BLUE, Vector4(12, 6, 12, 6))
	stage_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_stage_name = make_label("", font_ui, int(15 * s), Color.WHITE, 0)
	stage_panel.add_child(_stage_name)
	tr.add_child(stage_panel)
	_stage_info = make_label("", font_ui, int(26 * s), Color.WHITE, 2)
	_stage_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stage_info.size_flags_horizontal = Control.SIZE_SHRINK_END
	tr.add_child(_stage_info)

	# --- Top centre: clock, wanted level, busted bar ---
	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.add_theme_constant_override("separation", 2)
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -160
	top.offset_right = 160
	top.offset_top = 8
	_game.add_child(top)
	_clock_box = VBoxContainer.new()
	_clock_box.add_theme_constant_override("separation", -8)
	_clock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl_lab := make_label("TIJD", font_ui, 13, YELLOW, 2)
	tl_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_box.add_child(tl_lab)
	_clock = make_label("0", font_ui, int(64 * s), Color.WHITE, 4)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_box.add_child(_clock)
	top.add_child(_clock_box)
	_wanted = make_label("★★★★★", font_text, int(30 * s), Color(1, 1, 1, 0.35), 2)
	_wanted.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_wanted)
	_bust = Bar.new()
	_bust.custom_minimum_size = Vector2(200, 14)
	_bust.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bust.fill_a = Color("ff3a3a")
	_bust.fill_b = Color("ff3a3a")
	_bust.border = Color("ff3a3a")
	_bust.text = "KLEMGEZET"
	_bust.font = font_ui
	_bust.font_size = 10
	_bust.visible = false
	top.add_child(_bust)

	# --- Bottom right: speedometer ---
	_br = Control.new()
	_br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_br.custom_minimum_size = Vector2(230, 150) * s
	_br.size = _br.custom_minimum_size
	_anchor(_br, Control.PRESET_BOTTOM_RIGHT, Vector2(-_br.size.x - 24, -_br.size.y - 16))
	_game.add_child(_br)
	_gauge = Gauge.new()
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.position = Vector2(0, 0)
	_gauge.size = Vector2(230, 130) * s
	_br.add_child(_gauge)
	_speed = make_label("0", font_ui, int(76 * s), Color.WHITE, 4)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed.position = Vector2(0, 30 * s)
	_speed.size = Vector2(222 * s, 90 * s)
	_br.add_child(_speed)
	var unit := make_label("KM/U", font_ui, int(16 * s), YELLOW, 2)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	unit.position = Vector2(0, 118 * s)
	unit.size = Vector2(220 * s, 24)
	_br.add_child(unit)

	# --- Bottom left: damage, nitro, slowmo, rams ---
	_bl = HBoxContainer.new()
	_bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bl.add_theme_constant_override("separation", 14)
	_bl.alignment = BoxContainer.ALIGNMENT_END
	_game.add_child(_bl)
	_dmg = DamageCar.new()
	_dmg.custom_minimum_size = Vector2(62, 114) * s
	_dmg.size_flags_vertical = Control.SIZE_SHRINK_END
	_dmg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bl.add_child(_dmg)
	var side := VBoxContainer.new()
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_constant_override("separation", 6)
	side.size_flags_vertical = Control.SIZE_SHRINK_END
	_bl.add_child(side)
	side.add_child(make_label("SCHADE", font_ui, 12, YELLOW, 2))
	_dmg_pct = make_label("0%", font_ui, int(28 * s), Color.WHITE, 3)
	side.add_child(_dmg_pct)
	_nitro = Bar.new()
	_nitro.custom_minimum_size = Vector2(210, 18) * s
	_nitro.text = "NITRO"
	_nitro.font = font_ui
	side.add_child(_nitro)
	_bullet = Bar.new()
	_bullet.custom_minimum_size = Vector2(210, 18) * s
	_bullet.fill_a = Color("7a2cff")
	_bullet.fill_b = Color("d6a8ff")
	_bullet.text = "SLOWMO"
	_bullet.font = font_ui
	side.add_child(_bullet)
	var rams := HBoxContainer.new()
	rams.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rams.add_theme_constant_override("separation", 6)
	_ram_l = _ram_box("Q")
	_ram_r = _ram_box("E")
	rams.add_child(_ram_l.get_parent())
	rams.add_child(make_label("RAM", font_ui, 12, Color(1, 1, 1, 0.7), 0))
	rams.add_child(_ram_r.get_parent())
	side.add_child(rams)

	# --- Centre: messages, countdown ---
	_messages = VBoxContainer.new()
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_messages.alignment = BoxContainer.ALIGNMENT_BEGIN
	_messages.add_theme_constant_override("separation", 4)
	_messages.set_anchors_preset(Control.PRESET_FULL_RECT)
	_messages.anchor_top = 0.22
	root.add_child(_messages)
	_countdown_box = _full(root)

	# --- Edges: rivals alongside, look-back, restart hold ---
	_side_l = make_label("◀◀", font_text, int(34 * s), YELLOW, 2)
	_side_r = make_label("▶▶", font_text, int(34 * s), YELLOW, 2)
	_side_l.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_side_l.anchor_top = 0.6
	_side_l.offset_left = 18
	_side_r.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_side_r.anchor_top = 0.6
	_side_r.offset_left = -80
	_side_r.offset_right = -18
	_side_r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for lb in [_side_l, _side_r]:
		lb.modulate.a = 0
		_game.add_child(lb)
	_look_back = make_label("ACHTERUIT KIJKEN", font_ui, 13, Color.WHITE, 0)
	var lb_panel := panel_box()
	lb_panel.add_child(_look_back)
	lb_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lb_panel.position.y = 92 if not compact else 64
	lb_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lb_panel.visible = false
	_game.add_child(lb_panel)
	_restart = panel_box(PANEL, Vector4(10, 6, 10, 6))
	_restart.set_anchors_preset(Control.PRESET_CENTER)
	_restart.anchor_top = 0.6
	_restart.anchor_bottom = 0.6
	_restart.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_restart.custom_minimum_size = Vector2(240, 0)
	var rv := VBoxContainer.new()
	_restart_label = make_label("Houd R vast om te herstarten", font_ui, 13, Color.WHITE, 0)
	_restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_restart_label)
	var track_bg := ColorRect.new()
	track_bg.color = Color(1, 1, 1, 0.2)
	track_bg.custom_minimum_size = Vector2(0, 4)
	_restart_bar = ColorRect.new()
	_restart_bar.color = YELLOW
	_restart_bar.size = Vector2(0, 4)
	track_bg.add_child(_restart_bar)
	rv.add_child(track_bg)
	_restart.add_child(rv)
	_restart.visible = false
	root.add_child(_restart)

	_help = make_label("", font_text, 13, Color.WHITE, 0)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var help_panel := panel_box(PANEL, Vector4(12, 4, 12, 4))
	help_panel.add_child(_help)
	help_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help_panel.offset_left = -560
	help_panel.offset_right = 560
	help_panel.offset_top = -40
	help_panel.offset_bottom = -6
	help_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help_panel.visible = not touch
	help_panel.name = "help"
	_game.add_child(help_panel)

	_now_playing = panel_box(Color(1, 0.36, 0, 0.85), Vector4(18, 8, 18, 8))
	var np := VBoxContainer.new()
	np.add_theme_constant_override("separation", 0)
	np.add_child(make_label("♪ NU SPEELT", font_ui, 10, Color(1, 1, 1, 0.85), 0))
	_now_title = make_label("", font_ui, 18, Color.WHITE, 0)
	np.add_child(_now_title)
	_now_playing.add_child(np)
	_now_playing.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_now_playing.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_now_playing.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_now_playing.offset_top = -190 if touch else -130
	_now_playing.offset_bottom = -190 if touch else -130
	_now_playing.modulate.a = 0
	root.add_child(_now_playing)

	_reset_btn = Button.new()
	_reset_btn.text = "↺ Terug op de weg"
	_reset_btn.add_theme_font_override("font", font_ui)
	_reset_btn.add_theme_font_size_override("font_size", 24 if compact else 18)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 0.54, 0, 0.85)
		sb.border_color = YELLOW
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(999)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		_reset_btn.add_theme_stylebox_override(st, sb)
	_reset_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_reset_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reset_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_reset_btn.offset_top = -130
	_reset_btn.offset_bottom = -130
	if touch:
		_reset_btn.set_anchors_preset(Control.PRESET_CENTER)
		_reset_btn.anchor_top = 0.34
		_reset_btn.anchor_bottom = 0.34
	_reset_btn.visible = false
	_reset_btn.pressed.connect(func(): reset_pressed.emit())
	root.add_child(_reset_btn)
	_layout_corners()


func _ram_box(text: String) -> Label:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(2)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(26, 26) * (0.8 if compact else 1.0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lb := make_label(text, font_ui, 12, Color.WHITE, 0)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(lb)
	return lb


## Bottom corners; with touch buttons the gauges move up out of the thumbs' way.
func _layout_corners() -> void:
	var lift := 0.0
	if touch:
		lift = 150.0 if not compact else 0.0
	_bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bl.offset_left = 22
	_bl.offset_bottom = -20 - lift
	_bl.offset_top = -20 - lift
	if touch and compact:
		# Phone: damage and meters under the position, speed beside the stage info.
		_bl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_bl.grow_vertical = Control.GROW_DIRECTION_END
		_bl.offset_left = 22
		_bl.offset_top = 150
		_br.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_br.position = Vector2(-_br.size.x - 20, 100)
		_gauge.visible = false
	elif touch:
		_br.position.y -= lift


# ------------------------------------------------------------------ updates

static func fmt_time(t: float) -> String:
	var m := floori(t / 60)
	return "%d:%05.2f" % [m, t - m * 60]


func update_state(h: Dictionary) -> void:
	var player: Vehicle = h.player
	_clock_box.visible = h.timeLeft >= 0
	if h.timeLeft >= 0:
		_clock.text = str(ceili(h.timeLeft))
		var low: bool = h.timeLeft < 10
		_clock.add_theme_color_override("font_color", RED if low else Color.WHITE)
		_clock.modulate.a = (0.4 + 0.6 * absf(sin(_t * 7.8))) if low else 1.0
	if h.stars != _last_stars:
		_last_stars = h.stars
		_wanted.text = "★★★★★"
	if h.stars > 0:
		var on := "★".repeat(h.stars)
		var off := "☆".repeat(5 - h.stars)
		_wanted.text = on + off
		var red := fmod(_t / 0.6, 2.0) > 1.0
		_wanted.add_theme_color_override("font_color", Color("ff3a3a") if red else Color("4f8bff"))
	else:
		_wanted.text = "☆☆☆☆☆"
		_wanted.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	_police_glow.on = h.sirenNear and h.stars > 0
	_bust.visible = h.bust > 0.02
	_bust.value = h.bust
	_bust.queue_redraw()
	var kmh := roundi(player.speed * 3.6)
	_speed.text = str(kmh)
	_gauge.frac = minf(1.0, kmh / 300.0)
	_gauge.nitro = player.nitro_active
	_gauge.queue_redraw()

	if h.position != _last_pos:
		_pos_num.text = str(h.position)
		_pos_total.text = "/%d" % h.total
		_pos_num.pivot_offset = _pos_num.size / 2
		var tw := create_tween()
		_pos_num.scale = Vector2(1.6, 1.6)
		_pos_num.add_theme_color_override("font_color", YELLOW)
		tw.tween_property(_pos_num, "scale", Vector2.ONE, 0.4).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): _pos_num.add_theme_color_override("font_color", Color.WHITE))
		_last_pos = h.position
	if _standings.visible:
		var rows: Array = h.rows
		for i in _standings.get_child_count():
			var row: PanelContainer = _standings.get_child(i)
			row.visible = i < rows.size()
			if i >= rows.size():
				continue
			var r: Dictionary = rows[i]
			var lb: Label = row.get_child(0)
			lb.text = "%d   %s%s" % [i + 1, r.name, "  WRAK" if r.wrecked else ""]
			lb.modulate.a = 0.5 if r.wrecked else 1.0
			var sb := row.get_theme_stylebox("panel") as StyleBoxFlat
			sb.bg_color = Color(160 / 255.0, 20 / 255.0, 20 / 255.0, 0.55) if r.isPlayer else PANEL

	_stage_name.text = h.stage
	_stage_info.text = "%.2f km     %s" % [maxf(0.0, h.distanceLeft) / 1000.0, fmt_time(h.raceTime)]

	for z in Vehicle.ZONES:
		_dmg.levels[z] = player.damage[z]
	_dmg.queue_redraw()
	var max_d := player.wreck_level
	_dmg_pct.text = "%d%%" % roundi(max_d)
	_dmg_pct.add_theme_color_override("font_color", RED if max_d > 75 else Color.WHITE)
	_dmg_pct.modulate.a = (0.4 + 0.6 * absf(sin(_t * 6.0))) if max_d > 75 else 1.0
	_nitro.value = player.nitro
	_nitro.glow = player.nitro > 0.99
	_nitro.fill_a = Color.WHITE if player.nitro_active else (Color("36c6ff") if player.nitro > 0.99 else Color("0a5cff"))
	_nitro.fill_b = Color("b4f0ff") if player.nitro > 0.99 and not player.nitro_active else Color("36c6ff")
	_nitro.queue_redraw()
	_bullet.value = h.bullet
	_bullet.glow = h.bullet > 0.99
	_bullet.blink = h.bulletOn
	_bullet.queue_redraw()
	_bullet_tint.modulate.a = move_toward(_bullet_tint.modulate.a, 1.0 if h.bulletOn else 0.0, get_process_delta_time() * 4)
	var ready := player.ram_cooldown <= 0
	_ram_state(_ram_l, ready, ready and h.ramTargetL)
	_ram_state(_ram_r, ready, ready and h.ramTargetR)
	_side_l.modulate.a = move_toward(_side_l.modulate.a, 0.9 if h.sideL else 0.0, get_process_delta_time() * 6)
	_side_r.modulate.a = move_toward(_side_r.modulate.a, 0.9 if h.sideR else 0.0, get_process_delta_time() * 6)
	_look_back.get_parent().visible = h.lookBack
	_restart.visible = h.restartHold > 0.05
	_restart_bar.size.x = _restart_bar.get_parent().size.x * h.restartHold


func _ram_state(lb: Label, ready: bool, target: bool) -> void:
	var p: PanelContainer = lb.get_parent()
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	p.pivot_offset = p.size / 2
	if target:
		sb.bg_color = YELLOW
		sb.border_color = YELLOW
		lb.add_theme_color_override("font_color", INK)
		var k := 1.0 + 0.18 * absf(sin(_t * 7.85))
		p.scale = Vector2(k, k)
		p.modulate.a = 1
	elif ready:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = YELLOW
		lb.add_theme_color_override("font_color", YELLOW)
		p.scale = Vector2.ONE
		p.modulate.a = 1
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(1, 1, 1, 0.35)
		lb.add_theme_color_override("font_color", Color.WHITE)
		p.scale = Vector2.ONE
		p.modulate.a = 0.35


func _process(delta: float) -> void:
	_t += delta
	var glow_target := 1.0 if _police_glow.on else 0.0
	_police_glow.alpha = move_toward(_police_glow.alpha, glow_target, delta * 2.5)
	_police_glow.queue_redraw()


## Key labels for the device in use: the ram indicators, help line and reset prompt.
func set_keys(k: Dictionary) -> void:
	_ram_l.text = k.ramL
	_ram_r.text = k.ramR
	_reset_key = k.reset
	_help.text = k.help
	_restart_label.text = "Houd %s vast om te herstarten" % k.restart
	var help: Control = _game.get_node("help")
	help.visible = not k.touch and not touch


func message(text: String, color: Variant = "#ffd400", big := false, duration := 1.4) -> void:
	var col := Color(color) if color is String else color as Color
	var lb := make_label(text, font_big, (84 if big else 44) if not compact else (60 if big else 34), col, 4)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_constant_override("outline_size", 6)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(0, lb.get_minimum_size().y)
	holder.add_child(lb)
	lb.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_messages.add_child(holder)
	while _messages.get_child_count() > 4:
		var old := _messages.get_child(0)
		_messages.remove_child(old)
		old.queue_free()
	await get_tree().process_frame
	if not is_instance_valid(lb):
		return
	lb.pivot_offset = lb.size / 2
	lb.rotation = deg_to_rad(-4)
	lb.scale = Vector2(2.2, 2.2)
	lb.modulate.a = 0
	var tw := lb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lb, "scale", Vector2.ONE, duration * 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(lb, "modulate:a", 1.0, duration * 0.12)
	tw.chain().tween_interval(duration * 0.68)
	tw.chain().set_parallel(true)
	tw.tween_property(lb, "modulate:a", 0.0, duration * 0.2)
	tw.tween_property(lb, "position:y", lb.position.y - 30, duration * 0.2)
	tw.chain().tween_callback(func(): holder.queue_free())


## A rival talking trash: smaller, subtitle-style.
func taunt(who: String, text: String) -> void:
	var p := panel_box(Color(8 / 255.0, 10 / 255.0, 20 / 255.0, 0.6), Vector4(14, 6, 14, 6))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.add_theme_font_override("normal_font", font_ui)
	rt.add_theme_font_size_override("normal_font_size", 22 if not compact else 18)
	rt.text = "[color=#ffd400]%s[/color]  “%s”" % [who, text]
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(rt)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_messages.add_child(p)
	p.modulate.a = 0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.22)
	tw.tween_interval(1.65)
	tw.tween_property(p, "modulate:a", 0.0, 0.33)
	tw.tween_callback(func(): p.queue_free())


## Speed camera flash.
func flash() -> void:
	_flash.modulate.a = 0.9
	var tw := create_tween()
	tw.tween_property(_flash, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_OUT)


func show_now_playing(title: String) -> void:
	_now_title.text = title
	var tw := _now_playing.create_tween()
	_now_playing.modulate.a = 0
	tw.tween_property(_now_playing, "modulate:a", 1.0, 0.45)
	tw.tween_interval(3.15)
	tw.tween_property(_now_playing, "modulate:a", 0.0, 0.9)


func countdown(text: String, go := false) -> void:
	var lb := make_label(text, font_big, (130 if go else 160) if not compact else (90 if go else 110), Color("4dff6a") if go else YELLOW, 6)
	lb.add_theme_constant_override("outline_size", 8)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lb.anchor_top = 0.2
	lb.anchor_bottom = 0.2
	lb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown_box.add_child(lb)
	await get_tree().process_frame
	if not is_instance_valid(lb):
		return
	lb.pivot_offset = lb.size / 2
	lb.scale = Vector2(2.5, 2.5)
	lb.modulate.a = 0
	var tw := lb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lb, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(lb, "modulate:a", 1.0, 0.18)
	tw.chain().set_parallel(true)
	tw.tween_property(lb, "scale", Vector2(0.9, 0.9), 0.72)
	tw.tween_property(lb, "modulate:a", 0.0, 0.72)
	tw.chain().tween_callback(func(): lb.queue_free())


func set_help_visible(v: bool) -> void:
	var help: Control = _game.get_node("help")
	var tw := help.create_tween()
	tw.tween_property(help, "modulate:a", 1.0 if v else 0.0, 1.0)


## Show the 'back on the road' prompt while the player is stuck.
func show_reset(v: bool) -> void:
	if _reset_btn.visible == v:
		return
	_reset_btn.visible = v
	_reset_btn.text = "↺ Terug op de weg" if touch else "↺ Terug op de weg (%s)" % _reset_key


func set_visible_hud(v: bool) -> void:
	_game.visible = v
