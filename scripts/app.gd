extends Node

# ponytail: preload instead of class_name so parse works before .godot class cache exists.
const ReactionState = preload("res://scripts/reaction_state.gd")
const OsuState = preload("res://scripts/osu_state.gd")
const SphereState = preload("res://scripts/sphere_state.gd")
const ScoreStore = preload("res://scripts/score_store.gd")
const CornerWatch = preload("res://scripts/corner_watch.gd")
const SphereAim = preload("res://scripts/sphere_aim.gd")

const INK := Color("#ebf0f9")
const MUTED := Color("#97a6bd")
const ACCENT := Color("#7790ff")
const DARK := Color("#0b101e")
const OSU_RADIUS := 40.0
const OSU_PAD := 12.0

@onready var menu: Control = $Menu
@onready var color_reaction: Control = $ColorReaction
@onready var osu_page: Control = $Osu
@onready var corner_watch: CornerWatch = $CornerWatch
@onready var sphere_aim: SphereAim = $SphereAim
@onready var summary: Control = $Summary
@onready var trial_list: Control = $TrialList
@onready var flight_score_layer: Control = $FlightScore

var rng := RandomNumberGenerator.new()
var state: ReactionState = ReactionState.new()
var osu_state: OsuState = OsuState.new()
var sphere_state: SphereState = SphereState.new()
var scores: ScoreStore = ScoreStore.new()
var page := ""
var color_background: ColorRect
var color_title: Label
var color_hint: Label
var color_dots: Label
var osu_background: ColorRect
var osu_title: Label
var osu_hint: Label
var osu_dots: Label
var osu_circles_root: Control
var osu_centers: Array[Vector2] = []
var osu_circle_nodes: Array[Control] = []
var hud_title: Label
var hud_hint: Label
var hud_dots: Label
var hud_footer: Label
var summary_text: Label
var trial_rows: Array[Label] = []
var flight_score: Label
var score_flight: Tween
var score_flight_active := false
var menu_buttons: Array[Button] = []


func _ready() -> void:
	rng.randomize()
	scores.load_scores()
	_ensure_input_actions()
	Input.use_accumulated_input = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_build_menu()
	_build_color_page()
	_build_osu_page()
	_build_hud()
	_build_summary()
	_build_trial_list()
	show_menu()


func _process(_delta: float) -> void:
	if page.is_empty():
		return
	var now := Time.get_ticks_usec()
	if page == "color" or page == "corner":
		if state.advance(now):
			if page == "corner":
				if state.stage == ReactionState.Stage.TARGET:
					corner_watch.begin_target(rng.randi_range(0, 1) == 0)
				else:
					corner_watch.show_target(1.0)
					corner_watch.defeat_target()
			_refresh_project()
		if state.stage == ReactionState.Stage.TARGET and page == "corner":
			corner_watch.show_target(state.target_progress(now))
		if state.stage == ReactionState.Stage.SUMMARY:
			complete_summary()
	elif page == "spheres":
		if sphere_state.advance(now):
			if sphere_state.stage == SphereState.Stage.AIMING:
				sphere_aim.spawn_targets()
			elif sphere_state.stage == SphereState.Stage.INVALID:
				sphere_aim.clear_targets()
			_refresh_project()
		if sphere_state.stage == SphereState.Stage.SUMMARY:
			complete_summary()
	elif page == "osu":
		if osu_state.stage == OsuState.Stage.SUMMARY:
			complete_summary()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back"):
		if page.is_empty():
			get_tree().quit()
		else:
			show_menu()
		get_viewport().set_input_as_handled()
		return
	if page.is_empty():
		return
	if event.is_action_pressed("restart") and _summary_visible():
		_restart_project()
		return
	match page:
		"color", "corner":
			_handle_reaction_input(event)
		"osu":
			_handle_osu_input(event)
		"spheres":
			_handle_sphere_input(event)


func show_menu() -> void:
	page = ""
	state.reset()
	osu_state.reset()
	sphere_state.reset()
	_clear_osu_circles()
	menu.show()
	color_reaction.hide()
	osu_page.hide()
	summary.hide()
	trial_list.hide()
	flight_score_layer.hide()
	corner_watch.set_active(false)
	sphere_aim.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$CanvasLayer/HUD.hide()
	_update_best_scores()


