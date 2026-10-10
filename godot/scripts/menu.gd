class_name Menu
extends CanvasLayer
## Arcade menus, driven by keyboard/gamepad navigation edges and by taps/clicks on the items.
## Port of src/ui/Menu.ts. Actions: start_stage(i, campaign), next_stage(), restart_race(), resume(),
## to_menu(), choose_car(id), preview_car(id), sound().

const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const YELLOW := Hud.YELLOW
const ORANGE := Hud.ORANGE

var screen := ""
var actions := {}
var stages: Array = []
var input: InputCtl
var gamepad := false
var touch := false
var compact := false

var _index := 0
var _items: Array = [] # {label, action, disabled}
var _buttons: Array = []
var _car_index := 0
var _car_order: Array = ["rx"] + Config.RIVALS
var player_car := "rx"
var _initials := ["A", "A", "A"]
var _initial_pos := 0
var _pending := {}
var _extras := {"campaign": false, "campaignTotal": 0.0, "unlocked": []}
var _last_rank := 0
var _score_stage := 5
var _note := ""
## When the current screen opened: a handbrake tap at the finish mustn't click the result away.
var _opened_at := 0
## Rebinding: the action waiting for a key press.
var _capturing := ""
var _font_ui: Font
var _font_italic: Font
var _font_big: Font
var _font_text: Font
var _bg: Control
var _box: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	layer = 5
	_font_ui = load("res://assets/fonts/RussoOne-Regular.ttf")
	_font_italic = Hud.italic(_font_ui, 0.14)
	_font_big = load("res://assets/fonts/Bangers-Regular.ttf")
	_font_text = load("res://assets/fonts/LiberationSans-Bold.ttf")
	touch = Config.is_touch()
	var pts := DisplayServer.window_get_size().y / maxf(1.0, DisplayServer.screen_get_scale())
	compact = pts < 600
	_bg = Control.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_bg.gui_input.connect(_on_bg_input)
	visible = false


var is_open: bool:
	get:
		return screen != ""


func set_gamepad(on: bool) -> void:
	if on == gamepad:
		return
	gamepad = on
	if screen == "title":
		_render()


func open(s: String) -> void:
	if _capturing != "":
		input.cancel_rebind()
	_capturing = ""
	screen = s
	_index = 0
	_note = ""
	_opened_at = Time.get_ticks_msec()
	if s == "cars":
		_car_index = _car_order.find(player_car)
		actions.preview_car.call(_car_order[_car_index])
	elif s in ["main", "title", "stages"]:
		actions.preview_car.call(player_car)
	visible = true
	_render()


func close() -> void:
	screen = ""
	visible = false
	for c in _bg.get_children():
		c.queue_free()


## After a race: initials entry first when the time makes the highscores.
func show_result(r: Dictionary, extras: Dictionary) -> void:
	_pending = r
	_extras = extras
	_last_rank = 0
	var key := Progress.score_key(stages[r.stage].id)
	var row: Dictionary = r.rows[r.position - 1] if r.position - 1 < r.rows.size() else {}
	var finished: bool = row.get("finished", false)
	if not r.outOfTime and finished and r.qualified and Progress.qualifies(key, r.time):
		var ini := Progress.last_initials().rpad(3, "A").substr(0, 3)
		_initials = [ini[0], ini[1], ini[2]]
		_initial_pos = 0
		open("initials")
	else:
		open("results")


func _act(n: String) -> void:
	match n:
		"car-prev":
			_step_car(-1)
		"car-next":
			_step_car(1)
		"score-prev":
			_step_scores(-1)
		"score-next":
			_step_scores(1)
		"letter-up":
			_change_letter(1)
		"letter-down":
			_change_letter(-1)
		"letter-next":
			_next_letter()
		"key-cancel":
			input.cancel_rebind()
			_capturing = ""
			_render()
		_:
			if n.begins_with("slot-"):
				_initial_pos = int(n.substr(5))
				_render()


func _change_letter(d: int) -> void:
	var i := (LETTERS.find(_initials[_initial_pos]) + d + LETTERS.length()) % LETTERS.length()
	_initials[_initial_pos] = LETTERS[i]
	_render()


func _start_rebind(action: String) -> void:
	var idx := _index
	_capturing = action
	_note = ""
	_render()
	input.rebind(action, func(ok: bool) -> void:
		_capturing = ""
		_note = "" if ok else "Niet gewijzigd: geannuleerd, of die toets heeft al een vaste functie."
		_index = idx
		_render()
	)


