extends Node

# ponytail: preload instead of class_name so parse works before .godot class cache exists.
const ReactionState = preload("res://scripts/reaction_state.gd")
const OsuState = preload("res://scripts/osu_state.gd")
const SphereState = preload("res://scripts/sphere_state.gd")
const ScoreStore = preload("res://scripts/score_store.gd")
const Camera3DConfig = preload("res://scripts/camera_3d_config.gd")
const CornerWatch = preload("res://scripts/corner_watch.gd")
const SphereAim = preload("res://scripts/sphere_aim.gd")
const SensLab = preload("res://scripts/sens_lab.gd")

const Palette = preload("res://scripts/app_theme.gd")
const TrackingState = preload("res://scripts/tracking_state.gd")
const HistoryStore = preload("res://scripts/history_store.gd")
const HistoryPage = preload("res://scripts/history_page.gd")
const TrendChart = preload("res://scripts/trend_chart.gd")
const ResultCache = preload("res://scripts/result_cache.gd")
const UIAudio = preload("res://scripts/ui_audio.gd")
const Radar = preload("res://scripts/result_radar.gd")
const INK := Palette.INK
const MUTED := Palette.MUTED
const ACCENT := Palette.PRIMARY
const DARK := Palette.BASE
const OSU_RADIUS := 48.0
const OSU_SPACING := 360.0
const OSU_FADE_SEC := 0.28
const OSU_GATE_COLOR := Palette.SUCCESS

@onready var menu: Control = $Menu
@onready var color_reaction: Control = $ColorReaction
@onready var osu_page: Control = $Osu
@onready var corner_watch: CornerWatch = $CornerWatch
@onready var sphere_aim: SphereAim = $SphereAim
@onready var sens_lab: SensLab = $SensLab
@onready var tracking: Node3D = $Tracking
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
var color_footer: Label
var osu_background: ColorRect
var osu_title: Label
var osu_hint: Label
var osu_dots: Label
var osu_circles_root: Control
var osu_centers: Array[Vector2] = []
var osu_circle_nodes: Array[Control] = []
var osu_gate_center := Vector2.ZERO
var osu_gate_node: Control = null
var hud_title: Label
var hud_hint: Label
var hud_dots: Label
var hud_footer: Label
var summary_text: Label
var summary_radar: Control
var trial_rows: Array[Label] = []
var live_timer: Label
var flight_score: Label
var score_flight: Tween
var score_flight_active := false
var menu_buttons: Array[Button] = []
var sens_slider_layer: Control
var sens_slider: HSlider
var sens_slider_label: Label
var sens_slider_panel: Panel
var sens_slider_panel_style: StyleBoxFlat
var sens_slider_dragging := false
var sens_chrome_tween: Tween
var sens_chrome_full := false
var sens_last_adjust_sec := -INF
var profile_rows: Array[Label] = []
var result_cache = ResultCache.new()
var last_menu_refresh_us := -1_000_000
var menu_notice := ""
var tracking_state = TrackingState.new()
var history = HistoryStore.new()
var history_page: Control
var settings_page: Control
var settings_value: Label
var settings_slider: HSlider
var result_snapshot: Dictionary = {}
var menu_tag: LineEdit
var save_button: Button
var save_status: Label
var audio: Node
var sens_save_failed := false
var storage_status: Label
var summary_time: Label
var osu_cursor_position := Vector2.ZERO

const SENS_PANEL_ALPHA_DIM := 0.16
const SENS_PANEL_ALPHA_FULL := 0.72
const SENS_CHROME_HOLD_SEC := 2.0


func _ready() -> void:
	rng.randomize()
	scores.load_scores()
	history.load_history()
	audio = UIAudio.new()
	add_child(audio)
	sens_lab.set_layout(scores.lab_spacing, scores.lab_distance)
	var app_theme := Palette.create()
	for root in [menu, color_reaction, osu_page, summary, trial_list, flight_score_layer, $CanvasLayer/HUD]:
		root.theme = app_theme
	_apply_look_sensitivity()
	_ensure_input_actions()
	Input.use_accumulated_input = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_build_menu()
	_build_color_page()
	_build_osu_page()
	_build_hud()
	_build_sens_slider()
	_build_summary()
	_build_trial_list()
	_build_settings()
	history_page = HistoryPage.new()
	add_child(history_page)
	history_page.setup(history)
	history_page.back_requested.connect(show_menu)
	audio.bind_controls(self)
	show_menu()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var expired := result_cache.prune(now)
	if page == "sens":
		_sync_sens_alt_cursor()
		_update_sens_chrome()
	if page.is_empty():
		if expired or now - last_menu_refresh_us >= 1_000_000:
			_update_best_scores(now)
		return
	if summary.visible:
		return
	_update_live_trial_time(now)
	if page == "color" or page == "corner":
		if state.advance(now):
			if state.stage == ReactionState.Stage.INVALID:
				audio.response(false)
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
				audio.response(false)
				sphere_aim.clear_targets()
			_refresh_project()
		if sphere_state.stage == SphereState.Stage.SUMMARY:
			complete_summary()
	elif page == "osu":
		if osu_state.advance(now):
			if osu_state.stage == OsuState.Stage.ACTIVE:
				_spawn_osu_circles()
			else:
				_clear_osu_circles()
				audio.response(false)
			_refresh_project()
		if osu_state.stage == OsuState.Stage.SUMMARY:
			complete_summary()

	elif page == "tracking":
		var preparing: bool = tracking_state.stage == TrackingState.Stage.PREPARING
		var acquired_before: int = tracking_state.acquired_us
		tracking.move_target(tracking_state.coverage.size(), tracking_state.movement_seconds(now))
		if tracking_state.advance(now, tracking.score_weight(), tracking.error_degrees()):
			var index: int = tracking_state.coverage.size() - 1
			_show_score_text_flight(index, ScoreStore.display("tracking", tracking_state.coverage[index]))
			if tracking_state.stage == TrackingState.Stage.PREPARING:
				tracking.move_target(tracking_state.coverage.size(), 0.0)
		if preparing and tracking_state.stage == TrackingState.Stage.ACTIVE:
			audio.play("start")
		elif preparing and tracking_state.acquired_us > acquired_before:
			audio.play("slide")
		tracking.set_feedback(tracking_state.stage == TrackingState.Stage.ACTIVE, tracking_state.acquired_us / 1_000_000.0)
		_refresh_tracking()
		if tracking_state.stage == TrackingState.Stage.SUMMARY:
			complete_summary()


func _sync_sens_alt_cursor() -> void:
	var alt_held := Input.is_key_pressed(KEY_ALT)
	if alt_held == sens_lab.cursor_mode:
		return
	sens_lab.set_cursor_mode(alt_held)
	_set_sens_slider_interactive(alt_held)
	if not alt_held:
		sens_slider_dragging = false
	_refresh_sens()