func enter_project(project: String) -> void:
	page = project
	state.reset()
	osu_state.reset()
	sphere_state.reset()
	_clear_osu_circles()
	_reset_trial_list()
	menu.hide()
	summary.hide()
	trial_list.show()
	color_reaction.visible = page == "color"
	osu_page.visible = page == "osu"
	corner_watch.set_active(page == "corner")
	sphere_aim.set_active(page == "spheres")
	$CanvasLayer/HUD.visible = page == "corner" or page == "spheres"
	_refresh_project()


func complete_summary() -> void:
	if summary.visible or score_flight_active:
		return
	var samples := _active_samples()
	var result := ScoreStore.statistics(samples)
	scores.update(_score_key(), result.median)
	summary_text.text = "FIVE-TRIAL RESULT\n\n%.1f ms\nMEDIAN TIME\n\nMEAN  %.1f ms\nSTD DEV  %.1f ms\n\nR: RETRY    ESC: MENU" % [result.median, result.mean, result.deviation]
	$CanvasLayer/HUD.hide()
	summary.show()


func _restart_project() -> void:
	state.reset()
	osu_state.reset()
	sphere_state.reset()
	_clear_osu_circles()
	summary.hide()
	_reset_trial_list()
	if page == "corner" or page == "spheres":
		$CanvasLayer/HUD.show()
		if page == "spheres":
			sphere_aim.clear_targets()
	_refresh_project()


func _handle_reaction_input(event: InputEvent) -> void:
	if not _reaction_event(event):
		return
	var now := Time.get_ticks_usec()
	var target_was_active := state.stage == ReactionState.Stage.TARGET
	var samples_before := state.reactions_us.size()
	if page == "corner" and state.stage == ReactionState.Stage.TARGET:
		state.respond(now, corner_watch.target_is_visible())
	else:
		state.activate(now, rng) if state.stage != ReactionState.Stage.TARGET else state.respond(now)
	if state.reactions_us.size() > samples_before:
		var new_sample_index := state.reactions_us.size() - 1
		_show_score_flight(new_sample_index, state.reactions_us[new_sample_index])
	if state.stage == ReactionState.Stage.NEXT:
		state.start_wait(now, rng)
	if page == "corner" and target_was_active and state.stage != ReactionState.Stage.TARGET:
		corner_watch.defeat_target()
	_refresh_project()


func _handle_osu_input(event: InputEvent) -> void:
	var now := Time.get_ticks_usec()
	if osu_state.stage == OsuState.Stage.READY or osu_state.stage == OsuState.Stage.INVALID or osu_state.stage == OsuState.Stage.NEXT:
		if _reaction_event(event):
			osu_state.begin_round()
			_spawn_osu_circles()
			_refresh_project()
		return
	if osu_state.stage != OsuState.Stage.ACTIVE:
		return
	var samples_before: int = osu_state.reactions_us.size()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit_index: int = _osu_circle_at(osu_page.get_local_mouse_position())
		if hit_index + 1 == osu_state.expected:
			osu_state.hit_next(now)
			_mark_osu_hit(hit_index)
		else:
			osu_state.miss()
			_clear_osu_circles()
	elif _keyboard_react(event):
		var hit_index: int = osu_state.expected - 1
		osu_state.hit_next(now)
		_mark_osu_hit(hit_index)
	else:
		return
	if osu_state.reactions_us.size() > samples_before:
		var new_sample_index: int = osu_state.reactions_us.size() - 1
		_show_score_flight(new_sample_index, osu_state.reactions_us[new_sample_index])
		_clear_osu_circles()
	if osu_state.stage == OsuState.Stage.INVALID:
		_clear_osu_circles()
	_refresh_project()


