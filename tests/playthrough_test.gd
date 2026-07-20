extends SceneTree

const OsuState = preload("res://scripts/osu_state.gd")
const SphereState = preload("res://scripts/sphere_state.gd")
const Camera3DConfig = preload("res://scripts/camera_3d_config.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var app: Node = packed.instantiate()
	get_root().add_child(app)
	await process_frame
	await process_frame

	assert(float(app.get("OSU_SPACING")) == 360.0, "osu spacing should be 360")

	app.call("enter_project", "osu")
	await process_frame
	_press_key(KEY_SPACE)
	await process_frame
	var centers: Array = app.get("osu_centers")
	assert(centers.size() == 6, "expected 6 osu circles, got %d" % centers.size())
	var spacing: float = float(app.get("OSU_SPACING"))
	var radius: float = float(app.get("OSU_RADIUS"))
	for i in centers.size() - 1:
		assert(is_equal_approx(centers[i].distance_to(centers[i + 1]), spacing), "adjacent spacing must match")
	for i in centers.size() - 2:
		assert(centers[i].distance_to(centers[i + 2]) >= radius * 2.0 - 0.01, "consecutive triple overlap")
	var osu_nodes: Array = app.get("osu_circle_nodes")
	var visible_count := 0
	for node in osu_nodes:
		if node.visible:
			visible_count += 1
	assert(visible_count == 2, "osu should show only next two circles")
	var osu_state = app.get("osu_state")
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
	sphere_state.set("deadline_us", Time.get_ticks_usec())
	await process_frame
	await process_frame
	assert(int(sphere_state.get("stage")) == SphereState.Stage.AIMING, "wait should spawn targets")
	var bodies: Array = sphere_aim.get("target_bodies")
	assert(bodies.size() == 6, "expected 6 spheres")
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
	sens_lab.call("nudge_spacing", 0.16)
	assert(float(sens_lab.call("spacing_side")) >= before - 0.001)
	var scores = app.get("scores")
	var sens_before: float = float(scores.get("look_sens"))
	app.call("_nudge_look_sensitivity", 0.05)
	assert(is_equal_approx(float(scores.get("look_sens")), Camera3DConfig.clamp_look_sensitivity(sens_before + 0.05)))
	assert(bool(app.get("sens_chrome_full")), "sens adjust should reveal panel")
	app.call("_apply_sens_slider_at", 330.0 + 310.0)
	var dragged: float = float(scores.get("look_sens"))
	assert(is_equal_approx(dragged, snappedf(dragged, Camera3DConfig.LOOK_SENS_FINE_STEP)))

	for i in 4:
		sens_lab.call("_defeat", i)
	assert(int(sens_lab.call("alive_count")) == 0)
	sens_lab.call("spawn_gate")
	assert(bool(sens_lab.get("gate_active")))
	assert(sens_lab.get("target_bodies").size() == 1)
	sens_lab.call("_defeat", 0)
	sens_lab.call("spawn_targets")
	assert(sens_lab.get("target_bodies").size() == 4, "sens-lab should respawn 4 after gate")
	assert(not bool(sens_lab.get("gate_active")))

	app.call("show_menu")
	await process_frame
	assert(app.get("profile_radar") != null, "menu should show profile radar")
	assert(app.get("profile_rows").size() == 4, "profile should list four bests")
	const ScoreStore = preload("res://scripts/score_store.gd")
	assert(is_equal_approx(ScoreStore.radar_radius(260.0, 120.0, 400.0), 0.5))
	assert(ScoreStore.radar_radius(0.0, 120.0, 400.0) < 0.0)
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