func _input(event: InputEvent) -> void:
	if page == "osu" and (event is InputEventMouseMotion or event is InputEventMouseButton):
		# Preserve input-event order; polling the cursor can include motion queued after a key press.
		osu_cursor_position = osu_page.get_global_transform_with_canvas().affine_inverse() * event.position
	if page != "sens" or not sens_lab.cursor_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var over := _sens_slider_hit(event.position)
		if event.pressed and over:
			audio.play("press")
			sens_slider_dragging = true
			_apply_sens_slider_at(event.position.x)
			get_viewport().set_input_as_handled()
		elif not event.pressed:
			sens_slider_dragging = false
	elif event is InputEventMouseMotion and sens_slider_dragging:
		_apply_sens_slider_at(event.position.x)
		get_viewport().set_input_as_handled()


func _sens_slider_hit(pos: Vector2) -> bool:
	if sens_slider == null:
		return false
	return Rect2(sens_slider.global_position, sens_slider.size).grow(8.0).has_point(pos)


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
	if page == "sens":
		_handle_sens_input(event)
		return
	if event.is_action_pressed("restart") and _summary_visible():
		_restart_project()
		return
	if summary.visible:
		return
	match page:
		"tracking":
			pass
		"color", "corner":
			_handle_reaction_input(event)
		"osu":
			_handle_osu_input(event)
		"spheres":
			_handle_sphere_input(event)


func show_menu() -> void:
	page = ""
	result_snapshot.clear()
	tracking_state.reset()
	tracking.set_active(false)
	settings_page.hide()
	history_page.hide()
	_reset_trial_list()
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
	sens_slider_layer.hide()
	corner_watch.set_active(false)
	sphere_aim.set_active(false)
	sens_lab.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$CanvasLayer/HUD.hide()
	_update_trial_list_opacity()
	_update_best_scores()


func enter_project(project: String) -> void:
	if project == "sens":
		enter_sens_lab()
		return
	page = project
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	result_snapshot.clear()
	tracking_state.reset()
	tracking.set_active(page == "tracking")
	if page == "tracking":
		tracking_state.prepare(Time.get_ticks_usec())
		tracking.set_feedback(false, 0.0)
	settings_page.hide()
	history_page.hide()
	state.reset()
	osu_state.reset()
	sphere_state.reset()
	_clear_osu_circles()
	_reset_trial_list()
	menu.hide()
	summary.hide()
	sens_slider_layer.hide()
	trial_list.show()
	color_reaction.visible = page == "color"
	osu_page.visible = page == "osu"
	if page == "osu":
		osu_cursor_position = osu_page.get_local_mouse_position()
	corner_watch.set_active(page == "corner")
	sphere_aim.set_active(page == "spheres")
	sens_lab.set_active(false)
	_apply_look_sensitivity()
	_update_trial_list_opacity()
	$CanvasLayer/HUD.visible = page in ["corner", "spheres", "tracking"]
	_refresh_project()


func enter_sens_lab() -> void:
	page = "sens"
	result_snapshot.clear()
	tracking.set_active(false)
	settings_page.hide()
	history_page.hide()
	_reset_trial_list()
	state.reset()
	osu_state.reset()
	sphere_state.reset()
	_clear_osu_circles()
	menu.hide()
	summary.hide()
	trial_list.hide()
	color_reaction.hide()
	osu_page.hide()
	corner_watch.set_active(false)
	sphere_aim.set_active(false)
	_apply_look_sensitivity()
	sens_lab.set_active(true)
	sens_slider_layer.show()
	_sync_sens_slider()
	_set_sens_slider_interactive(false)
	sens_last_adjust_sec = -INF
	sens_chrome_full = true
	_set_sens_chrome_visible(false)
	$CanvasLayer/HUD.show()
	_refresh_sens()


func complete_summary() -> void:
	if summary.visible or not _summary_visible():
		return
	_freeze_result()
	if score_flight_active or result_snapshot.is_empty():
		return
	var result: Dictionary = result_snapshot.stats
	var key := _score_key()
	var unit := "%" if key == "tracking" else "ms"
	var radar_results := result_cache.selected(Time.get_ticks_usec())
	for index in radar_results.size():
		if radar_results[index].project == key:
			radar_results[index] = result_snapshot
	summary_radar.set_results(radar_results)
	summary_text.add_theme_color_override("font_color", Palette.PROJECT_COLORS[key])
	summary_text.text = "%s / FIVE-ROUND RESULT\n\n%s\nFROM FIVE-ROUND MEDIAN\n\nMEAN  %.1f %s    STD DEV  %.1f %s" % [_project_name(key), ScoreStore.display(key, result.median), result.mean, unit, result.deviation, unit]
	if key == "tracking":
		var average := 0.0
		for degrees in result_snapshot.errors_degrees:
			average += degrees / 5.0
		summary_text.text += "\nMEAN ANGULAR ERROR  %.2f deg" % average
	summary_time.text = "Completed: %s (local time)" % result_snapshot.local_time
	$CanvasLayer/HUD.hide()
	corner_watch.active = false
	sphere_aim.active = false
	tracking.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	summary.show()
	_update_trial_list_opacity()


func _freeze_result() -> void:
	if not result_snapshot.is_empty():
		return
	var key := _score_key()
	var samples: Array = tracking_state.coverage if key == "tracking" else _active_samples()
	if samples.size() == 5:
		var completed_us := Time.get_ticks_usec()
		result_snapshot = HistoryStore.snapshot(key, samples, scores.look_sens, tracking_state.errors if key == "tracking" else [])
		result_cache.add(result_snapshot, completed_us)
		menu_notice = ""


func _save_session() -> void:
	if not page.is_empty():
		return
	var selected := result_cache.selected(Time.get_ticks_usec())
	if selected.size() != ScoreStore.PROJECTS.size():
		menu_notice = "Complete all five tests within one hour before saving."
	elif history.save_session(selected, menu_tag.text):
		result_cache.clear()
		menu_tag.clear()
		menu_notice = "Session saved. Complete five tests to save another."
	else:
		menu_notice = history.error
	_update_best_scores()


func _project_name(key: String) -> String:
	for mode in ScoreStore.PROJECTS:
		if mode.key == key:
			return mode.name
	return key


func _restart_project() -> void:
	enter_project(page)


func _handle_reaction_input(event: InputEvent) -> void:
	if not _reaction_event(event):
		return
	var now := Time.get_ticks_usec()
	var target_was_active := state.stage == ReactionState.Stage.TARGET
	var samples_before := state.reactions_us.size()
	if page == "corner" and state.stage == ReactionState.Stage.TARGET:
		state.respond(now, corner_watch.target_is_visible())
	else:
		state.respond(now) if state.stage in [ReactionState.Stage.TARGET, ReactionState.Stage.WAITING] else state.activate(now, rng)
	if state.stage == ReactionState.Stage.WAITING and not state.reactions_us.size() > samples_before:
		audio.play("start")
	else:
		audio.response(state.stage != ReactionState.Stage.INVALID)
	if state.reactions_us.size() > samples_before:
		var new_sample_index := state.reactions_us.size() - 1
		_show_score_flight(new_sample_index, state.reactions_us[new_sample_index])
	if state.stage == ReactionState.Stage.NEXT:
		state.start_wait(now, rng)
		audio.play("start")
	if page == "corner" and target_was_active and state.stage != ReactionState.Stage.TARGET:
		corner_watch.defeat_target()
	_refresh_project()