func _handle_sphere_input(event: InputEvent) -> void:
	var now := Time.get_ticks_usec()
	if sphere_state.stage == SphereState.Stage.READY or sphere_state.stage == SphereState.Stage.INVALID or sphere_state.stage == SphereState.Stage.NEXT:
		if _reaction_event(event):
			sphere_state.start_wait(now, rng)
			_refresh_project()
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		if sphere_state.stage == SphereState.Stage.WAITING and _keyboard_react(event):
			sphere_state.try_fire(now)
			sphere_aim.clear_targets()
			_refresh_project()
		return
	var samples_before: int = sphere_state.reactions_us.size()
	if not sphere_state.try_fire(now):
		return
	if sphere_state.stage == SphereState.Stage.INVALID:
		sphere_aim.clear_targets()
		_refresh_project()
		return
	var hit: int = sphere_aim.fire_ray()
	if hit >= 0:
		sphere_state.register_hit(now)
	if sphere_state.reactions_us.size() > samples_before:
		var new_sample_index: int = sphere_state.reactions_us.size() - 1
		_show_score_flight(new_sample_index, sphere_state.reactions_us[new_sample_index])
		sphere_aim.clear_targets()
	_refresh_project()


func _refresh_project() -> void:
	if page == "color" and state.stage == ReactionState.Stage.INVALID:
		_reset_trial_list()
	if page == "corner" and state.stage == ReactionState.Stage.INVALID:
		_reset_trial_list()
	if page == "osu" and osu_state.stage == OsuState.Stage.INVALID:
		_reset_trial_list()
	if page == "spheres" and sphere_state.stage == SphereState.Stage.INVALID:
		_reset_trial_list()
	match page:
		"color":
			_refresh_color()
		"corner":
			_refresh_corner()
		"osu":
			_refresh_osu()
		"spheres":
			_refresh_spheres()


func _refresh_color() -> void:
	var title := "COLOR REACTION"
	var hint := "Press SPACE, Z, X, an arrow key, or click to begin."
	var background := DARK
	match state.stage:
		ReactionState.Stage.WAITING:
			title = "WAIT"
			hint = "Do not press yet."
			background = Color("#ba353e")
		ReactionState.Stage.TARGET:
			title = "NOW"
			hint = "PRESS OR CLICK"
			background = Color("#21aa5e")
		ReactionState.Stage.NEXT:
			title = "NEXT TRIAL"
			hint = "Press when ready."
		ReactionState.Stage.INVALID:
			title = "ROUND INVALID"
			hint = "False start or timeout. Press to retry."
	color_background.color = background
	color_title.text = title
	color_hint.text = hint
	color_dots.text = _dots(state.reactions_us.size())


func _refresh_corner() -> void:
	var title := "CORNER WATCH"
	var hint := "Move the mouse. Click when the enemy appears."
	if state.stage == ReactionState.Stage.NEXT:
		title = "NEXT TRIAL"
		hint = "Click when ready."
	elif state.stage == ReactionState.Stage.INVALID:
		title = "ROUND INVALID"
		hint = "False start, miss, or timeout. Click to retry."
	elif state.stage == ReactionState.Stage.WAITING:
		title = "WAIT"
		hint = "Do not fire yet."
	elif state.stage == ReactionState.Stage.TARGET:
		title = "FIRE"
		hint = "Shoot the target."
	hud_title.text = title
	hud_hint.text = hint
	hud_dots.text = _dots(state.reactions_us.size())
	hud_footer.text = "MOUSE: LIMITED LOOK | LMB: FIRE | ESC: MENU"


func _refresh_osu() -> void:
	var title := "OSU"
	var hint := "Press SPACE, Z, X, an arrow key, or click to begin."
	match osu_state.stage:
		OsuState.Stage.ACTIVE:
			title = "HIT %d / %d" % [osu_state.expected, OsuState.TARGETS]
			hint = "Click circles in order, or use react keys for the next circle."
		OsuState.Stage.NEXT:
			title = "NEXT TRIAL"
			hint = "Press when ready."
		OsuState.Stage.INVALID:
			title = "ROUND INVALID"
			hint = "Wrong circle. Press to retry."
	osu_title.text = title
	osu_hint.text = hint
	osu_dots.text = _dots(osu_state.reactions_us.size())