func _step_car(d: int) -> void:
	_car_index = (_car_index + d + _car_order.size()) % _car_order.size()
	_note = ""
	actions.preview_car.call(_car_order[_car_index])
	_render()


func _step_scores(d: int) -> void:
	_score_stage = ((_score_stage - 1 + d + 5) % 5) + 1
	_render()


func _next_letter() -> void:
	if _initial_pos < 2:
		_initial_pos += 1
		_render()
		return
	var r := _pending
	var ini := "".join(_initials)
	Progress.remember_initials(ini)
	var score := {"initials": ini, "time": r.time, "takedowns": r.takedowns, "car": r.car, "date": Time.get_date_string_from_system()}
	_last_rank = Progress.add_score(Progress.score_key(stages[r.stage].id), score)
	open("results")


## Feed navigation from the polled controls.
func handle(c: InputCtl.Controls) -> void:
	if screen == "":
		return
	var s := screen
	if _capturing != "":
		return # the next key press is being bound
	# Space doubles as the handbrake: ignore confirms for a moment after a race ends.
	var fresh := (s == "results" or s == "initials") and Time.get_ticks_msec() - _opened_at < 900
	var confirm := c.confirm and not fresh
	if s == "title":
		if (c.confirm or c.any) and not fresh:
			open("main")
		return
	if s == "cars":
		if c.navLeft:
			_step_car(-1)
		if c.navRight:
			_step_car(1)
	if s == "scores":
		if c.navLeft:
			_step_scores(-1)
		if c.navRight:
			_step_scores(1)
	if s == "initials":
		if c.navUp:
			_act("letter-up")
		if c.navDown:
			_act("letter-down")
		if c.navLeft and _initial_pos > 0:
			_initial_pos -= 1
			_render()
		if (c.navRight and not fresh) or confirm:
			_next_letter()
		return
	if not _items.is_empty():
		if c.navUp:
			_move(-1)
		if c.navDown:
			_move(1)
		if confirm:
			_activate(_index)
	if c.back or (c.pause and s == "pause"):
		if s == "pause":
			actions.resume.call()
		elif s == "keys":
			open("controls")
		elif s != "main" and s != "results":
			open("main")


func _activate(i: int) -> void:
	if i < 0 or i >= _items.size():
		return
	var it: Dictionary = _items[i]
	if not it.get("disabled", false):
		it.action.call()


func _move(d: int) -> void:
	_index = (_index + d + _items.size()) % _items.size()
	_highlight()


func _highlight() -> void:
	for i in _buttons.size():
		var b: Button = _buttons[i]
		var sel := i == _index
		var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
		sb.bg_color = Color(ORANGE, 0.9) if sel else Color(1, 1, 1, 0.06)
		sb.border_color = YELLOW if sel else Color(0, 0, 0, 0)
		sb.content_margin_left = 28 if sel else 18
		if sel and is_instance_valid(_scroll):
			_scroll.ensure_control_visible(b)


func _on_bg_input(e: InputEvent) -> void:
	var tapped: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if tapped and screen == "title":
		open("main")


# ------------------------------------------------------------------ building blocks

func _label(text: String, f: Font, size: int, col := Color.WHITE, shadow := 0) -> Label:
	var lb := Hud.make_label(text, f, size, col, shadow)
	return lb


func _rich(text: String, size: int, col := Color.WHITE) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size = Vector2(minf(620, get_viewport().get_visible_rect().size.x - 60), 0)
	rt.add_theme_font_override("normal_font", _font_text)
	rt.add_theme_font_override("bold_font", _font_ui)
	rt.add_theme_font_size_override("normal_font_size", size)
	rt.add_theme_font_size_override("bold_font_size", size)
	rt.add_theme_color_override("default_color", col)
	rt.text = text
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rt