func _handle_osu_input(event: InputEvent) -> void:
	var now := Time.get_ticks_usec()
	if osu_state.stage == OsuState.Stage.READY or osu_state.stage == OsuState.Stage.INVALID:
		if _reaction_event(event):
			_begin_osu_gate()
			audio.response(true)
		return
	var is_click: bool = (
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
		or _keyboard_react(event)
	)
	if not is_click:
		return
	var point := osu_cursor_position
	if event is InputEventMouseButton:
		point = osu_page.get_global_transform_with_canvas().affine_inverse() * event.position
	if osu_state.stage == OsuState.Stage.WAITING:
		osu_state.early_input()
		audio.response(false)
		_clear_osu_circles()
		_refresh_project()
		return
	if osu_state.stage == OsuState.Stage.GATE:
		var gate_hit := _osu_gate_hit(point)
		if gate_hit:
			osu_state.begin_wait(now, rng)
			_clear_osu_circles()
		audio.play("start") if gate_hit else audio.response(false)
		_refresh_project()
		return
	if osu_state.stage != OsuState.Stage.ACTIVE:
		return
	# Mouse and react keys both require the cursor to be on the next circle.
	var samples_before: int = osu_state.reactions_us.size()
	var hit_index: int = _osu_circle_at(point)
	if hit_index + 1 == osu_state.expected:
		osu_state.hit_next(now)
		_mark_osu_hit(hit_index)
		_show_osu_guide_line()
		_refresh_osu_visibility()
	else:
		osu_state.miss()
		_clear_osu_circles()
	audio.response(osu_state.stage != OsuState.Stage.INVALID)
	if osu_state.reactions_us.size() > samples_before:
		var new_sample_index: int = osu_state.reactions_us.size() - 1
		_show_score_flight(new_sample_index, osu_state.reactions_us[new_sample_index])
		if osu_state.stage == OsuState.Stage.NEXT:
			_begin_osu_gate()
			return
	if osu_state.stage == OsuState.Stage.INVALID:
		_clear_osu_circles()
	_refresh_project()


func _begin_osu_gate() -> void:
	osu_state.start_gate()
	_spawn_osu_gate()
	_refresh_project()


func _handle_sphere_input(event: InputEvent) -> void:
	var now := Time.get_ticks_usec()
	if sphere_state.stage == SphereState.Stage.READY or sphere_state.stage == SphereState.Stage.INVALID:
		if _reaction_event(event):
			_begin_sphere_gate()
			audio.response(true)
		return
	var is_fire: bool = (
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
		or _keyboard_react(event)
	)
	if not is_fire:
		return
	var samples_before: int = sphere_state.reactions_us.size()
	if not sphere_state.try_fire(now):
		return
	if sphere_state.stage == SphereState.Stage.INVALID:
		audio.response(false)
		sphere_aim.clear_targets()
		_refresh_project()
		return
	var hit: int = sphere_aim.fire_ray()
	if sphere_state.stage == SphereState.Stage.GATE:
		if hit >= 0:
			sphere_state.begin_wait(now, rng)
			sphere_aim.clear_targets()
		audio.play("start") if hit >= 0 else audio.response(false)
		_refresh_project()
		return
	if hit >= 0:
		sphere_state.register_hit(now)
	audio.response(hit >= 0)
	if sphere_state.reactions_us.size() > samples_before:
		var new_sample_index: int = sphere_state.reactions_us.size() - 1
		_show_score_flight(new_sample_index, sphere_state.reactions_us[new_sample_index])
		sphere_aim.clear_targets()
		if sphere_state.stage == SphereState.Stage.NEXT:
			_begin_sphere_gate()
			return
	_refresh_project()


func _begin_sphere_gate() -> void:
	sphere_state.start_gate()
	sphere_aim.spawn_gate()
	_refresh_project()


func _handle_sens_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var step := Camera3DConfig.LOOK_SENS_FINE_STEP if event.alt_pressed or Input.is_key_pressed(KEY_ALT) else Camera3DConfig.LOOK_SENS_STEP
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_nudge_look_sensitivity(step)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_nudge_look_sensitivity(-step)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			_adjust_lab_layout(-SensLab.SPACING_STEP * 2.0, 0.0)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			_adjust_lab_layout(SensLab.SPACING_STEP * 2.0, 0.0)
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
			_adjust_lab_layout(0.0, -SensLab.DISTANCE_STEP if event.keycode == KEY_BRACKETLEFT else SensLab.DISTANCE_STEP)
			get_viewport().set_input_as_handled()
			return
	if sens_lab.cursor_mode:
		return
	var is_fire: bool = (
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
		or _keyboard_react(event)
	)
	if is_fire:
		audio.response(sens_lab.fire_ray() >= 0)
		_refresh_sens()


func _adjust_lab_layout(spacing_delta: float, distance_delta: float) -> void:
	var previous_spacing := sens_lab.spacing_side()
	var previous_distance := sens_lab.target_distance
	sens_lab.set_layout(sens_lab.spacing_side() + spacing_delta, sens_lab.target_distance + distance_delta)
	sens_save_failed = not scores.set_lab_layout(sens_lab.spacing_side(), sens_lab.target_distance)
	if sens_save_failed:
		sens_lab.set_layout(scores.lab_spacing, scores.lab_distance)
	elif not is_equal_approx(previous_spacing, sens_lab.spacing_side()) or not is_equal_approx(previous_distance, sens_lab.target_distance):
		audio.play("slide")
	_note_sens_adjust()
	_refresh_sens()


func _nudge_look_sensitivity(delta: float) -> void:
	_set_look_sensitivity(scores.look_sens + delta, true)
	_note_sens_adjust()


func _set_look_sensitivity(value: float, sync_slider: bool = true) -> void:
	var previous := scores.look_sens
	var saved := scores.set_look_sensitivity(value)
	sens_save_failed = not saved
	if saved and not is_equal_approx(previous, scores.look_sens):
		audio.play("slide")
	_apply_look_sensitivity()
	if sync_slider:
		_sync_sens_slider()
	else:
		sens_slider_label.text = "LOOK SENSITIVITY  %.2f" % scores.look_sens
	if page == "sens":
		_refresh_sens()
	if settings_value:
		settings_value.text = "LOOK SENSITIVITY  %.2f%s" % [scores.look_sens, "" if saved else "  (save failed)"]
		settings_slider.set_value_no_signal(scores.look_sens)