func _refresh_spheres() -> void:
	var title := "SPHERE AIM"
	var hint := "Press SPACE, Z, X, an arrow key, or click to begin."
	match sphere_state.stage:
		SphereState.Stage.WAITING:
			title = "WAIT"
			hint = "Do not fire yet."
		SphereState.Stage.AIMING:
			title = "CLEAR TARGETS"
			hint = "Aim and fire. %d left." % sphere_state.hits_remaining
		SphereState.Stage.NEXT:
			title = "NEXT TRIAL"
			hint = "Click when ready."
		SphereState.Stage.INVALID:
			title = "ROUND INVALID"
			hint = "Early fire or timeout. Click to retry."
	hud_title.text = title
	hud_hint.text = hint
	hud_dots.text = _dots(sphere_state.reactions_us.size())
	hud_footer.text = "MOUSE: LIMITED LOOK | LMB: FIRE | ESC: MENU"


func _dots(completed: int) -> String:
	return " ".join(PackedStringArray(Array(range(5)).map(func(index: int) -> String: return "●" if index < completed else "○")))


func _active_samples() -> Array[int]:
	match page:
		"osu":
			return osu_state.reactions_us
		"spheres":
			return sphere_state.reactions_us
		_:
			return state.reactions_us


func _score_key() -> String:
	match page:
		"color":
			return "color"
		"corner":
			return "shooter"
		"osu":
			return "osu"
		"spheres":
			return "spheres"
		_:
			return "color"


func _summary_visible() -> bool:
	match page:
		"color", "corner":
			return state.stage == ReactionState.Stage.SUMMARY
		"osu":
			return osu_state.stage == OsuState.Stage.SUMMARY
		"spheres":
			return sphere_state.stage == SphereState.Stage.SUMMARY
		_:
			return false


func _reaction_event(event: InputEvent) -> bool:
	if event.is_action_pressed("react"):
		return true
	return _keyboard_react(event)


func _keyboard_react(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_Z, KEY_X]


