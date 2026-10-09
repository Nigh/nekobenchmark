extends SceneTree

const OsuState = preload("res://scripts/osu_state.gd")
const SphereState = preload("res://scripts/sphere_state.gd")
const Camera3DConfig = preload("res://scripts/camera_3d_config.gd")
const Scores = preload("res://scripts/score_store.gd")
const Lab = preload("res://scripts/sens_lab.gd")
const History = preload("res://scripts/history_store.gd")
const Cache = preload("res://scripts/result_cache.gd")
const Room = preload("res://scripts/practice_room.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var app: Node = packed.instantiate()
	var test_prefix := "user://playthrough-%d" % Time.get_ticks_usec()
	app.get("scores").score_path = test_prefix + "-scores.txt"
	app.get("history").path = test_prefix + "-history.json"
	get_root().add_child(app)
	await process_frame
	await process_frame

	assert(app.get("profile_total").text == "-- / 500", "incomplete results cannot fabricate a total")
	assert(float(app.get("OSU_SPACING")) == 360.0, "osu spacing should be 360")

	app.call("enter_project", "osu")
	await process_frame
	_press_key(KEY_SPACE)
	await process_frame
	var osu_state = app.get("osu_state")
	assert(int(osu_state.get("stage")) == OsuState.Stage.GATE, "osu should arm from green gate")
	assert(app.get("osu_gate_node") != null, "osu should show green gate")
	var gate_center: Vector2 = app.get("osu_gate_center")
	osu_state.call("begin_wait", Time.get_ticks_usec(), app.get("rng"))
	app.call("_clear_osu_circles")
	await process_frame
	assert(int(osu_state.get("stage")) == OsuState.Stage.WAITING, "gate hit should start wait")
	osu_state.set("deadline_us", Time.get_ticks_usec())
	await process_frame
	await process_frame
	assert(int(osu_state.get("stage")) == OsuState.Stage.ACTIVE, "wait should spawn circles")
	var centers: Array = app.get("osu_centers")
	assert(centers.size() == 6, "expected 6 osu circles, got %d" % centers.size())
	var spacing: float = float(app.get("OSU_SPACING"))
	var radius: float = float(app.get("OSU_RADIUS"))
	assert(is_equal_approx(centers[0].distance_to(gate_center), spacing), "first circle should be one spacing from gate")
	for i in centers.size() - 1:
		assert(is_equal_approx(centers[i].distance_to(centers[i + 1]), spacing), "adjacent spacing must match")
	for i in centers.size() - 2:
		assert(centers[i].distance_to(centers[i + 2]) >= radius * 2.0 - 0.01, "consecutive triple overlap")
	var osu_nodes: Array = app.get("osu_circle_nodes")
	var visible_count := 0
	for node in osu_nodes:
		if node.visible:
			visible_count += 1
	assert(visible_count == 3, "osu should show the next three circles")
	assert(is_equal_approx(osu_nodes[0].modulate.a, 1.0))
	assert(osu_nodes[1].modulate.a == 0.0 and osu_nodes[2].modulate.a == 0.0)
	for index in [1, 2]:
		var reveal: Tween = osu_nodes[index].get_meta("reveal_tween")
		reveal.pause()
		reveal.custom_step(0.3)
	assert(osu_nodes[1].modulate.a > 0.0 and osu_nodes[1].modulate.a < 0.6)
	assert(osu_nodes[2].modulate.a == 0.0, "third target waits a further 200ms")
	for index in [1, 2]:
		osu_nodes[index].get_meta("reveal_tween").custom_step(0.31)
	assert(is_equal_approx(osu_nodes[1].modulate.a, 0.6))
	assert(is_equal_approx(osu_nodes[2].modulate.a, 0.3))
	osu_state.hit_next(Time.get_ticks_usec())
	app.call("_mark_osu_hit", 0)
	app.call("_refresh_osu_visibility")
	assert(osu_nodes[3].visible and osu_nodes[3].modulate.a == 0.0)
	for index in [1, 2, 3]:
		var reveal: Tween = osu_nodes[index].get_meta("reveal_tween")
		reveal.pause()
		reveal.custom_step(0.2)
	assert(is_equal_approx(osu_nodes[1].modulate.a, 1.0))
	assert(is_equal_approx(osu_nodes[2].modulate.a, 0.6))
	assert(is_equal_approx(osu_nodes[3].modulate.a, 0.3))
	# Exercise actual GUI routing: a partly faded current target under the result panel.
	var click_point := Vector2(100, 330)
	centers[1] = click_point
	osu_nodes[1].position = click_point - Vector2.ONE * radius
	osu_nodes[1].modulate.a = 0.4
	assert(app.call("_osu_circle_at", click_point) == 1, "alpha does not gate hit testing")
	await process_frame
	var move := InputEventMouseMotion.new()
	move.position = app.get("osu_page").get_global_transform_with_canvas() * click_point
	move.global_position = move.position
	get_root().push_input(move, true)
	var click := InputEventMouseButton.new()
	click.position = move.position
	click.global_position = click.position
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	get_root().push_input(click, true)
	assert(osu_state.expected == 3, "result panel must not swallow clicks on a fading target")
	click.pressed = false
	get_root().push_input(click, true)
	# No intervening frame: motion to center, react press, then immediate motion away.
	var next_center: Vector2 = centers[2]
	move.position = app.get("osu_page").get_global_transform_with_canvas() * next_center
	move.global_position = move.position
	get_root().push_input(move, true)
	var fast_key := InputEventKey.new()
	fast_key.keycode = KEY_SPACE
	fast_key.pressed = true
	get_root().push_input(fast_key, true)
	move.position = app.get("osu_page").get_global_transform_with_canvas() * Vector2(1200, 680)
	move.global_position = move.position
	get_root().push_input(move, true)
	assert(osu_state.stage == OsuState.Stage.ACTIVE and osu_state.expected == 4, "later mouse motion cannot turn a react-key hit into a miss")
	fast_key.echo = true
	get_root().push_input(fast_key, true)
	assert(osu_state.expected == 4, "held react keys do not fire repeatedly")
	fast_key.echo = false
	fast_key.pressed = false
	get_root().push_input(fast_key, true)
	var fourth_center: Vector2 = centers[3]
	fast_key.pressed = true
	get_root().push_input(fast_key, true)
	move.position = app.get("osu_page").get_global_transform_with_canvas() * fourth_center
	get_root().push_input(move, true)
	assert(osu_state.stage == OsuState.Stage.INVALID, "moving onto a target after the key press cannot turn a miss into a hit")
	fast_key.pressed = false
	get_root().push_input(fast_key, true)
	# Leaving during a hit fade must destroy its node-bound tween and callback.
	app.call("show_menu")
	await create_timer(0.3).timeout
	app.call("enter_project", "osu")
	osu_state.stage = OsuState.Stage.ACTIVE
	for i in 6:
		osu_state.call("hit_next", Time.get_ticks_usec() + i * 10_000)
	assert(int(osu_state.get("stage")) == OsuState.Stage.NEXT, "osu round should finish")

	app.call("enter_project", "spheres")
	await process_frame
	_press_key(KEY_SPACE)
	await process_frame
	var sphere_state = app.get("sphere_state")
	assert(int(sphere_state.get("stage")) == SphereState.Stage.GATE)
	var sphere_aim = app.get("sphere_aim")
	assert(bool(sphere_aim.get("gate_active")), "spheres should show green gate")
	assert(sphere_aim.get("target_bodies").size() == 1)
	assert(is_equal_approx(float(sphere_aim.get("SPHERE_RADIUS")), 0.42))
	var gate: Node3D = sphere_aim.get("target_bodies")[0]
	assert(is_equal_approx(gate.position.x, 0.0) and is_equal_approx(gate.position.z, float(sphere_aim.get("GATE_Z"))), "gate fixed at room center")
	sphere_aim.set("yaw", 0.0)
	sphere_aim.set("pitch", 0.0)
	sphere_aim.call("_apply_camera_rotation")
	await process_frame
	_press_key(KEY_SPACE)
	await process_frame
	assert(int(sphere_state.get("stage")) == SphereState.Stage.WAITING, "gate hit should start wait")
	assert(app.get("audio").last_kind == "start")
	sphere_state.set("deadline_us", Time.get_ticks_usec())
	await process_frame
	await process_frame
	assert(int(sphere_state.get("stage")) == SphereState.Stage.AIMING, "wait should spawn targets")
	var bodies: Array = sphere_aim.get("target_bodies")
	assert(bodies.size() == 6, "expected 6 spheres")
	var sorted_layouts: Array = sphere_aim.layout_order.duplicate()
	sorted_layouts.sort()
	assert(sorted_layouts == [0, 1, 2, 3, 4])
	for round_index in 5:
		if round_index > 0:
			sphere_aim.spawn_targets()
		var layout: Array = sphere_aim.LAYOUTS[sphere_aim.layout_order[round_index]]
		for index in 6:
			assert(sphere_aim.target_bodies[index].position == layout[index])
	assert(sphere_aim.layout_cursor == 5)
	bodies = sphere_aim.target_bodies

	var PracticeRoom = load("res://scripts/practice_room.gd")
	var cam: Camera3D = sphere_aim.get("camera")
	var forward: Vector3 = -cam.global_transform.basis.z
	var max_ang := 0.0
	var quads := [false, false, false, false] # TL TR BL BR
	for body in bodies:
		assert(PracticeRoom.contains_point(body.global_position, 0.2), "sphere must stay in room")
		var ang: float = forward.angle_to(body.global_position - cam.global_position)
		max_ang = maxf(max_ang, ang)
		var local: Vector3 = cam.to_local(body.global_position)
		var qi := (0 if local.x < 0.0 else 1) + (0 if local.y >= 0.0 else 2)
		quads[qi] = true
	assert(quads[0] and quads[1] and quads[2] and quads[3], "each view quadrant needs a target")
	assert(max_ang <= deg_to_rad(31.0), "sphere spread should stay near 60° FOV")
	assert(cam.fov == Camera3DConfig.HORIZONTAL_FOV, "sphere fov")
	assert(cam.keep_aspect == Camera3D.KEEP_WIDTH, "sphere keep_aspect")

	app.call("enter_sens_lab")
	await process_frame
	await process_frame
	var sens_lab = app.get("sens_lab")
	assert(is_equal_approx(float(sens_lab.get("SPHERE_RADIUS")), 0.42))
	assert(is_equal_approx(float(app.get("SENS_PANEL_ALPHA_DIM")), 0.16))
	assert(not bool(app.get("sens_chrome_full")), "sens panel starts dim")
	var sens_bodies: Array = sens_lab.get("target_bodies")
	assert(sens_bodies.size() == 4, "expected 4 sens-lab spheres")
	assert(app.get("sens_slider_layer").visible, "sens slider should stay visible")
	var before: float = float(sens_lab.call("spacing_side"))
	app.call("_adjust_lab_layout", 0.32, 0.0)
	assert(float(sens_lab.call("spacing_side")) >= before - 0.001)
	var scores = app.get("scores")
	var sens_before: float = float(scores.get("look_sens"))
	app.call("_nudge_look_sensitivity", 0.05)
	assert(is_equal_approx(float(scores.get("look_sens")), Camera3DConfig.clamp_look_sensitivity(sens_before + 0.05)))
	assert(bool(app.get("sens_chrome_full")), "sens adjust should reveal panel")
	app.call("_apply_sens_slider_at", 330.0 + 310.0)
	var dragged: float = float(scores.get("look_sens"))
	assert(is_equal_approx(dragged, snappedf(dragged, Camera3DConfig.LOOK_SENS_FINE_STEP)))
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.alt_pressed = true
	var wheel_before: float = scores.look_sens
	app.call("_handle_sens_input", wheel)
	assert(is_equal_approx(scores.look_sens, wheel_before + 0.01))
	wheel.alt_pressed = false
	app.call("_handle_sens_input", wheel)
	assert(is_equal_approx(scores.look_sens, wheel_before + 0.06))
	var held := InputEventKey.new()
	held.pressed = true
	held.echo = true
	held.keycode = KEY_EQUAL
	var held_before: float = sens_lab.spacing_side()
	app.call("_handle_sens_input", held)
	app.call("_handle_sens_input", held)
	assert(is_equal_approx(sens_lab.spacing_side(), held_before + Lab.SPACING_STEP * 4.0))
	held.keycode = KEY_BRACKETRIGHT
	app.call("_handle_sens_input", held)
	app.call("_handle_sens_input", held)
	assert(sens_lab.target_distance == 8.5)
	for body in sens_lab.target_bodies:
		assert(body.position.z == -8.5)
	for distance in [3.0, 8.0, 20.0]:
		sens_lab.set_layout(100.0, distance)
		var lab_camera: Camera3D = sens_lab.camera
		for body in sens_lab.target_bodies:
			assert(Room.contains_point(body.position, Lab.SPHERE_RADIUS - 0.0001))
			var offset: Vector3 = body.position - lab_camera.position
			assert(Vector2(offset.x, offset.y).length() + Lab.SPHERE_RADIUS <= distance + 0.0001)
		assert(sens_lab.spacing_side() >= Lab.SPHERE_RADIUS * 2.0)
	sens_lab.set_layout(scores.lab_spacing, scores.lab_distance)
	var reloaded := Scores.new()
	reloaded.score_path = scores.score_path
	reloaded.load_scores()
	assert(is_equal_approx(reloaded.look_sens, scores.look_sens))
	assert(is_equal_approx(reloaded.lab_spacing, sens_lab.spacing_side()))
	assert(reloaded.lab_distance == sens_lab.target_distance)
	app.call("show_menu")
	app.call("enter_sens_lab")
	assert(is_equal_approx(sens_lab.spacing_side(), reloaded.lab_spacing))
	assert(sens_lab.target_distance == reloaded.lab_distance)
	var real_test_path: String = scores.score_path
	scores.score_path = test_prefix + "/missing/scores.txt"
	app.call("_adjust_lab_layout", 0.16, 0.25)
	assert(app.get("sens_save_failed"))
	assert(is_equal_approx(sens_lab.spacing_side(), reloaded.lab_spacing))
	assert(sens_lab.target_distance == reloaded.lab_distance)
	scores.score_path = real_test_path

	for i in 4:
		sens_lab.call("_defeat", i)
	assert(int(sens_lab.call("alive_count")) == 0)
	sens_lab.call("spawn_gate")
	assert(bool(sens_lab.get("gate_active")))
	assert(sens_lab.get("target_bodies").size() == 1)
	app.call("_adjust_lab_layout", 0.0, 0.25)
	assert(sens_lab.target_bodies[0].position.z == -sens_lab.target_distance)
	sens_lab.call("_defeat", 0)
	sens_lab.call("spawn_targets")
	assert(sens_lab.get("target_bodies").size() == 4, "sens-lab should respawn 4 after gate")
	assert(not bool(sens_lab.get("gate_active")))
	var audio = app.get("audio")
	assert(audio.streams.success.data.size() == int(44100 * 0.022) * 2)
	assert(audio.streams.error.data.size() == int(44100 * 0.035) * 2)
	assert(audio.streams.start.data.size() == int(44100 * 0.045) * 4)
	var count_before: int = audio.play_count
	audio.last_slide_us = -100_000
	audio.play("slide")
	audio.play("slide")
	assert(audio.play_count == count_before + 1)
	app.call("_set_look_sensitivity", scores.look_sens)
	assert(audio.play_count == count_before + 1, "unchanged slider values stay silent")
	held.keycode = KEY_SPACE
	app.call("_handle_sens_input", held)
	assert(audio.play_count == count_before + 1, "react key echoes stay silent")
	app.call("enter_project", "color")
	var react := InputEventKey.new()
	react.keycode = KEY_SPACE
	react.pressed = true
	app.call("_handle_reaction_input", react)
	assert(audio.last_kind == "start")
	app.call("_handle_reaction_input", react)
	assert(audio.last_kind == "error", "false start plays an error")
	assert(app.get("state").stage == app.get("ReactionState").Stage.INVALID)
	app.get("state").stage = app.get("ReactionState").Stage.TARGET
	app.get("state").target_frame_us = Time.get_ticks_usec() - 100_000
	app.call("_handle_reaction_input", react)
	assert(audio.last_kind == "start" and app.get("state").reactions_us.size() == 1)
	app.call("enter_project", "spheres")
	app.call("_handle_sphere_input", react)
	assert(audio.last_kind == "success")
	app.get("sphere_aim").camera.rotation = Vector3(0, PI * 0.5, 0)
	app.call("_handle_sphere_input", react)
	assert(audio.last_kind == "error" and app.get("sphere_state").stage == app.get("SphereState").Stage.GATE)
	count_before = audio.play_count
	app.call("_handle_sphere_input", react)
	assert(audio.play_count == count_before, "cooldown inputs stay silent")
	app.get("sphere_state").stage = app.get("SphereState").Stage.WAITING
	app.call("_handle_sphere_input", react)
	assert(audio.last_kind == "error")
	app.call("enter_project", "osu")
	app.call("_handle_osu_input", react)
	assert(audio.last_kind == "success")
	app.get("osu_state").stage = app.get("OsuState").Stage.WAITING
	app.call("_handle_osu_input", react)
	assert(audio.last_kind == "error")

	app.call("show_menu")
	await process_frame
	assert(app.get("profile_rows").size() == 5, "overview should list five bests")
	assert(app.get("menu_buttons").size() == 5)
	for index in 5:
		var expected_color: Color = app.get("Palette").PROJECT_COLORS[Scores.PROJECTS[index].key]
		assert(app.get("menu_buttons")[index].get_theme_stylebox("normal").border_color == expected_color)
	audio.last_hover_us = -100_000
	app.get("menu_buttons")[0].mouse_entered.emit()
	assert(audio.last_kind == "hover")
	app.get("menu_buttons")[0].button_down.emit()
	assert(audio.last_kind == "press")
	app.call("show_settings")
	assert(app.get("settings_page").visible)
	assert(not app.get("menu").visible)
	app.call("show_history")
	assert(app.get("history_page").visible)
	assert(not app.get("settings_page").visible)

	app.call("enter_project", "tracking")
	assert(app.get("tracking").active)
	var tracking_state = app.get("tracking_state")
	const TrackingState = preload("res://scripts/tracking_state.gd")
	assert(tracking_state.stage == TrackingState.Stage.PREPARING, "Tracking starts without a key")
	var target_material: ShaderMaterial = app.get("tracking").target.mesh.material
	assert(not target_material.get_shader_parameter("scoring"))
	tracking_state.last_us = Time.get_ticks_usec() - 500_000
	tracking_state.was_covered = true
	app.get("tracking").move_target(tracking_state.path_index(), tracking_state.movement_seconds(Time.get_ticks_usec()))
	app.get("tracking").camera.look_at(app.get("tracking").target.global_position)
	audio.last_slide_us = -100_000
	app.call("_process", 0.0)
	assert(tracking_state.stage == TrackingState.Stage.PREPARING and audio.last_kind == "slide")
	tracking_state.motion_start_us = Time.get_ticks_usec() - 1_000_000
	tracking_state.last_us = Time.get_ticks_usec() - 1_000_000
	tracking_state.was_covered = true
	app.get("tracking").move_target(tracking_state.path_index(), tracking_state.movement_seconds(Time.get_ticks_usec()))
	app.get("tracking").camera.look_at(app.get("tracking").target.global_position)
	var play_count: int = app.get("audio").play_count
	app.call("_process", 0.0)
	assert(tracking_state.stage == TrackingState.Stage.ACTIVE)
	assert(target_material.get_shader_parameter("scoring"))
	assert(app.get("audio").play_count == play_count + 1)
	assert(app.get("audio").last_kind == "start")
	app.call("_process", 0.0)
	assert(app.get("audio").play_count == play_count + 1)
	assert(audio.tracking_player.playing, "active center coverage starts continuous feedback")
	app.get("tracking").camera.look_at(app.get("tracking").target.global_position + Vector3(0.3, 0, 0))
	app.call("_process", 0.0)
	assert(audio.tracking_player.playing and audio.tracking_player.pitch_scale == 1.0, "outer coverage uses lower pitch")
	app.get("tracking").camera.rotation = Vector3(0, PI, 0)
	app.call("_process", 0.0)
	assert(not audio.tracking_player.playing, "outside coverage is silent")
	assert(target_material.get_shader_parameter("inner_color") == app.get("Palette").WARNING)
	audio.set_tracking_weight(0.5)
	assert(audio.tracking_player.playing and audio.tracking_player.pitch_scale == 1.0)
	audio.set_tracking_weight(1.0)
	assert(audio.tracking_player.playing and audio.tracking_player.pitch_scale == 2.0)
	audio.set_tracking_weight(0.0)
	assert(not audio.tracking_player.playing)
	tracking_state.coverage.assign([20.0, 40.0, 60.0, 80.0, 100.0])
	tracking_state.errors.assign([5.0, 4.0, 3.0, 2.0, 1.0])
	tracking_state.stage = TrackingState.Stage.SUMMARY
	app.call("complete_summary")
	assert(app.get("summary").visible)
	assert(is_equal_approx(app.get("summary_radar").values.tracking, Scores.points("tracking", 60.0)))
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	assert(not app.get("tracking").active)
	assert(not audio.tracking_player.playing)
	assert(app.get("result_snapshot").samples == [20.0, 40.0, 60.0, 80.0, 100.0])
	var cache = app.get("result_cache")
	assert(cache.latest("tracking").record.stats.median == 60.0)
	app.call("_save_session")
	assert(app.get("history").sessions.is_empty(), "save is only allowed on the menu")
	app.call("show_menu")
	assert(app.get("save_button").disabled, "partial sessions cannot be saved")
	app.call("_save_session")
	assert(app.get("history").sessions.is_empty())
	var settings_before := FileAccess.get_file_as_string(scores.score_path)
	for mode in Scores.PROJECTS:
		if mode.key == "tracking":
			continue
		app.call("enter_project", mode.page)
		var completed_state = app.get("osu_state") if mode.key == "osu" else app.get("sphere_state") if mode.key == "spheres" else app.get("state")
		completed_state.reactions_us.assign([100000, 200000, 300000, 400000, 500000])
		completed_state.stage = app.get("OsuState").Stage.SUMMARY if mode.key == "osu" else app.get("SphereState").Stage.SUMMARY if mode.key == "spheres" else app.get("ReactionState").Stage.SUMMARY
		app.call("complete_summary")
		assert(app.get("summary").visible)
	app.call("show_menu")
	assert(cache.selected(Time.get_ticks_usec()).size() == 5)
	assert(not app.get("save_button").disabled)
	assert(FileAccess.get_file_as_string(scores.score_path) == settings_before, "finishing tests never writes scores")
	var tracking_backup: Dictionary = cache.latest("tracking").record.duplicate(true)
	app.call("enter_project", "color")
	cache.entries.tracking.completed_us = Time.get_ticks_usec() - Cache.VALID_US
	app.call("_process", 0.0)
	assert(cache.expired(cache.latest("tracking"), Time.get_ticks_usec()), "cache expires while another test is open")
	cache.add(tracking_backup, Time.get_ticks_usec())
	app.call("show_menu")
	cache.entries.color.completed_us = Time.get_ticks_usec() - Cache.VALID_US
	app.call("_update_latest_scores")
	assert(app.get("save_button").disabled)
	assert("EXPIRED" in app.get("profile_total_status").text and app.get("profile_total").modulate.a < 1.0)
	assert("EXPIRED" in app.get("profile_status")[0].text)
	assert(app.get("profile_rows")[0].modulate.a < 1.0)
	assert("color" in app.get("menu_radar").expired_projects)
	app.call("_save_session")
	assert(app.get("history").sessions.is_empty(), "expiry is rechecked before saving")
	cache.add(History.snapshot("color", [100000, 200000, 300000, 400000, 500000], scores.look_sens), Time.get_ticks_usec())
	app.call("_update_latest_scores")
	app.get("menu_tag").text = "mouse-A"
	app.get("menu_tag").grab_focus()
	count_before = audio.play_count
	app.call("_unhandled_input", react)
	assert(audio.play_count == count_before, "menu tag typing cannot trigger gameplay audio")
	var history_store = app.get("history")
	var history_path: String = history_store.path
	history_store.path = test_prefix + "/missing/history.json"
	app.call("_save_session")
	assert(history_store.sessions.is_empty() and cache.selected(Time.get_ticks_usec()).size() == 5)
	assert(not app.get("save_button").disabled and app.get("menu_tag").text == "mouse-A")
	history_store.path = history_path
	app.call("_save_session")
	assert(app.get("save_button").disabled)
	assert(history_store.sessions.size() == 1 and history_store.records.size() == 5)
	assert(cache.selected(Time.get_ticks_usec()).is_empty())
	assert(app.get("menu_tag").text.is_empty())
	for row in app.get("profile_status"):
		assert("SAVED" in row.text, "saved scores remain on the menu")
	assert(app.get("menu_radar").values.size() == 5)
	var expected_total := 0.0
	for entry in cache.entries.values():
		expected_total += Scores.points(entry.record.project, entry.record.stats.median)
	assert(app.get("profile_total").text == "%.1f / 500" % expected_total)
	app.call("_save_session")
	assert(history_store.sessions.size() == 1, "duplicate save must not append")
	app.call("show_history")
	var history_page = app.get("history_page")
	history_page.refresh()
	assert(history_page.shown.size() == 1)
	assert(history_page.chart.groups.size() == 1 and history_page.chart.groups[0].results.size() == 5)
	assert(history_page.shown[0].tag == "mouse-A")
	history_page.call("_show_group", history_page.shown[0])
	assert("60.0 %" in history_page.detail_rules[4].text)
	assert(history_page.detail_rows[0].text == "2D REACTION" and history_page.detail_rows[3].text == "3D AIM")
	assert(history_page.shown[0].id == history_store.sessions[0].id)
	assert(history_page.radar.values.size() == 5)
	assert("/ 500" in history_page.list.get_item_text(0))
	for index in 55:
		var session: Dictionary = history_store.sessions[0].duplicate(true)
		session.id += "-%d" % index
		session.timestamp_utc += index + 1
		session.local_time = Time.get_datetime_string_from_unix_time(int(session.timestamp_utc) + int(session.utc_offset_minutes) * 60, true)
		session.tag = "mouse-B" if index % 2 == 0 else "mouse-A"
		for result in session.results:
			result.id += "-%d" % index
			result.tag = session.tag
		assert(History.valid_session(session))
		history_store.sessions.append(session)
		history_store.call("_index_session", session)
	var older_session: Dictionary = history_store.sessions[0].duplicate(true)
	older_session.id += "-old-rules"
	for result in older_session.results:
		result.id += "-old-rules"
		if result.project == "osu":
			result.rule_version = 2
	history_store.sessions.append(older_session)
	history_store.call("_index_session", older_session)
	var legacy_record: Dictionary = History.snapshot("tracking", [10.0, 10.0, 10.0, 10.0, 10.0], 1.0, [0, 0, 0, 0, 0])
	history_store.legacy_records.append(legacy_record)
	history_store.records.append(legacy_record)
	history_page.refresh()
	assert(history_page.filtered.size() == 58, "all sessions, versions and legacy singles are visible")
	assert(history_page.shown.size() == 50)
	assert(history_page.chart.groups.size() == 58)
	var chart = history_page.chart
	assert(not chart.gui_input.get_connections().is_empty(), "chart keeps shared UI audio bindings")
	assert(chart.maximum_offset() > 0.0 and chart.offset == chart.maximum_offset())
	var scroll := InputEventMouseButton.new()
	scroll.button_index = MOUSE_BUTTON_WHEEL_UP
	scroll.pressed = true
	chart.call("_gui_input", scroll)
	assert(chart.offset < chart.maximum_offset())
	await process_frame
	await process_frame
	assert(not chart.bars.is_empty())
	for item in chart.group_rects:
		if is_equal_approx(item.rect.size.x, chart.GROUP_WIDTH):
			var group_bars: Array = []
			for visible_bar in chart.bars:
				if item.rect.has_point(visible_bar.rect.get_center()):
					group_bars.append(visible_bar.rect)
			if group_bars.size() == item.group.results.size():
				var midpoint: float = (group_bars[0].position.x + group_bars[-1].end.x) * 0.5
				assert(is_equal_approx(midpoint, item.rect.get_center().x), "bars center in group bounds")
	var bar: Dictionary = chart.bars[-1]
	var motion := InputEventMouseMotion.new()
	motion.position = bar.rect.get_center()
	var selection_before: String = chart.selected_id
	chart.call("_gui_input", motion)
	assert(chart.hovered_id == bar.record.id and history_page.tooltip.visible)
	assert(chart.selected_id == selection_before, "hover cannot change the selected session")
	var chart_click := InputEventMouseButton.new()
	chart_click.button_index = MOUSE_BUTTON_LEFT
	chart_click.position = motion.position
	chart_click.pressed = true
	chart.call("_gui_input", chart_click)
	chart_click.pressed = false
	chart.call("_gui_input", chart_click)
	var selected_group: Dictionary = {}
	for entry in chart.groups:
		if entry.id == chart.selected_id:
			selected_group = entry
	assert(not selected_group.is_empty())
	assert(history_page.radar.values.size() == selected_group.results.size(), "click selects all results in the group")
	var selected_before_drag: String = chart.selected_id
	chart_click.pressed = true
	chart.call("_gui_input", chart_click)
	motion.relative = Vector2(30, 0)
	chart.call("_gui_input", motion)
	chart_click.pressed = false
	chart.call("_gui_input", chart_click)
	assert(chart.selected_id == selected_before_drag and not history_page.tooltip.visible, "drag scroll cannot select a session")
	var group: Dictionary = chart.groups[0]
	chart.group_selected.emit(group)
	assert(history_page.radar.values.size() == 5)
	assert(chart.selected_id == group.id)
	var other_result: Dictionary = group.results[0]
	chart.record_hovered.emit(other_result)
	assert(history_page.tooltip.visible)
	assert("Rules v" in history_page.tooltip_label.text and "Rounds (ms)" in history_page.tooltip_label.text)
	chart.record_hovered.emit({})
	assert(not history_page.tooltip.visible)
	assert(not history_page.next.disabled)
	history_page.next.pressed.emit()
	assert(history_page.shown.size() == 8)
	assert(history_page.next.disabled)
	history_page.previous.pressed.emit()
	assert(history_page.shown.size() == 50)
	var legacy_group: Dictionary = {}
	for entry in history_page.filtered:
		if entry.get("legacy", false):
			legacy_group = entry
	history_page.call("_show_group", legacy_group)
	assert(history_page.radar.values.size() == 1, "legacy radar never fabricates missing tests")
	assert("Legacy single result" in history_page.detail.text)
	var zero_group: Dictionary = legacy_group.duplicate(true)
	zero_group.results[0].samples = [0.0, 0.0, 0.0, 0.0, 0.0]
	zero_group.results[0].stats = History.summary_stats("tracking", zero_group.results[0].samples)
	var zero_groups: Array[Dictionary] = [zero_group]
	chart.set_groups(zero_groups)
	await process_frame
	await process_frame
	assert(chart.bars.size() == 1 and chart.bars[0].rect.size.y == 6.0, "zero-point bars remain hoverable")
	motion.position = chart.bars[0].rect.get_center()
	chart.call("_gui_input", motion)
	assert(history_page.tooltip.visible and "0.0 pts" in history_page.tooltip_label.text)
	chart.mouse_exited.emit()
	assert(not history_page.tooltip.visible and chart.hovered_id.is_empty())
	var empty_groups: Array[Dictionary] = []
	chart.set_groups(empty_groups)
	await process_frame
	await process_frame
	assert(chart.bars.is_empty() and chart.group_rects.is_empty())
	app.call("enter_project", "tracking")
	tracking_state.prepare(Time.get_ticks_usec())
	audio.set_tracking_weight(1.0)
	app.call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(tracking_state.stage == TrackingState.Stage.INVALID)
	assert(not audio.tracking_player.playing, "focus loss stops coverage feedback")
	assert(tracking_state.coverage.is_empty())
	assert(app.get("result_snapshot").is_empty())
	app.call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(tracking_state.stage == TrackingState.Stage.PREPARING)

	app.call("enter_project", "corner")
	app.get("state").reactions_us.assign([100000, 200000, 300000, 400000, 500000])
	app.get("state").stage = 5
	app.call("complete_summary")
	assert(not app.get("corner_watch").active)
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	app.call("_restart_project")
	assert(app.get("corner_watch").active)
	if DisplayServer.get_name() != "headless":
		assert(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	app.call("show_menu")
	app.call("enter_project", "color")
	app.call("complete_summary")
	assert(not app.get("summary").visible, "incomplete sets must not show a saveable result")
	app.call("show_menu")
	DirAccess.remove_absolute(test_prefix + "-scores.txt")
	DirAccess.remove_absolute(test_prefix + "-history.json")
	audio.player.stop()
	audio.tracking_player.stop()
	# Let the audio mixer release stopped voices before scene shutdown.
	await create_timer(0.2).timeout
	app.queue_free()
	await process_frame
	await process_frame
	print("playthrough_test: PASS")
	quit()


func _press_key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)