func _apply_look_sensitivity() -> void:
	corner_watch.set_look_sensitivity(scores.look_sens)
	sphere_aim.set_look_sensitivity(scores.look_sens)
	sens_lab.set_look_sensitivity(scores.look_sens)
	tracking.set_look_sensitivity(scores.look_sens)


func _sync_sens_slider() -> void:
	if sens_slider == null:
		return
	sens_slider.set_value_no_signal(scores.look_sens)
	sens_slider_label.text = "LOOK SENSITIVITY  %.2f" % scores.look_sens


func _set_sens_slider_interactive(enabled: bool) -> void:
	if sens_slider == null:
		return
	var filter := Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	sens_slider.mouse_filter = filter
	sens_slider.editable = enabled


func _on_sens_slider_changed(value: float) -> void:
	_set_look_sensitivity(snappedf(value, Camera3DConfig.LOOK_SENS_FINE_STEP), false)
	_note_sens_adjust()


func _apply_sens_slider_at(x: float) -> void:
	var left := sens_slider.global_position.x
	var width := maxf(1.0, sens_slider.size.x)
	var t := clampf((x - left) / width, 0.0, 1.0)
	var value := lerpf(Camera3DConfig.LOOK_SENS_MIN, Camera3DConfig.LOOK_SENS_MAX, t)
	value = snappedf(value, Camera3DConfig.LOOK_SENS_FINE_STEP)
	_set_look_sensitivity(value, true)
	_note_sens_adjust()


func _note_sens_adjust() -> void:
	sens_last_adjust_sec = Time.get_ticks_msec() * 0.001
	_set_sens_chrome_visible(true)


func _sens_chrome_wants_full() -> bool:
	if page != "sens":
		return false
	if sens_lab.cursor_mode or sens_slider_dragging:
		return true
	return (Time.get_ticks_msec() * 0.001) - sens_last_adjust_sec < SENS_CHROME_HOLD_SEC


func _update_sens_chrome() -> void:
	_set_sens_chrome_visible(_sens_chrome_wants_full())


func _set_sens_chrome_visible(full: bool) -> void:
	if sens_slider_panel_style == null:
		return
	if full == sens_chrome_full:
		return
	sens_chrome_full = full
	var target := SENS_PANEL_ALPHA_FULL if full else SENS_PANEL_ALPHA_DIM
	if sens_chrome_tween != null:
		sens_chrome_tween.kill()
	sens_chrome_tween = create_tween()
	sens_chrome_tween.tween_method(_set_sens_panel_alpha, sens_slider_panel_style.bg_color.a, target, 0.35)


func _set_sens_panel_alpha(alpha: float) -> void:
	if sens_slider_panel_style == null:
		return
	var color := sens_slider_panel_style.bg_color
	color.a = alpha
	sens_slider_panel_style.bg_color = color
	if sens_slider_panel:
		sens_slider_panel.add_theme_stylebox_override("panel", sens_slider_panel_style)


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
		"sens":
			_refresh_sens()
		"tracking":
			_refresh_tracking()


func _refresh_sens() -> void:
	hud_title.text = "3D LOOK SENSITIVITY"
	hud_hint.text = "SENS  %.2f    SPACING  %.2f    DISTANCE  %.2f%s" % [scores.look_sens, sens_lab.spacing_side(), sens_lab.target_distance, "  (save failed)" if sens_save_failed else ""]
	hud_dots.text = ""
	if sens_lab.cursor_mode:
		hud_footer.text = "SLIDER / WHEEL: SENS 0.01  |  -/=: SPACING  |  [/]: DISTANCE  |  RELEASE ALT: LOOK  |  ESC: MENU"
	else:
		hud_footer.text = "WHEEL: SENS 0.05  |  -/=: SPACING  |  [/]: DISTANCE  |  ALT: CURSOR  |  LMB / KEYS: FIRE  |  ESC: MENU"


func _refresh_color() -> void:
	var title := "2D REACTION"
	var hint := "Press SPACE, Z, X, an arrow key, or click to begin."
	var background := DARK
	match state.stage:
		ReactionState.Stage.WAITING:
			title = "WAIT"
			hint = "Do not press yet."
			background = Palette.ERROR
		ReactionState.Stage.TARGET:
			title = "NOW"
			hint = "PRESS OR CLICK"
			background = Palette.SUCCESS
		ReactionState.Stage.NEXT:
			title = "NEXT TRIAL"
			hint = "Press when ready."
		ReactionState.Stage.INVALID:
			title = "ROUND INVALID / 0.0 pts"
			hint = "False start or timeout. Press to retry."
	color_background.color = background
	var foreground := Palette.SURFACE if state.stage in [ReactionState.Stage.WAITING, ReactionState.Stage.TARGET] else INK
	color_title.add_theme_color_override("font_color", foreground)
	color_hint.add_theme_color_override("font_color", foreground)
	color_dots.add_theme_color_override("font_color", foreground)
	color_footer.add_theme_color_override("font_color", foreground)
	color_title.text = title
	color_hint.text = hint
	color_dots.text = _dots(state.reactions_us.size())


func _refresh_corner() -> void:
	var title := "3D REACTION"
	var hint := "Move the mouse. Click when the enemy appears."
	if state.stage == ReactionState.Stage.NEXT:
		title = "NEXT TRIAL"
		hint = "Click when ready."
	elif state.stage == ReactionState.Stage.INVALID:
		title = "ROUND INVALID / 0.0 pts"
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
	hud_footer.text = "MOUSE: LIMITED LOOK | LMB / REACT KEYS: FIRE | ESC: MENU"


func _refresh_osu() -> void:
	var title := "OSU"
	var hint := "Press SPACE, Z, X, an arrow key, or click to begin."
	match osu_state.stage:
		OsuState.Stage.GATE:
			title = "ARM"
			hint = "Hit the green gate to arm the round."
		OsuState.Stage.WAITING:
			title = "WAIT"
			hint = "Do not click yet."
		OsuState.Stage.ACTIVE:
			title = "HIT %d / %d" % [osu_state.expected, OsuState.TARGETS]
			hint = "Aim at the next circle, then click or press a react key."
		OsuState.Stage.NEXT:
			title = "NEXT TRIAL"
			hint = "Hit the green gate when ready."
		OsuState.Stage.INVALID:
			title = "ROUND INVALID / 0.0 pts"
			hint = "Early start, miss, or wrong circle. Press to retry."
	osu_title.text = title
	osu_hint.text = hint
	osu_dots.text = _dots(osu_state.reactions_us.size())
	_update_trial_list_opacity()


