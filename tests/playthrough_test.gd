extends SceneTree

## Drive Main through OSU and Sphere Aim round start without a human.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var app: Node = packed.instantiate()
	get_root().add_child(app)
	await process_frame
	await process_frame

	app.call("enter_project", "osu")
	await process_frame
	_press_key(KEY_SPACE)
	await process_frame
	var centers: Array = app.get("osu_centers")
	assert(centers.size() == 6, "expected 6 osu circles, got %d" % centers.size())
	var osu_state = app.get("osu_state")
	for i in 6:
		osu_state.call("hit_next", Time.get_ticks_usec() + i * 10_000)
	assert(int(osu_state.get("stage")) == OsuState.Stage.NEXT, "osu round should finish")

	app.call("enter_project", "spheres")
	await process_frame
	_press_key(KEY_SPACE)
	await process_frame
	var sphere_state = app.get("sphere_state")
	assert(int(sphere_state.get("stage")) == SphereState.Stage.WAITING)
	# Jump wait.
	sphere_state.set("deadline_us", Time.get_ticks_usec())
	await process_frame
	await process_frame
	assert(int(sphere_state.get("stage")) == SphereState.Stage.AIMING, "spheres should enter aiming")
	var bodies: Array = app.get("sphere_aim").get("target_bodies")
	assert(bodies.size() == 6, "expected 6 spheres")

	app.call("show_menu")
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