func _logo(parent: Control) -> void:
	var s := 0.45 if compact else 1.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(-40 * s))
	box.rotation = deg_to_rad(-5)
	# "A35": yellow → orange → red, with a blue drop shadow (a shader on its own label, so the
	# shadow label underneath keeps its colour).
	var a35 := MarginContainer.new()
	var shadow_box := MarginContainer.new()
	shadow_box.add_theme_constant_override("margin_left", int(6 * s))
	shadow_box.add_theme_constant_override("margin_top", int(6 * s))
	shadow_box.add_child(_label("A35", _font_big, int(150 * s), Color("1d3cff"), 0))
	a35.add_child(shadow_box)
	var grad := _label("A35", _font_big, int(150 * s), Color.WHITE, 0)
	var mat := ShaderMaterial.new()
	mat.shader = _gradient_shader()
	grad.material = mat
	grad.resized.connect(func(): mat.set_shader_parameter("height", grad.size.y))
	grad.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grad.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	a35.add_child(grad)
	box.add_child(a35)
	var racer := _label("RACER", _font_big, int(96 * s), Color("e8e8f0"), 0)
	racer.add_theme_color_override("font_shadow_color", Color("c4161c"))
	racer.add_theme_constant_override("shadow_offset_x", int(5 * s))
	racer.add_theme_constant_override("shadow_offset_y", int(5 * s))
	box.add_child(racer)
	parent.add_child(box)


static var _grad_shader: Shader


static func _gradient_shader() -> Shader:
	if _grad_shader == null:
		_grad_shader = Shader.new()
		_grad_shader.code = """shader_type canvas_item;
// Vertical gradient over the label (the web logo's linear-gradient(#fff36b, #ff8a00 55%, #ff2a00)).
uniform float height = 100.0;
varying float y;
void vertex() { y = VERTEX.y; }
void fragment() {
	float t = clamp(y / height, 0.0, 1.0);
	vec3 top = vec3(1.0, 0.953, 0.42);
	vec3 mid = vec3(1.0, 0.541, 0.0);
	vec3 bot = vec3(1.0, 0.165, 0.0);
	vec3 c = t < 0.55 ? mix(top, mid, t / 0.55) : mix(mid, bot, (t - 0.55) / 0.45);
	COLOR = vec4(c, COLOR.a);
}
"""
	return _grad_shader


func _title(text: String) -> Label:
	var lb := _label(text, _font_big, 40 if compact else 56, YELLOW, 0)
	lb.add_theme_color_override("font_shadow_color", Color("c4161c"))
	lb.add_theme_constant_override("shadow_offset_x", 4)
	lb.add_theme_constant_override("shadow_offset_y", 4)
	return lb


func _big_title(text: String) -> Label:
	var lb := _label(text, _font_big, 64 if compact else 120, YELLOW, 0)
	lb.add_theme_color_override("font_shadow_color", Color("c4161c"))
	lb.add_theme_constant_override("shadow_offset_x", 6)
	lb.add_theme_constant_override("shadow_offset_y", 6)
	return lb


func _list(items: Array) -> VBoxContainer:
	_items = items
	_buttons = []
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6 if compact else 8)
	box.custom_minimum_size = Vector2(340 if screen == "keys" else 280, 0)
	for i in items.size():
		var it: Dictionary = items[i]
		var b := Button.new()
		b.text = it.label
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", _font_italic)
		b.add_theme_font_size_override("font_size", (16 if compact else 22) if screen != "keys" else (14 if compact else 16))
		var col := Color(1, 1, 1, 0.45) if it.get("disabled", false) else Color.WHITE
		for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(st, col)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.06)
		sb.border_width_left = 4
		sb.border_color = Color(0, 0, 0, 0)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 6 if compact else 9
		sb.content_margin_bottom = 6 if compact else 9
		sb.skew = Vector2(0.14, 0)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		var idx := i
		b.mouse_entered.connect(func() -> void:
			if not touch:
				_index = idx
				_highlight())
		b.pressed.connect(func() -> void:
			_index = idx
			_activate(idx))
		box.add_child(b)
		_buttons.append(b)
	_highlight.call_deferred()
	return box


func _arrow(text: String, act: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font_ui)
	b.add_theme_font_size_override("font_size", 56 if touch else 42)
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, YELLOW)
	b.custom_minimum_size = Vector2(64, 64) if touch else Vector2.ZERO
	b.pressed.connect(func(): _act(act))
	return b


func _small_button(text: String, act: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font_ui)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", YELLOW)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(func(): _act(act))
	return b