func _ensure_input_actions() -> void:
	if not InputMap.has_action("react"):
		InputMap.add_action("react")
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
	for keycode in [KEY_SPACE, KEY_Z, KEY_X, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		var event := InputEventKey.new()
		event.keycode = keycode
		if not InputMap.action_has_event("react", event):
			InputMap.action_add_event("react", event)
	var fire := InputEventMouseButton.new()
	fire.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("react", fire):
		InputMap.action_add_event("react", fire)
	if not InputMap.action_has_event("fire", fire):
		InputMap.action_add_event("fire", fire)


func _build_menu() -> void:
	_add_full_rect(menu, DARK)
	var title := _label("NEKO / BENCHMARK", 34, INK)
	title.position = Vector2(0, 48)
	title.size = Vector2(1280, 48)
	menu.add_child(title)
	var subtitle := _label("SELECT A TEST", 18, MUTED)
	subtitle.position = Vector2(0, 100)
	subtitle.size = Vector2(1280, 28)
	menu.add_child(subtitle)
	var projects := [
		{"id": "color", "name": "COLOR REACTION"},
		{"id": "corner", "name": "CORNER WATCH"},
		{"id": "osu", "name": "OSU"},
		{"id": "spheres", "name": "SPHERE AIM"},
	]
	menu_buttons.clear()
	for index in projects.size():
		var button := Button.new()
		button.position = Vector2(340, 145 + index * 110)
		button.size = Vector2(600, 92)
		button.text = projects[index].name
		button.add_theme_font_size_override("font_size", 22)
		button.pressed.connect(enter_project.bind(projects[index].id))
		menu.add_child(button)
		menu_buttons.append(button)
	var footer := _label("Choose a test with the mouse.  ESC: QUIT", 15, MUTED)
	footer.position = Vector2(0, 680)
	footer.size = Vector2(1280, 28)
	menu.add_child(footer)


func _build_color_page() -> void:
	color_background = _add_full_rect(color_reaction, DARK)
	color_title = _label("", 48, INK)
	color_title.position = Vector2(0, 275)
	color_title.size = Vector2(1280, 62)
	color_reaction.add_child(color_title)
	color_hint = _label("", 20, INK)
	color_hint.position = Vector2(0, 350)
	color_hint.size = Vector2(1280, 34)
	color_reaction.add_child(color_hint)
	color_dots = _label("", 24, ACCENT)
	color_dots.position = Vector2(0, 405)
	color_dots.size = Vector2(1280, 36)
	color_reaction.add_child(color_dots)
	var footer := _label("ESC: MENU", 15, MUTED)
	footer.position = Vector2(0, 650)
	footer.size = Vector2(1280, 26)
	color_reaction.add_child(footer)


func _build_osu_page() -> void:
	osu_background = _add_full_rect(osu_page, DARK)
	osu_circles_root = Control.new()
	osu_circles_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	osu_circles_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	osu_page.add_child(osu_circles_root)
	osu_title = _label("", 32, INK)
	osu_title.position = Vector2(0, 36)
	osu_title.size = Vector2(1280, 40)
	osu_page.add_child(osu_title)
	osu_hint = _label("", 16, INK)
	osu_hint.position = Vector2(0, 78)
	osu_hint.size = Vector2(1280, 28)
	osu_page.add_child(osu_hint)
	osu_dots = _label("", 22, ACCENT)
	osu_dots.position = Vector2(0, 110)
	osu_dots.size = Vector2(1280, 30)
	osu_page.add_child(osu_dots)
	var footer := _label("LMB: HIT CIRCLE | REACT KEYS: NEXT | ESC: MENU", 14, MUTED)
	footer.position = Vector2(0, 680)
	footer.size = Vector2(1280, 24)
	osu_page.add_child(footer)


func _build_hud() -> void:
	var hud: Control = $CanvasLayer/HUD
	hud_title = _label("", 28, INK)
	hud_title.position = Vector2(0, 42)
	hud_title.size = Vector2(1280, 38)
	hud.add_child(hud_title)
	hud_hint = _label("", 16, INK)
	hud_hint.position = Vector2(0, 84)
	hud_hint.size = Vector2(1280, 28)
	hud.add_child(hud_hint)
	hud_dots = _label("", 22, ACCENT)
	hud_dots.position = Vector2(0, 122)
	hud_dots.size = Vector2(1280, 30)
	hud.add_child(hud_dots)
	var crosshair := _label("+", 28, INK)
	crosshair.position = Vector2(620, 345)
	crosshair.size = Vector2(40, 40)
	hud.add_child(crosshair)
	hud_footer = _label("MOUSE: LIMITED LOOK | LMB: FIRE | ESC: MENU", 14, INK)
	hud_footer.position = Vector2(0, 680)
	hud_footer.size = Vector2(1280, 24)
	hud.add_child(hud_footer)


func _build_summary() -> void:
	_add_full_rect(summary, DARK)
	summary_text = _label("", 20, INK)
	summary_text.position = Vector2(0, 135)
	summary_text.size = Vector2(1280, 440)
	summary_text.add_theme_constant_override("line_spacing", 10)
	summary.add_child(summary_text)


func _build_trial_list() -> void:
	var background := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	background.add_theme_stylebox_override("panel", style)
	background.position = Vector2(16, 235)
	background.size = Vector2(228, 218)
	trial_list.add_child(background)
	var title := _label("ROUND RESULTS", 13, MUTED)
	title.position = Vector2(20, 247)
	title.size = Vector2(220, 24)
	trial_list.add_child(title)
	for index in 5:
		var row := _label("ROUND %d  --" % (index + 1), 14, INK)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.position = Vector2(28, 280 + index * 32)
		row.size = Vector2(210, 24)
		trial_list.add_child(row)
		trial_rows.append(row)
	flight_score = _label("", 30, ACCENT)
	flight_score.size = Vector2(220, 48)
	flight_score_layer.add_child(flight_score)


func _spawn_osu_circles() -> void:
	_clear_osu_circles()
	var min_dist := OSU_RADIUS * 2.0 + OSU_PAD
	var area := Rect2(280, 160, 720, 460)
	var attempts := 0
	while osu_centers.size() < OsuState.TARGETS and attempts < 800:
		attempts += 1
		var center := Vector2(
			rng.randf_range(area.position.x + OSU_RADIUS, area.end.x - OSU_RADIUS),
			rng.randf_range(area.position.y + OSU_RADIUS, area.end.y - OSU_RADIUS)
		)
		var ok := true
		for other in osu_centers:
			if center.distance_to(other) < min_dist:
				ok = false
				break
		if not ok:
			continue
		osu_centers.append(center)
	# ponytail: if RNG packing fails, fall back to a fixed 2x3 grid so the round is always playable.
	if osu_centers.size() < OsuState.TARGETS:
		osu_centers.clear()
		for index in OsuState.TARGETS:
			var col: int = index % 3
			var row: int = int(index / 3)
			osu_centers.append(Vector2(400.0 + col * 200.0, 260.0 + row * 180.0))
	for index in osu_centers.size():
		var circle := _make_osu_circle(index + 1, osu_centers[index])
		osu_circles_root.add_child(circle)
		osu_circle_nodes.append(circle)


func _make_osu_circle(number: int, center: Vector2) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = center - Vector2(OSU_RADIUS, OSU_RADIUS)
	root.size = Vector2(OSU_RADIUS * 2.0, OSU_RADIUS * 2.0)
	var ring := ColorRect.new()
	ring.color = ACCENT
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ring)
	# ponytail: ColorRect is square; visual is circle-ish enough via number label. Upgrade: draw_circle in _draw.
	var fill := ColorRect.new()
	fill.color = DARK
	fill.position = Vector2(6, 6)
	fill.size = Vector2(OSU_RADIUS * 2.0 - 12.0, OSU_RADIUS * 2.0 - 12.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	var label := _label(str(number), 28, INK)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(label)
	return root


func _osu_circle_at(point: Vector2) -> int:
	for index in osu_centers.size():
		if point.distance_to(osu_centers[index]) <= OSU_RADIUS:
			return index
	return -1


func _mark_osu_hit(index: int) -> void:
	if index < 0 or index >= osu_circle_nodes.size():
		return
	var node := osu_circle_nodes[index]
	for child in node.get_children():
		if child is ColorRect and child.color == ACCENT:
			child.color = MUTED


func _clear_osu_circles() -> void:
	for node in osu_circle_nodes:
		node.queue_free()
	osu_circle_nodes.clear()
	osu_centers.clear()


func _reset_trial_list() -> void:
	if score_flight:
		score_flight.kill()
	score_flight_active = false
	flight_score_layer.hide()
	for index in trial_rows.size():
		trial_rows[index].text = "ROUND %d  --" % (index + 1)


func _show_score_flight(index: int, reaction_us: int) -> void:
	var score_text := "%.1f ms" % (float(reaction_us) / 1000.0)
	if score_flight:
		score_flight.kill()
	score_flight_active = true
	flight_score_layer.show()
	flight_score.text = score_text
	flight_score.position = Vector2(530, 328)
	score_flight = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	score_flight.tween_property(flight_score, "position", Vector2(28, 280 + index * 32), 0.5)
	score_flight.tween_callback(_finish_score_flight.bind(index, score_text))


func _finish_score_flight(index: int, score_text: String) -> void:
	trial_rows[index].text = "ROUND %d  %s" % [index + 1, score_text]
	flight_score_layer.hide()
	score_flight_active = false


func _update_best_scores() -> void:
	var labels := [
		{"name": "COLOR REACTION", "key": "color"},
		{"name": "CORNER WATCH", "key": "shooter"},
		{"name": "OSU", "key": "osu"},
		{"name": "SPHERE AIM", "key": "spheres"},
	]
	for index in menu_buttons.size():
		var best := scores.get_best(labels[index].key)
		menu_buttons[index].text = "%s\nBEST: %s" % [labels[index].name, "--" if best == 0.0 else "%.1f ms" % best]


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", load("res://assets/MapleMono-Regular.ttf"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _add_full_rect(parent: Control, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(rect)
	return rect