func _refresh_spheres() -> void:
	var title := "3D AIM"
	var hint := "Press SPACE, Z, X, an arrow key, or click to begin."
	match sphere_state.stage:
		SphereState.Stage.GATE:
			title = "ARM"
			hint = "Hit the green gate to arm the round."
		SphereState.Stage.WAITING:
			title = "WAIT"
			hint = "Do not fire yet."
		SphereState.Stage.AIMING:
			title = "CLEAR TARGETS"
			hint = "Aim and fire. %d left." % sphere_state.hits_remaining
		SphereState.Stage.NEXT:
			title = "NEXT TRIAL"
			hint = "Hit the green gate when ready."
		SphereState.Stage.INVALID:
			title = "ROUND INVALID / 0.0 pts"
			hint = "Early fire or timeout. Click to retry."
	hud_title.text = title
	hud_hint.text = hint
	hud_dots.text = _dots(sphere_state.reactions_us.size())
	hud_footer.text = "MOUSE: LIMITED LOOK | LMB / REACT KEYS: FIRE | ESC: MENU"


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
		"tracking":
			return "tracking"
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
		"tracking":
			return tracking_state.stage == TrackingState.Stage.SUMMARY
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
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_full_rect(menu, DARK)
	var title := _label("NEKO / BENCHMARK", 34, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.position = Vector2(40, 32)
	title.size = Vector2(560, 48)
	menu.add_child(title)
	var subtitle := _label("TESTS / FIND YOUR RHYTHM", 15, MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	subtitle.position = Vector2(40, 90)
	subtitle.size = Vector2(560, 26)
	menu.add_child(subtitle)
	for index in ScoreStore.PROJECTS.size():
		var mode: Dictionary = ScoreStore.PROJECTS[index]
		var button := _button(menu, mode.name, Vector2(40, 128 + index * 76), Vector2(560, 62), enter_project.bind(mode.page))
		button.add_theme_font_size_override("font_size", 20)
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(color_name, Palette.PROJECT_COLORS[mode.key])
		for state_name in ["normal", "hover", "pressed", "focus"]:
			var style: StyleBoxFlat = button.get_theme_stylebox(state_name).duplicate()
			style.border_color = Palette.PROJECT_COLORS[mode.key]
			button.add_theme_stylebox_override(state_name, style)
		menu_buttons.append(button)
	var separator := ColorRect.new()
	separator.position = Vector2(40, 530)
	separator.size = Vector2(560, 1)
	separator.color = Palette.BORDER
	menu.add_child(separator)
	var tools := _label("TOOLS", 13, MUTED)
	tools.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tools.position = Vector2(40, 548)
	tools.size = Vector2(560, 24)
	menu.add_child(tools)
	_button(menu, "History", Vector2(40, 584), Vector2(270, 46), show_history)
	_button(menu, "Settings", Vector2(330, 584), Vector2(270, 46), show_settings)
	var footer := _label("ESC: QUIT  /  ENGINE TIMING", 13, MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	footer.position = Vector2(40, 674)
	footer.size = Vector2(560, 26)
	menu.add_child(footer)
	storage_status = _label("", 13, Palette.ERROR)
	storage_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	storage_status.position = Vector2(40, 636)
	storage_status.size = Vector2(560, 36)
	storage_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(storage_status)
	_build_profile_card()


func _build_profile_card() -> void:
	var card := Panel.new()
	card.position = Vector2(640, 90)
	card.size = Vector2(600, 560)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(card)
	var heading := _label("UNSAVED / BEST WITHIN 1 HOUR", 16, MUTED)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.position = Vector2(664, 108)
	heading.size = Vector2(552, 28)
	menu.add_child(heading)
	for index in ScoreStore.PROJECTS.size():
		var mode: Dictionary = ScoreStore.PROJECTS[index]
		var title := _label(mode.name, 16, Palette.BASE)
		title.position = Vector2(664, 150 + index * 90)
		title.size = Vector2(228, 28)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Palette.PROJECT_COLORS[mode.key]
		title.add_theme_stylebox_override("normal", fill)
		var bold := FontVariation.new()
		bold.base_font = load("res://assets/MapleMono-Regular.ttf")
		bold.variation_embolden = 0.7
		title.add_theme_font_override("font", bold)
		menu.add_child(title)
		var row := _label("", 17, INK)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.position = Vector2(664, 182 + index * 90)
		row.size = Vector2(552, 28)
		menu.add_child(row)
		profile_rows.append(row)
	menu_tag = LineEdit.new()
	menu_tag.placeholder_text = "Tag (optional): device, setup, or form"
	menu_tag.max_length = 64
	menu_tag.position = Vector2(664, 574)
	menu_tag.size = Vector2(320, 36)
	menu.add_child(menu_tag)
	save_button = _button(menu, "Save Session", Vector2(1004, 574), Vector2(212, 36), _save_session)
	save_button.add_theme_color_override("font_color", ACCENT)
	save_status = _label("", 13, MUTED)
	save_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	save_status.position = Vector2(664, 612)
	save_status.size = Vector2(552, 34)
	save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(save_status)


func _build_color_page() -> void:
	color_reaction.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	color_footer = _label("ESC: MENU", 15, MUTED)
	color_footer.position = Vector2(0, 650)
	color_footer.size = Vector2(1280, 26)
	color_reaction.add_child(color_footer)


func _build_osu_page() -> void:
	osu_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var footer := _label("CURSOR ON NEXT CIRCLE + LMB OR REACT KEY | ESC: MENU", 14, MUTED)
	footer.position = Vector2(0, 650)
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
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	crosshair.offset_left = -20.0
	crosshair.offset_top = -20.0
	crosshair.offset_right = 20.0
	crosshair.offset_bottom = 20.0
	hud.add_child(crosshair)
	hud_footer = _label("MOUSE: LIMITED LOOK | LMB / REACT KEYS: FIRE | ESC: MENU", 14, INK)
	hud_footer.position = Vector2(0, 650)
	hud_footer.size = Vector2(1280, 24)
	hud.add_child(hud_footer)


func _build_sens_slider() -> void:
	sens_slider_layer = Control.new()
	sens_slider_layer.theme = Palette.create()
	sens_slider_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sens_slider_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sens_slider_layer.hide()
	$CanvasLayer.add_child(sens_slider_layer)
	sens_slider_panel = Panel.new()
	sens_slider_panel_style = StyleBoxFlat.new()
	sens_slider_panel_style.bg_color = Color(Palette.SURFACE, SENS_PANEL_ALPHA_DIM)
	sens_slider_panel_style.corner_radius_top_left = 12
	sens_slider_panel_style.corner_radius_top_right = 12
	sens_slider_panel_style.corner_radius_bottom_left = 12
	sens_slider_panel_style.corner_radius_bottom_right = 12
	sens_slider_panel.add_theme_stylebox_override("panel", sens_slider_panel_style)
	sens_slider_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sens_slider_panel.position = Vector2(290, 510)
	sens_slider_panel.size = Vector2(700, 96)
	sens_slider_layer.add_child(sens_slider_panel)
	sens_slider_label = _label("LOOK SENSITIVITY  1.00", 16, INK)
	sens_slider_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sens_slider_label.position = Vector2(310, 518)
	sens_slider_label.size = Vector2(660, 28)
	sens_slider_layer.add_child(sens_slider_label)
	sens_slider = HSlider.new()
	sens_slider.min_value = Camera3DConfig.LOOK_SENS_MIN
	sens_slider.max_value = Camera3DConfig.LOOK_SENS_MAX
	sens_slider.step = Camera3DConfig.LOOK_SENS_FINE_STEP
	sens_slider.value = scores.look_sens
	sens_slider.position = Vector2(330, 558)
	sens_slider.size = Vector2(620, 28)
	sens_slider.focus_mode = Control.FOCUS_NONE
	sens_slider.value_changed.connect(_on_sens_slider_changed)
	sens_slider_layer.add_child(sens_slider)
	sens_chrome_full = false
	_set_sens_slider_interactive(false)


func _build_summary() -> void:
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_full_rect(summary, DARK)
	summary_text = _label("", 22, INK)
	summary_text.position = Vector2(270, 90)
	summary_text.size = Vector2(600, 310)
	summary_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	summary_text.add_theme_constant_override("line_spacing", 10)
	summary.add_child(summary_text)
	summary_radar = Radar.new()
	summary_radar.position = Vector2(900, 110)
	summary_radar.size = Vector2(340, 330)
	summary.add_child(summary_radar)
	summary_time = _label("", 14, MUTED)
	summary_time.position = Vector2(270, 408)
	summary_time.size = Vector2(600, 30)
	summary_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	summary.add_child(summary_time)
	var hint := _label("Added to the 1-hour cache. Save all five tests from Menu.", 14, MUTED)
	hint.position = Vector2(340, 460)
	hint.size = Vector2(800, 40)
	summary.add_child(hint)
	_button(summary, "Retry", Vector2(560, 568), Vector2(220, 48), _restart_project)
	_button(summary, "Menu", Vector2(820, 568), Vector2(220, 48), show_menu)
	var footer := _label("R: RETRY    ESC: MENU", 14, MUTED)
	footer.position = Vector2(340, 656)
	footer.size = Vector2(800, 30)
	summary.add_child(footer)


func _update_trial_list_opacity() -> void:
	# Only dim while OSU targets are on screen (ACTIVE); wait / between rounds stay readable.
	if page == "osu" and osu_state.stage == OsuState.Stage.ACTIVE:
		trial_list.modulate = Color(1, 1, 1, 0.38)
	else:
		trial_list.modulate = Color.WHITE


func _build_trial_list() -> void:
	var background := Panel.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.SURFACE, 0.90)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	background.add_theme_stylebox_override("panel", style)
	background.position = Vector2(16, 220)
	background.size = Vector2(228, 248)
	trial_list.add_child(background)
	var title := _label("ROUND RESULTS", 13, MUTED)
	title.position = Vector2(20, 232)
	title.size = Vector2(220, 24)
	trial_list.add_child(title)
	live_timer = _label("", 14, ACCENT)
	live_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	live_timer.position = Vector2(28, 258)
	live_timer.size = Vector2(210, 24)
	live_timer.hide()
	trial_list.add_child(live_timer)
	for index in 5:
		var row := _label("ROUND %d  --" % (index + 1), 12, INK)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.position = Vector2(28, 290 + index * 32)
		row.size = Vector2(210, 24)
		trial_list.add_child(row)
		trial_rows.append(row)
	flight_score = _label("", 30, ACCENT)
	flight_score.size = Vector2(500, 48)
	flight_score_layer.add_child(flight_score)


func _spawn_osu_gate() -> void:
	_clear_osu_circles()
	osu_gate_center = _osu_play_area().get_center()
	var gate := _make_osu_circle(0, osu_gate_center)
	gate.ring_color = OSU_GATE_COLOR
	gate.modulate.a = 1.0
	osu_gate_node = gate
	osu_circles_root.add_child(gate)


func _osu_play_area() -> Rect2:
	return Rect2(80, 120, 1120, 540)


func _osu_gate_hit(point: Vector2) -> bool:
	return point.distance_to(osu_gate_center) <= OSU_RADIUS


func _spawn_osu_circles() -> void:
	_clear_osu_circles()
	var area := _osu_play_area()
	var inner := Rect2(
		area.position.x + OSU_RADIUS,
		area.position.y + OSU_RADIUS,
		area.size.x - OSU_RADIUS * 2.0,
		area.size.y - OSU_RADIUS * 2.0
	)
	osu_gate_center = area.get_center()
	var built := false
	for _attempt in 80:
		if _try_build_osu_chain(inner):
			built = true
			break
	if not built:
		_build_osu_chain_fallback(inner)
	for index in osu_centers.size():
		var circle := _make_osu_circle(index + 1, osu_centers[index])
		osu_circles_root.add_child(circle)
		osu_circle_nodes.append(circle)
	_refresh_osu_visibility(true)


func _try_build_osu_chain(inner: Rect2) -> bool:
	osu_centers.clear()
	var first_placed := false
	for _angle_try in 48:
		var angle := rng.randf() * TAU
		var first := osu_gate_center + Vector2.from_angle(angle) * OSU_SPACING
		if not inner.has_point(first):
			continue
		osu_centers.append(first)
		first_placed = true
		break
	if not first_placed:
		return false
	while osu_centers.size() < OsuState.TARGETS:
		var prev: Vector2 = osu_centers[osu_centers.size() - 1]
		var placed := false
		for _angle_try in 48:
			var angle := rng.randf() * TAU
			var next := prev + Vector2.from_angle(angle) * OSU_SPACING
			if not inner.has_point(next):
				continue
			# Only consecutive triples must not overlap (check new vs centers[-2]).
			if osu_centers.size() >= 2:
				var older: Vector2 = osu_centers[osu_centers.size() - 2]
				if next.distance_to(older) < OSU_RADIUS * 2.0:
					continue
			osu_centers.append(next)
			placed = true
			break
		if not placed:
			osu_centers.clear()
			return false
	return true


func _build_osu_chain_fallback(inner: Rect2) -> void:
	# ponytail: serpentine path with fixed edge length; O(1) layout if RNG chain fails.
	osu_centers.clear()
	var start := osu_gate_center + Vector2(OSU_SPACING, 0.0)
	if not inner.has_point(start):
		start = osu_gate_center + Vector2(-OSU_SPACING, 0.0)
	if not inner.has_point(start):
		start = osu_gate_center + Vector2(0.0, OSU_SPACING)
	osu_centers.append(start)
	var heading := 0.0
	var guard := 0
	while osu_centers.size() < OsuState.TARGETS and guard < 64:
		guard += 1
		var prev: Vector2 = osu_centers[osu_centers.size() - 1]
		var placed := false
		for turn in 24:
			var angle := heading + (float(turn) - 11.5) * 0.2
			var next := prev + Vector2.from_angle(angle) * OSU_SPACING
			if not inner.has_point(next):
				continue
			if osu_centers.size() >= 2 and next.distance_to(osu_centers[osu_centers.size() - 2]) < OSU_RADIUS * 2.0:
				continue
			osu_centers.append(next)
			heading = angle
			placed = true
			break
		if not placed:
			heading += 0.7
	# If still short, place remaining along a clipped horizontal zig-zag inside bounds.
	while osu_centers.size() < OsuState.TARGETS:
		var prev2: Vector2 = osu_centers[osu_centers.size() - 1]
		var next2 := Vector2(prev2.x + OSU_SPACING, prev2.y)
		if not inner.has_point(next2):
			next2 = Vector2(prev2.x, clampf(prev2.y + OSU_SPACING, inner.position.y, inner.end.y))
		if not inner.has_point(next2):
			next2 = inner.get_center()
		osu_centers.append(next2)


func _make_osu_circle(number: int, center: Vector2) -> Control:
	var root := OsuCircleDraw.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = center - Vector2(OSU_RADIUS, OSU_RADIUS)
	root.size = Vector2(OSU_RADIUS * 2.0, OSU_RADIUS * 2.0)
	root.ring_color = Palette.PROJECT_COLORS.osu
	root.fill_color = DARK
	root.modulate.a = 0.0
	if number > 0:
		var label := _label(str(number), 28, INK)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(label)
	return root


func _osu_circle_at(point: Vector2) -> int:
	for index in osu_centers.size():
		if not _osu_circle_is_active(index):
			continue
		if point.distance_to(osu_centers[index]) <= OSU_RADIUS:
			return index
	return -1


func _osu_circle_is_active(index: int) -> bool:
	var number := index + 1
	return number >= osu_state.expected and number <= osu_state.expected + 2


func _refresh_osu_visibility(initial: bool = false) -> void:
	for index in osu_circle_nodes.size():
		var node := osu_circle_nodes[index]
		if node == null or not is_instance_valid(node):
			continue
		if node.get_meta("fading", false):
			continue
		var should_show := osu_state.stage == OsuState.Stage.ACTIVE and _osu_circle_is_active(index)
		node.visible = should_show
		if node.has_meta("reveal_tween"):
			node.get_meta("reveal_tween").kill()
		if not should_show:
			continue
		var offset: int = index + 1 - osu_state.expected
		var opacity: float = [1.0, 0.6, 0.3][offset]
		if initial and offset == 0:
			node.modulate.a = opacity
		else:
			var tween := node.create_tween()
			node.set_meta("reveal_tween", tween)
			if initial:
				tween.tween_interval(offset * 0.2)
			tween.tween_property(node, "modulate:a", opacity, 0.2)


func _mark_osu_hit(index: int) -> void:
	if index < 0 or index >= osu_circle_nodes.size():
		return
	var node := osu_circle_nodes[index]
	if node == null or not is_instance_valid(node):
		return
	node.set_meta("fading", true)
	if node is OsuCircleDraw:
		var circle: OsuCircleDraw = node
		circle.ring_color = MUTED
		circle.queue_redraw()
	if node.has_meta("reveal_tween"):
		node.get_meta("reveal_tween").kill()
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 0.0, OSU_FADE_SEC)
	tween.tween_callback(node.hide)


func _show_osu_guide_line() -> void:
	# After a hit, expected is the next target; meteor streak from next → next+1 edges.
	var from_idx := osu_state.expected - 1
	var to_idx := osu_state.expected
	if from_idx < 0 or to_idx >= osu_centers.size():
		return
	var guide := OsuGuideLine.new()
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	guide.from_point = osu_centers[from_idx]
	guide.to_point = osu_centers[to_idx]
	guide.radius = OSU_RADIUS
	guide.line_color = Color.WHITE
	osu_circles_root.add_child(guide)


func _clear_osu_circles() -> void:
	for node in osu_circles_root.get_children():
		node.queue_free()
	osu_circle_nodes.clear()
	osu_centers.clear()
	osu_gate_node = null


func _update_live_trial_time(now_us: int) -> void:
	if live_timer == null or summary.visible:
		return
	var start_us := 0
	match page:
		"color", "corner":
			if state.stage == ReactionState.Stage.TARGET:
				start_us = state.target_frame_us
		"spheres":
			if sphere_state.stage == SphereState.Stage.AIMING:
				start_us = sphere_state.target_frame_us
		"osu":
			if osu_state.stage == OsuState.Stage.ACTIVE and osu_state.start_us > 0:
				start_us = osu_state.start_us
	if start_us <= 0:
		live_timer.hide()
		return
	var elapsed_ms := float(maxi(0, now_us - start_us)) / 1000.0
	live_timer.text = "LIVE  %.1f ms" % elapsed_ms
	live_timer.show()


func _reset_trial_list() -> void:
	if score_flight:
		score_flight.kill()
	score_flight_active = false
	flight_score_layer.hide()
	if live_timer:
		live_timer.hide()
	for index in trial_rows.size():
		trial_rows[index].text = "ROUND %d  --" % (index + 1)


func _show_score_flight(index: int, reaction_us: int) -> void:
	if live_timer:
		live_timer.hide()
	if _active_samples().size() == 5:
		_freeze_result()
	_show_score_text_flight(index, ScoreStore.display(_score_key(), float(reaction_us) / 1000.0))


func _show_score_text_flight(index: int, score_text: String) -> void:
	var color: Color = Palette.PROJECT_COLORS[_score_key()]
	flight_score.add_theme_color_override("font_color", color)
	trial_rows[index].add_theme_color_override("font_color", color)
	if score_flight:
		score_flight.kill()
	score_flight_active = true
	flight_score_layer.show()
	flight_score.text = score_text
	flight_score.position = Vector2(440, 328)
	score_flight = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	score_flight.tween_property(flight_score, "position", Vector2(28, 290 + index * 32), 0.5)
	score_flight.tween_callback(_finish_score_flight.bind(index, score_text))


func _finish_score_flight(index: int, score_text: String) -> void:
	trial_rows[index].text = "%d  %s" % [index + 1, score_text]
	flight_score_layer.hide()
	score_flight_active = false


func _update_best_scores(now_us: int = -1) -> void:
	if now_us < 0:
		now_us = Time.get_ticks_usec()
	last_menu_refresh_us = now_us
	result_cache.prune(now_us)
	storage_status.text = " / ".join([scores.error, history.error]).trim_prefix(" / ").trim_suffix(" / ")
	var completed := 0
	for index in ScoreStore.PROJECTS.size():
		var mode: Dictionary = ScoreStore.PROJECTS[index]
		var entry: Dictionary = result_cache.best(mode.key)
		if entry.is_empty():
			profile_rows[index].text = "--  /  NO VALID UNSAVED RESULT"
			continue
		completed += 1
		var remaining := ceili(float(ResultCache.VALID_US - (now_us - int(entry.completed_us))) / 1_000_000.0)
		profile_rows[index].text = "%s / %02d:%02d LEFT" % [ScoreStore.display(mode.key, entry.record.stats.median), remaining / 60, remaining % 60]
	save_button.disabled = completed != ScoreStore.PROJECTS.size() or not history.writable
	menu_tag.editable = history.writable
	save_status.text = menu_notice if not menu_notice.is_empty() else "%d / 5 ready. Complete all five within one hour to save." % completed


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", load("res://assets/MapleMono-Regular.ttf"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(parent: Control, text: String, pos: Vector2, extent: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = extent
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _build_settings() -> void:
	settings_page = Control.new()
	settings_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_page.theme = Palette.create()
	add_child(settings_page)
	_add_full_rect(settings_page, DARK)
	var title := _label("SETTINGS", 34, INK)
	title.position = Vector2(40, 32)
	title.size = Vector2(1200, 48)
	settings_page.add_child(title)
	settings_value = _label("", 22, INK)
	settings_value.position = Vector2(240, 220)
	settings_value.size = Vector2(800, 44)
	settings_page.add_child(settings_value)
	settings_slider = HSlider.new()
	settings_slider.min_value = Camera3DConfig.LOOK_SENS_MIN
	settings_slider.max_value = Camera3DConfig.LOOK_SENS_MAX
	settings_slider.step = Camera3DConfig.LOOK_SENS_FINE_STEP
	settings_slider.position = Vector2(330, 300)
	settings_slider.size = Vector2(620, 36)
	settings_slider.value_changed.connect(func(value: float) -> void: _set_look_sensitivity(value))
	settings_page.add_child(settings_slider)
	var hint := _label("Shared by all 3D tests. Practice and adjust in Sens Lab.", 16, MUTED)
	hint.position = Vector2(160, 360)
	hint.size = Vector2(960, 40)
	settings_page.add_child(hint)
	_button(settings_page, "Open Sens Lab", Vector2(440, 440), Vector2(400, 54), enter_sens_lab)
	_button(settings_page, "Menu", Vector2(520, 580), Vector2(240, 48), show_menu)


func show_settings() -> void:
	show_menu()
	page = "settings"
	menu.hide()
	settings_page.show()
	settings_slider.set_value_no_signal(scores.look_sens)
	settings_value.text = "LOOK SENSITIVITY  %.2f" % scores.look_sens


func show_history() -> void:
	show_menu()
	page = "history"
	menu.hide()
	history_page.show()
	history_page.refresh(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and page == "tracking" and tracking_state.stage == TrackingState.Stage.INVALID:
		tracking_state.prepare(Time.get_ticks_usec())
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and page == "tracking" and tracking_state.stage in [TrackingState.Stage.PREPARING, TrackingState.Stage.ACTIVE]:
		tracking_state.reset()
		tracking_state.stage = TrackingState.Stage.INVALID
		_reset_trial_list()
		_refresh_tracking()


func _refresh_tracking() -> void:
	hud_title.text = "3D TRACKING"
	hud_dots.text = _dots(tracking_state.coverage.size())
	hud_footer.text = "MOUSE: TRACK WITH CROSSHAIR | NO FIRE REQUIRED | ESC: MENU"
	live_timer.hide()
	match tracking_state.stage:
		TrackingState.Stage.READY:
			hud_hint.text = "Follow the target continuously for 1 second to begin."
		TrackingState.Stage.INVALID:
			hud_hint.text = "Focus lost. Set cancelled. Return to resume tracking."
		TrackingState.Stage.PREPARING:
			hud_hint.text = "FOLLOW  %.1f / 1.0 s continuously inside the outer circle" % (tracking_state.acquired_us / 1_000_000.0)
		TrackingState.Stage.ACTIVE:
			var elapsed: int = maxi(1, tracking_state.last_us - tracking_state.start_us)
			var coverage: float = 100.0 * tracking_state.covered_us / elapsed
			hud_hint.text = "TRACK  %.1f s remaining / %.1f %% coverage / inner 100, outer 50" % [maxf(0.0, 10.0 - elapsed / 1_000_000.0), coverage]
			live_timer.text = "LIVE %.1f s / %.1f pts" % [maxf(0.0, 10.0 - elapsed / 1_000_000.0), ScoreStore.points("tracking", coverage)]
			live_timer.show()


func _add_full_rect(parent: Control, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(rect)
	return rect


class OsuCircleDraw extends Control:
	var ring_color := Color.WHITE
	var fill_color := Color.BLACK

	func _draw() -> void:
		var center := size * 0.5
		var radius := size.x * 0.5
		draw_circle(center, radius, ring_color)
		draw_circle(center, maxf(0.0, radius - 6.0), fill_color)


class OsuGuideLine extends Control:
	var from_point := Vector2.ZERO
	var to_point := Vector2.ZERO
	var radius := 48.0
	var line_color := Color.WHITE
	# Phase 0: reveal start→end; phase 1: whole streak fades out.
	var phase := 0
	var anim_t := 0.0
	const REVEAL_SEC := 0.05
	const FADE_SEC := 0.08
	const SEGMENTS := 24

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		var duration := REVEAL_SEC if phase == 0 else FADE_SEC
		anim_t = minf(1.0, anim_t + delta / duration)
		if phase == 1:
			modulate.a = 1.0 - anim_t
		queue_redraw()
		if anim_t >= 1.0:
			if phase == 0:
				phase = 1
				anim_t = 0.0
			else:
				queue_free()

	func _draw() -> void:
		var direction := to_point - from_point
		var length := direction.length()
		if length <= radius * 2.0 + 1.0:
			return
		var tip := direction / length
		var start := from_point + tip * radius
		var end := to_point - tip * radius
		var path := end - start
		if path.length_squared() < 1.0:
			return
		# Reveal draws [0, anim_t]; fade phase keeps the full streak and dims via modulate.
		var visible_to := 1.0 if phase == 1 else anim_t
		if visible_to <= 0.0:
			return
		_draw_streak(start, path, 0.0, visible_to, 10.0, 18.0, Color(1, 1, 1, 0.12), 0.15)
		_draw_streak(start, path, 0.0, visible_to, 5.0, 10.0, Color(1, 1, 1, 0.28), 0.35)
		_draw_streak(start, path, 0.0, visible_to, 2.5, 5.5, Color(1, 1, 1, 0.75), 0.75)
		_draw_streak(start, path, 0.0, visible_to, 1.2, 3.0, Color(1, 1, 1, 1.0), 1.0)

	func _draw_streak(
		start: Vector2,
		path: Vector2,
		visible_from: float,
		visible_to: float,
		width_start: float,
		width_end: float,
		color: Color,
		alpha_scale: float
	) -> void:
		for i in SEGMENTS:
			var t0 := float(i) / float(SEGMENTS)
			var t1 := float(i + 1) / float(SEGMENTS)
			if t1 <= visible_from or t0 >= visible_to:
				continue
			var a := maxf(t0, visible_from)
			var b := minf(t1, visible_to)
			if b <= a:
				continue
			var p0 := start + path * a
			var p1 := start + path * b
			var along := (a + b) * 0.5
			var col := color
			col.a *= lerpf(0.55, 1.0, along) * alpha_scale
			var width := lerpf(width_start, width_end, along)
			draw_line(p0, p1, col, width, true)