func _table(header: Array, rows: Array, highlight := -1) -> GridContainer:
	var g := GridContainer.new()
	g.columns = header.size()
	g.add_theme_constant_override("h_separation", 2)
	g.add_theme_constant_override("v_separation", 2)
	var fs := 12 if compact else 17
	for h in header:
		var lb := _label(h, _font_ui, 10 if compact else 12, YELLOW)
		g.add_child(lb)
	for r in rows.size():
		for cell in rows[r]:
			var p := Hud.panel_box(Color(170 / 255.0, 20 / 255.0, 20 / 255.0, 0.7) if r == highlight else Hud.PANEL, Vector4(10, 5, 12, 5))
			var rt := _rich(str(cell), fs)
			rt.custom_minimum_size = Vector2(0, 0)
			rt.autowrap_mode = TextServer.AUTOWRAP_OFF
			p.add_child(rt)
			g.add_child(p)
	return g


func _bar(label: String, v: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lb := _label(label.to_upper(), _font_ui, 13)
	lb.custom_minimum_size = Vector2(130, 0)
	row.add_child(lb)
	var bar := Hud.Bar.new()
	bar.custom_minimum_size = Vector2(200, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.value = clampf(v, 0.05, 1.0)
	bar.fill_a = ORANGE
	bar.fill_b = YELLOW
	bar.border = Color(1, 1, 1, 0.12)
	row.add_child(bar)
	return row


func _stage_label(st: Dictionary) -> String:
	return "Etappe %d · %s → %s" % [st.id, st.from, st.to]


# ------------------------------------------------------------------ screens

func _render() -> void:
	for c in _bg.get_children():
		_bg.remove_child(c)
		c.queue_free()
	_items = []
	_buttons = []
	var s := screen
	var left := s in ["title", "main", "cars"]
	# Background: a dark sweep from the left (the car shows on the right), or a vignette.
	var shade := TextureRect.new()
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	if left:
		g.fill_from = Vector2(0, 0.5)
		g.fill_to = Vector2(1, 0.5)
		grad.set_color(0, Color(5 / 255.0, 6 / 255.0, 14 / 255.0, 0.92))
		grad.set_color(1, Color(5 / 255.0, 6 / 255.0, 14 / 255.0, 0.45 if compact else 0.0))
		grad.add_point(0.38, Color(5 / 255.0, 6 / 255.0, 14 / 255.0, 0.7))
	else:
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 1.0)
		grad.set_color(0, Color(10 / 255.0, 10 / 255.0, 30 / 255.0, 0.6))
		grad.set_color(1, Color(0, 0, 0, 0.88))
	g.gradient = grad
	shade.texture = g
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(shade)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_bg.add_child(_scroll)
	var outer := MarginContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pad := 16 if compact else 24
	var side_pad := maxi(pad, int(get_viewport().get_visible_rect().size.x * 0.06)) if left else pad
	outer.add_theme_constant_override("margin_left", side_pad)
	outer.add_theme_constant_override("margin_right", pad)
	outer.add_theme_constant_override("margin_top", pad)
	outer.add_theme_constant_override("margin_bottom", pad)
	_scroll.add_child(outer)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 8 if compact else 14)
	_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if left else Control.SIZE_SHRINK_CENTER
	_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_box)
	var box := _box
	var sub_size := 15 if compact else 18

	match s:
		"title":
			_logo(box)
			box.add_child(_label("Van Salland naar Twente · Raalte → Enschede", _font_ui, sub_size, YELLOW))
			var press := _label("Druk op ✕ / A" if gamepad else ("Tik om te starten" if touch else "Druk op ENTER"), _font_ui, 22)
			box.add_child(press)
			var tw := press.create_tween().set_loops()
			tw.tween_property(press, "modulate:a", 0.4, 0.7)
			tw.tween_property(press, "modulate:a", 1.0, 0.7)
		"main":
			var car: Dictionary = Config.CARS[player_car]
			_logo(box)
			box.add_child(_rich("Je rijdt de [b][color=#ffffff]%s[/color][/b]" % car.name, sub_size, YELLOW))
			box.add_child(_list([
				{"label": "Racen", "action": func(): open("stages")},
				{"label": "Auto kiezen", "action": func(): open("cars")},
				{"label": "Highscores", "action": func(): open("scores")},
				{"label": "Statistieken", "action": func(): open("stats")},
				{"label": "Besturing", "action": func(): open("controls")},
				{"label": "Geluid aan/uit", "action": func(): actions.sound.call()},
			]))
		"stages":
			var cleared := Progress.cleared_stages()
			box.add_child(_title("Waar rijden we?"))
			var items := [{"label": "Hele race · Raalte → Enschede", "action": func(): actions.start_stage.call(0, true)}]
			for i in stages.size():
				var st: Dictionary = stages[i]
				var idx := i
				items.append({"label": _stage_label(st) + ("  ✓" if cleared.has(int(st.id)) else ""), "action": func(): actions.start_stage.call(idx, false)})
			items.append({"label": "Terug", "action": func(): open("main")})
			box.add_child(_list(items))
			box.add_child(_rich("Eindig bij de eerste drie om een etappe te halen. Elke gehaalde etappe speelt een nieuwe auto vrij.", 13, Color(1, 1, 1, 0.75)))
		"cars":
			var id: String = _car_order[_car_index]
			var c: Dictionary = Config.CARS[id]
			var unlocked := Progress.is_unlocked(id)
			var owner := "Jouw auto" if id == player_car else "Normaal van %s" % c.driver
			box.add_child(_title("Kies je auto"))
			var pick := HBoxContainer.new()
			pick.add_theme_constant_override("separation", 14)
			pick.add_child(_arrow("‹", "car-prev"))
			var card := VBoxContainer.new()
			card.custom_minimum_size = Vector2(340, 0)
			card.add_theme_constant_override("separation", 8)
			var nm := _label(c.name, _font_big, 32 if compact else 40)
			nm.modulate.a = 1.0 if unlocked else 0.55
			card.add_child(nm)
			card.add_child(_label("%s · %d/%d" % [owner, _car_index + 1, _car_order.size()], _font_ui, 13, YELLOW))
			card.add_child(_bar("Topsnelheid", (c.topSpeed - 60) / 12.0))
			card.add_child(_bar("Acceleratie", (c.accelFactor - 0.85) / 0.25))
			card.add_child(_bar("Gewicht", (c.mass - 1000) / 700.0))
			card.add_child(_bar("Grip", (c.gripFactor - 0.9) / 0.17))
			if not unlocked:
				card.add_child(_label("🔒 Haal etappe %d om deze auto vrij te spelen" % Progress.UNLOCKS[id], _font_ui, 14, Color("ff9a3c")))
			pick.add_child(card)
			pick.add_child(_arrow("›", "car-next"))
			box.add_child(pick)
			box.add_child(_list([
				{"label": "Deze nemen" if unlocked else "Nog op slot", "disabled": not unlocked, "action": func() -> void:
					player_car = id
					actions.choose_car.call(id)
					open("main")},
				{"label": "Terug", "action": func(): open("main")},
			]))
			box.add_child(_rich("← → wisselen · je ruilt van auto met de coureur die hem normaal rijdt", 13, Color(1, 1, 1, 0.75)))
		"scores":
			var st: Dictionary = stages[_score_stage - 1]
			var rows := Progress.get_scores(Progress.score_key(st.id))
			box.add_child(_title("Highscores"))
			var pick := HBoxContainer.new()
			pick.add_theme_constant_override("separation", 14)
			pick.alignment = BoxContainer.ALIGNMENT_CENTER
			pick.add_child(_arrow("‹", "score-prev"))
			var lb := _label(_stage_label(st), _font_ui, sub_size, YELLOW)
			lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pick.add_child(lb)
			pick.add_child(_arrow("›", "score-next"))
			box.add_child(pick)
			if rows.is_empty():
				box.add_child(_label("Nog geen tijden. Rij de eerste!", _font_ui, sub_size, YELLOW))
			else:
				var data := []
				for i in rows.size():
					var r: Dictionary = rows[i]
					data.append([i + 1, r.initials, Hud.fmt_time(r.time), r.takedowns, r.car])
				box.add_child(_table(["#", "NAAM", "TIJD", "TAKEDOWNS", "AUTO"], data, _last_rank - 1))
			box.add_child(_list([{"label": "Terug", "action": func(): open("main")}]))
		"stats":
			var l := Progress.lifetime()
			box.add_child(_title("Statistieken"))
			box.add_child(_table(["", ""], [
				["Races gereden", l.races], ["Gewonnen", l.wins], ["Etappes gehaald", "%d van 5" % l.stagesCleared],
				["Tegenstanders in de vangrail", l.takedowns], ["Rakelings gepasseerd", l.nearMisses],
				["Topsnelheid", "%d km/u" % roundi(l.topSpeed)], ["Hardste klap", "%d km/u" % roundi(l.biggestHit * 3.6)],
				["Bekeuringen", l.busted], ["Total loss", l.wrecks], ["Kilometers", "%.1f" % l.km],
			]))
			box.add_child(_list([{"label": "Terug", "action": func(): open("main")}]))
		"controls":
			var k := func(a: String) -> String: return input.bind_label(a).replace("/", " / ")
			box.add_child(_title("Besturing"))
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 26)
			grid.add_theme_constant_override("v_separation", 4)
			for pair in [
				["%s · %s" % [k.call("throttle"), k.call("brake")], "gas & rem"], ["%s · %s" % [k.call("left"), k.call("right")], "sturen"],
				[k.call("handbrake"), "handrem (drift)"], [k.call("nitro"), "nitro"],
				["%s / %s" % [k.call("ramLeft"), k.call("ramRight")], "ram links / rechts"], [k.call("bulletTime"), "bullet time"],
				[k.call("lookBack"), "achterom kijken (vasthouden)"], [k.call("reset"), "terug op de weg"],
				["ESC / P", "pauze"], ["R vasthouden", "opnieuw"], ["N", "volgend nummer"], ["− / +", "muziekvolume"],
			]:
				grid.add_child(_rich("[b][color=#ffd400]%s[/color][/b]  %s" % pair, 13 if compact else 15))
			box.add_child(grid)
			for tip in [
				"Gamepad: R2/L2 gas en rem, ✕ handrem, ○ nitro, L1/R1 rammen, L3 of R3 bullet time, rechterstick naar beneden om achterom te kijken, △ terug op de weg, Select vasthouden om opnieuw te beginnen. iPhone en iPad: knoppen op het scherm (liggend); schuif met je duim tussen ◀ en ▶, de RAM-knop kiest zelf de kant, en AUTO GAS houdt het gas voor je ingedrukt.",
				"Rammen: als Q of E geel oplicht, staat er iemand binnen bereik. Gele pijlen aan de rand van het scherm: er rijdt een rivaal naast je.",
				"Slipstream: blijf even vlak achter een auto hangen en stuur er dan uit voor een slingshot. Achteropgeraakt na een crash? Het veld wacht een beetje op je.",
				"Op de N35 rijdt het tegenverkeer naast je: inhalen kan, maar kijk uit. Haal de checkpoints op tijd en eindig bij de eerste drie.",
			]:
				box.add_child(_rich(tip, 12 if compact else 13, Color(1, 1, 1, 0.75)))
			var items := []
			if not touch:
				items.append({"label": "Toetsen instellen", "action": func(): open("keys")})
			items.append({"label": "Terug", "action": func(): open("main")})
			box.add_child(_list(items))
		"keys":
			box.add_child(_title("Toetsen instellen"))
			var items := []
			for a in InputCtl.BIND_LABELS:
				var action: String = a
				var key := "druk op een toets…" if _capturing == action else input.bind_label(action).replace("/", " / ")
				items.append({"label": "%s   ·   %s" % [InputCtl.BIND_LABELS[action], key], "action": func(): _start_rebind(action)})
			items.append({"label": "Standaard herstellen", "action": func() -> void:
				input.reset_bindings()
				_note = "Standaardtoetsen hersteld."
				_render()})
			items.append({"label": "Terug", "action": func(): open("controls")})
			box.add_child(_list(items))
			if _capturing != "":
				var row := HBoxContainer.new()
				row.add_child(_rich("Druk op de nieuwe toets voor [b]%s[/b] · ESC annuleert" % InputCtl.BIND_LABELS[_capturing], 13, Color(1, 1, 1, 0.75)))
				row.add_child(_small_button("Annuleren", "key-cancel"))
				box.add_child(row)
			else:
				box.add_child(_rich("Kies een actie en druk op de nieuwe toets. ESC, P, R, M, N, T, ENTER, ⌫ en −/+ hebben een vaste functie.", 13, Color(1, 1, 1, 0.75)))
		"pause":
			box.add_child(_big_title("PAUZE"))
			box.add_child(_list([
				{"label": "Verder", "action": func(): actions.resume.call()},
				{"label": "Opnieuw", "action": func(): actions.restart_race.call()},
				{"label": "Naar menu", "action": func(): actions.to_menu.call()},
			]))
		"initials":
			box.add_child(_big_title("NIEUWE HIGHSCORE"))
			box.add_child(_label("%s · zet je naam erbij" % Hud.fmt_time(_pending.time), _font_ui, sub_size, YELLOW))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 18)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			for i in 3:
				var slot := VBoxContainer.new()
				slot.alignment = BoxContainer.ALIGNMENT_CENTER
				var sel := i == _initial_pos
				slot.add_child(_arrow("▲", "letter-up") if sel else Control.new())
				var letter := Button.new()
				letter.text = _initials[i]
				letter.flat = true
				letter.focus_mode = Control.FOCUS_NONE
				letter.add_theme_font_override("font", _font_big)
				letter.add_theme_font_size_override("font_size", 64 if compact else 84)
				for st in ["font_color", "font_hover_color", "font_pressed_color"]:
					letter.add_theme_color_override(st, YELLOW if sel else Color.WHITE)
				letter.custom_minimum_size = Vector2(72, 0)
				var slot_act := "slot-%d" % i
				letter.pressed.connect(func(): _act(slot_act))
				slot.add_child(letter)
				slot.add_child(_arrow("▼", "letter-down") if sel else Control.new())
				row.add_child(slot)
			box.add_child(row)
			var ok := _small_button("Volgende letter" if _initial_pos < 2 else "Opslaan", "letter-next")
			ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			box.add_child(ok)
			box.add_child(_rich("↑ ↓ letter kiezen · → of ENTER verder", 13, Color(1, 1, 1, 0.75)))
		"results":
			var r := _pending
			var x := _extras
			var st: Dictionary = stages[r.stage]
			var last: bool = r.stage >= stages.size() - 1
			var champion: bool = x.campaign and last and r.qualified
			var title := "TIJD OP!" if r.outOfTime else ("KAMPIOEN!" if champion else ("WINNAAR!" if r.position == 1 else "FINISH"))
			var verdict := ""
			if r.outOfTime:
				verdict = "Je haalde het checkpoint niet op tijd. Gas geven!"
			elif champion:
				verdict = "Van Raalte tot Enschede in %s. Kump wal goed!" % Hud.fmt_time(x.campaignTotal)
			elif r.qualified:
				verdict = "%s gehaald: %de plaats!" % [_stage_label(st), r.position]
			else:
				verdict = "%de... Je moet bij de eerste drie eindigen, noaber!" % r.position
			if _last_rank > 0:
				verdict += " · %de in de highscores" % _last_rank
			if x.campaign and not champion:
				verdict += " · hele race tot nu toe %s" % Hud.fmt_time(x.campaignTotal) if r.qualified else " · de hele race is voorbij"
			box.add_child(_big_title(title))
			var v := _rich(verdict, sub_size, YELLOW)
			box.add_child(v)
			if not x.unlocked.is_empty():
				var names := []
				for cid in x.unlocked:
					names.append(Config.CARS[cid].name)
				var un := _label("Nieuwe auto vrijgespeeld: %s!" % ", ".join(names), _font_ui, 18, Color("4dff6a"))
				box.add_child(un)
			var data := []
			var me := -1
			for i in r.rows.size():
				var row: Dictionary = r.rows[i]
				if row.isPlayer:
					me = i
				var tm := "—"
				if row.wrecked:
					tm = "WRAK"
				elif row.finished and row.time >= 0:
					tm = Hud.fmt_time(row.time) + ("  [color=#ff9a3c](+%ds)[/color]" % row.penalty if row.penalty else "")
				data.append([i + 1, row.name, row.car, tm, row.takedowns])
			box.add_child(_table(["#", "COUREUR", "AUTO", "TIJD", "TAKEDOWNS"], data, me))
			var items := []
			if r.qualified and not last:
				var nx: Dictionary = stages[r.stage + 1]
				items.append({"label": "Volgende etappe: %s → %s" % [nx.from, nx.to], "action": func(): actions.next_stage.call()})
			items.append({"label": "Opnieuw", "action": func(): actions.restart_race.call()})
			items.append({"label": "Naar menu", "action": func(): actions.to_menu.call()})
			box.add_child(_list(items))
	if _note != "":
		box.add_child(_rich(_note, 13, Color(1, 1, 1, 0.75)))
