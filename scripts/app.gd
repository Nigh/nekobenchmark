extends Node

const INK := Color("#ebf0f9")
const MUTED := Color("#97a6bd")
const ACCENT := Color("#7790ff")
const DARK := Color("#0b101e")

@onready var menu: Control = $Menu
@onready var color_reaction: Control = $ColorReaction
@onready var corner_watch: CornerWatch = $CornerWatch
@onready var summary: Control = $Summary
@onready var trial_list: Control = $TrialList
@onready var flight_score_layer: Control = $FlightScore

var rng := RandomNumberGenerator.new()
var state := ReactionState.new()
var scores := ScoreStore.new()
var page := ""
var color_background: ColorRect
var color_title: Label
var color_hint: Label
var color_dots: Label
var hud_title: Label
var hud_hint: Label
var hud_dots: Label
var summary_text: Label
var trial_rows: Array[Label] = []
var flight_score: Label
var score_flight: Tween
var score_flight_active := false


func _ready() -> void:
	rng.randomize()
	scores.load_scores()
	_ensure_input_actions()
	Input.use_accumulated_input = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_build_menu()
	_build_color_page()
	_build_hud()
	_build_summary()
	_build_trial_list()
	show_menu()


func _process(_delta: float) -> void:
	if page.is_empty():
		return
	var now := Time.get_ticks_usec()
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
	if event.is_action_pressed("restart") and state.stage == ReactionState.Stage.SUMMARY:
		state.reset()
		summary.hide()
		_reset_trial_list()
		if page == "corner":
			$CanvasLayer/HUD.show()
		_refresh_project()
		return
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


func show_menu() -> void:
	page = ""
	state.reset()
	menu.show()
	color_reaction.hide()
	summary.hide()
	trial_list.hide()
	flight_score_layer.hide()
	corner_watch.set_active(false)
	$CanvasLayer/HUD.hide()
	_update_best_scores()


func enter_project(project: String) -> void:
	page = project
	state.reset()
	_reset_trial_list()
	menu.hide()
	summary.hide()
	trial_list.show()
	if page == "color":
		color_reaction.show()
		$CanvasLayer/HUD.hide()
		corner_watch.set_active(false)
	else:
		color_reaction.hide()
		$CanvasLayer/HUD.show()
		corner_watch.set_active(true)
	_refresh_project()


func complete_summary() -> void:
	if not summary.visible and not score_flight_active:
		var result := ScoreStore.statistics(state.reactions_us)
		scores.update("color" if page == "color" else "shooter", result.median)
		summary_text.text = "FIVE-TRIAL RESULT\n\n%.1f ms\nMEDIAN REACTION TIME\n\nMEAN  %.1f ms\nSTD DEV  %.1f ms\n\nR: RETRY    ESC: MENU" % [result.median, result.mean, result.deviation]
		$CanvasLayer/HUD.hide()
		summary.show()


func _refresh_project() -> void:
	if state.stage == ReactionState.Stage.INVALID:
		_reset_trial_list()
	if page == "color":
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
		color_dots.text = _dots()
	else:
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
		hud_dots.text = _dots()


func _dots() -> String:
	return " ".join(PackedStringArray(Array(range(ReactionState.TRIALS)).map(func(index: int) -> String: return "●" if index < state.reactions_us.size() else "○")))


func _reaction_event(event: InputEvent) -> bool:
	if event.is_action_pressed("react"):
		return true
	return event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]


func _ensure_input_actions() -> void:
	for keycode in [KEY_SPACE, KEY_Z, KEY_X, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		var event := InputEventKey.new()
		event.keycode = keycode
		InputMap.action_add_event("react", event)
	var fire := InputEventMouseButton.new()
	fire.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("react", fire)
	InputMap.action_add_event("fire", fire)


func _build_menu() -> void:
	_add_full_rect(menu, DARK)
	var title := _label("NEKO / BENCHMARK", 34, INK)
	title.position = Vector2(0, 85)
	title.size = Vector2(1280, 48)
	menu.add_child(title)
	var subtitle := _label("SELECT A TEST", 18, MUTED)
	subtitle.position = Vector2(0, 140)
	subtitle.size = Vector2(1280, 28)
	menu.add_child(subtitle)
	for index in 2:
		var button := Button.new()
		button.position = Vector2(340, 205 + index * 125)
		button.size = Vector2(600, 100)
		button.text = "COLOR REACTION" if index == 0 else "CORNER WATCH"
		button.add_theme_font_size_override("font_size", 25)
		button.pressed.connect(enter_project.bind("color" if index == 0 else "corner"))
		menu.add_child(button)
	var footer := _label("Choose a test with the mouse.  ESC: QUIT", 15, MUTED)
	footer.position = Vector2(0, 650)
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
	var footer := _label("MOUSE: LIMITED LOOK | LMB: FIRE | ESC: MENU", 14, INK)
	footer.position = Vector2(0, 680)
	footer.size = Vector2(1280, 24)
	hud.add_child(footer)


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
	for index in ReactionState.TRIALS:
		var row := _label("ROUND %d  --" % (index + 1), 14, INK)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.position = Vector2(28, 280 + index * 32)
		row.size = Vector2(210, 24)
		trial_list.add_child(row)
		trial_rows.append(row)
	flight_score = _label("", 30, ACCENT)
	flight_score.size = Vector2(220, 48)
	flight_score_layer.add_child(flight_score)


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
	for child in menu.get_children():
		if child is Button:
			var button: Button = child
			var is_color: bool = button.text.begins_with("COLOR")
			var best := scores.color if is_color else scores.shooter
			button.text = "%s\nBEST: %s" % ["COLOR REACTION" if is_color else "CORNER WATCH", "--" if best == 0.0 else "%.1f ms" % best]


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
