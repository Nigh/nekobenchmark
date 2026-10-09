extends SceneTree

const History = preload("res://scripts/history_store.gd")
const Tracking = preload("res://scripts/tracking_state.gd")
const Scores = preload("res://scripts/score_store.gd")
const Cache = preload("res://scripts/result_cache.gd")
const Room = preload("res://scripts/practice_room.gd")


func _init() -> void:
	_test_cache()
	_test_fixed_layouts_and_order()
	_test_grading_and_preparation()
	var prefix := "user://history-check-%d" % Time.get_ticks_usec()
	var path := prefix + ".json"
	var history = History.new(path)
	assert(history.load_history())
	var results := _results()
	var record: Dictionary = results[0]
	assert(not history.save_session([record], "partial"))
	assert(history.save_session(results, "  mouse-A  "))
	assert(not history.save_session(results, "mouse-A"))
	assert(history.sessions.size() == 1 and history.records.size() == 5)
	assert(results[0].tag == "", "saving cannot mutate cached snapshots")
	var loaded = History.new(path)
	assert(loaded.load_history(), loaded.error)
	assert(loaded.sessions.size() == 1 and loaded.records.size() == 5)
	assert(loaded.sessions[0].tag == "mouse-A")
	for index in 5:
		assert(int(loaded.sessions[0].results[0].samples[index]) == record.samples[index])
	assert(loaded.sessions[0].results[0].local_time == record.local_time)
	assert(loaded.filtered("color", "mouse-A").size() == 1)
	assert(loaded.filtered("color", "mouse-B").is_empty())
	assert(loaded.filtered("tracking")[0].rule_version == 4)
	assert(loaded.get_session(loaded.records[0]).results.size() == 5)
	var future := _results()
	future[0].rule_version = 2
	assert(history.save_session(future, ""))
	assert(history.filtered("color").size() == 1)
	assert(history.filtered("color", "", 2).size() == 1)
	var invalid := record.duplicate(true)
	invalid.samples = [1, 2]
	assert(not History.valid_record(invalid))
	invalid = record.duplicate(true)
	invalid.local_time = "2026-99-99 99:99:99"
	assert(not History.valid_record(invalid))
	invalid = record.duplicate(true)
	invalid.stats.median = 999
	assert(not History.valid_record(invalid))
	invalid = record.duplicate(true)
	invalid.samples[0] = NAN
	assert(not History.valid_record(invalid))
	var invalid_session: Dictionary = history.sessions[0].duplicate(true)
	invalid_session.results[1] = invalid_session.results[0].duplicate(true)
	assert(not History.valid_session(invalid_session))
	var blocked = History.new(prefix + "/missing/history.json")
	assert(not blocked.save_session(_results(), ""))
	assert(blocked.records.is_empty() and blocked.sessions.is_empty())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("broken history")
	file.close()
	assert(not loaded.load_history())
	assert(not loaded.save_session(_results(), ""))
	assert(FileAccess.get_file_as_string(path) == "broken history")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"version": 3, "sessions": []}')
	file.close()
	assert(not loaded.load_history() and not loaded.writable)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 2, "data_epoch": 2, "sessions": [invalid_session]}))
	file.close()
	assert(not loaded.load_history() and not loaded.writable)
	var legacy_text := JSON.stringify({"version": 1, "data_epoch": 2, "records": [record]})
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(legacy_text)
	file.close()
	assert(loaded.load_history() and loaded.legacy_records.size() == 1 and loaded.sessions.is_empty())
	assert(FileAccess.get_file_as_string(path) == legacy_text)
	assert(loaded.save_session(_results(), "new"))
	assert(loaded.load_history() and loaded.legacy_records.size() == 1 and loaded.sessions.size() == 1)
	assert(loaded.records.size() == 6)
	DirAccess.remove_absolute(path)

	var scores = Scores.new()
	scores.score_path = prefix + "-scores.txt"
	file = FileAccess.open(scores.score_path, FileAccess.WRITE)
	file.store_string("color 250.0\nshooter 300.0\nosu 1000.0\nspheres 1500.0\nlook_sens 1.25\n")
	file.close()
	scores.load_scores()
	assert(scores.look_sens == 1.25, "reset preserves sensitivity")
	assert("data_epoch 2" in FileAccess.get_file_as_string(scores.score_path))
	assert(not "color " in FileAccess.get_file_as_string(scores.score_path), "settings file never persists cached scores")
	assert(scores.set_lab_layout(4.0, 12.0))
	var read_scores = Scores.new()
	read_scores.score_path = scores.score_path
	read_scores.load_scores()
	assert(read_scores.look_sens == 1.25)
	assert(read_scores.lab_spacing == 4.0 and read_scores.lab_distance == 12.0)
	scores.score_path = prefix + "/missing/scores.txt"
	assert(not scores.set_lab_layout(3.0, 8.0))
	assert(scores.lab_spacing == 4.0 and scores.lab_distance == 12.0)
	assert(not scores.set_look_sensitivity(2.0))
	assert(scores.look_sens == 1.25)
	DirAccess.remove_absolute(read_scores.score_path)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "records": [record]}))
	file.close()
	assert(loaded.load_history() and loaded.records.is_empty())
	assert(loaded.save_session(_results(), "new"))
	assert(loaded.load_history() and loaded.sessions.size() == 1)
	DirAccess.remove_absolute(path)
	var damaged := Scores.new()
	damaged.score_path = read_scores.score_path
	for text in ["broken scores", "unknown 1\n", "data_epoch 3\ncolor 100\n", "color nan\n", "color 10\ncolor 20\n"]:
		file = FileAccess.open(damaged.score_path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		damaged.load_scores()
		assert(not damaged.writable and not damaged.set_look_sensitivity(2.0))
		assert(FileAccess.get_file_as_string(damaged.score_path) == text)
	DirAccess.remove_absolute(damaged.score_path)
	var old_scores_text := "color 200.0\nlook_sens 1.35\n"
	file = FileAccess.open(damaged.score_path, FileAccess.WRITE)
	file.store_string(old_scores_text)
	file.close()
	assert(DirAccess.make_dir_absolute(damaged.score_path + ".tmp") == OK)
	damaged.load_scores()
	assert(not damaged.writable and damaged.look_sens == 1.35)
	assert(FileAccess.get_file_as_string(damaged.score_path) == old_scores_text)
	DirAccess.remove_absolute(damaged.score_path + ".tmp")
	assert(not damaged.set_look_sensitivity(2.0))
	damaged.load_scores()
	assert(damaged.writable and damaged.look_sens == 1.35)
	DirAccess.remove_absolute(damaged.score_path)
	var old_history_text := JSON.stringify({"version": 1, "records": [record]})
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(old_history_text)
	file.close()
	assert(DirAccess.make_dir_absolute(path + ".tmp") == OK)
	assert(not loaded.load_history() and not loaded.writable and loaded.records.is_empty())
	assert(FileAccess.get_file_as_string(path) == old_history_text)
	DirAccess.remove_absolute(path + ".tmp")
	assert(loaded.load_history() and loaded.records.is_empty())
	DirAccess.remove_absolute(path)

	var state = Tracking.new()
	state.prepare(100)
	state.advance(100, 0.5, 0.0)
	assert(not state.advance(500_100, 0.5, 0.0))
	assert(state.acquired_us == 500_000)
	state.advance(600_100, 0.0, 0.0)
	assert(state.acquired_us == 0)
	state.advance(900_100, 0.5, 0.0)
	assert(state.acquired_us == 0, "first covered sample cannot credit an uncovered interval")
	state.advance(1_900_099, 0.5, 0.0)
	assert(state.stage == Tracking.Stage.PREPARING)
	state.advance(1_900_100, 0.5, 0.0)
	assert(state.stage == Tracking.Stage.ACTIVE)
	assert(state.motion_start_us == 100, "acquisition does not restart movement")
	assert(state.covered_us == 0)
	for round_index in 5:
		if state.stage == Tracking.Stage.PREPARING:
			state.advance(state.motion_start_us, 0.5, 0.0)
			state.advance(state.motion_start_us + Tracking.ACQUIRE_US, 0.5, 0.0)
		assert(state.stage == Tracking.Stage.ACTIVE)
		var start: int = state.start_us
		state.advance(start + 2_000_000, 1.0, 2.0)
		state.advance(start + 9_000_000, 0.0, 12.0)
		assert(state.advance(start + 11_000_000, 0.5, 2.0))
		assert(state.coverage[round_index] == 25.0)
		assert(is_equal_approx(state.errors[round_index], 9.0))
	assert(state.stage == Tracking.Stage.SUMMARY)
	assert(History.valid_record(History.snapshot("tracking", state.coverage, 1.0, state.errors)))
	state.reset()
	state.prepare(0)
	state.advance(0, 1.0, 0.0)
	state.advance(Tracking.ACQUIRE_US, 1.0, 0.0)
	state.advance(state.start_us + Tracking.ROUND_US, 0.0, 180.0)
	assert(state.coverage[0] == 0.0)
	state.advance(state.motion_start_us, 0.5, 0.0)
	state.advance(state.motion_start_us + Tracking.ACQUIRE_US, 0.5, 0.0)
	state.advance(state.start_us + Tracking.ROUND_US, 1.0, 0.0)
	assert(state.coverage[1] == 100.0)
	state.advance(state.motion_start_us, 0.5, 0.0)
	state.advance(state.motion_start_us + Tracking.ACQUIRE_US, 0.5, 0.0)
	state.advance(state.start_us + Tracking.ROUND_US, 0.5, 0.0)
	assert(state.coverage[2] == 50.0)
	var origin := Vector3(0, 1.4, 0)
	var target := Vector3(0, 1.4, -8)
	assert(Tracking.score_weight(origin, Vector3.FORWARD, target) == 1.0)
	for offset in [0.21, 0.3, 0.42, 0.43]:
		var direction := (target + Vector3(offset, 0, 0) - origin).normalized()
		assert(Tracking.score_weight(origin, direction, target) == (1.0 if offset == 0.21 else 0.5 if offset <= 0.42 else 0.0))
	assert(Tracking.score_weight(origin, Vector3.FORWARD, Vector3(0, 1.4, -8)) == 1.0)
	assert(Tracking.score_weight(origin, Vector3.BACK, target) == 0.0)
	assert(Tracking.score_weight(origin, Vector3.FORWARD, Vector3(0, 1.4, 8)) == 0.0)
	for round_index in 5:
		assert(Tracking.target_position(round_index, 0.0).is_equal_approx(Tracking.target_position(round_index, 10.0)))
		var velocity_before := (Tracking.target_position(round_index, 10.0) - Tracking.target_position(round_index, 9.999)) / 0.001
		var velocity_after := (Tracking.target_position(round_index, 0.001) - Tracking.target_position(round_index, 0.0)) / 0.001
		assert(velocity_before.distance_to(velocity_after) < 0.01)
		var fastest := 0.0
		var slowest := INF
		for step in 1001:
			var position := Tracking.target_position(round_index, step / 100.0)
			assert(Room.contains_point(position, Tracking.RADIUS))
			assert(position == Tracking.target_position(round_index, step / 100.0))
			assert(Tracking.score_weight(origin, (position - origin).normalized(), position) == 1.0)
			var speed := position.distance_to(Tracking.target_position(round_index, step / 100.0 + 0.001)) / 0.001
			fastest = maxf(fastest, speed)
			slowest = minf(slowest, speed)
		assert(fastest > 12.0 and fastest > slowest * 3.0)
	print("history_tracking_test: PASS")
	quit()


static func _result(project: String, score: float) -> Dictionary:
	var samples: Array = []
	for index in 5:
		samples.append(score if project == "tracking" else int(score * 1000.0))
	return History.snapshot(project, samples, 1.25, [0, 0, 0, 0, 0] if project == "tracking" else [])


static func _results() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for project in Scores.PROJECTS:
		results.append(_result(project.key, 50.0 if project.key == "tracking" else 300.0))
	return results


func _test_cache() -> void:
	var cache := Cache.new()
	const MINUTE := 60_000_000
	cache.add(_result("color", 100.0), 0)
	cache.add(_result("color", 300.0), 10 * MINUTE)
	assert(cache.latest("color").record.stats.median == 300.0, "latest replaces even a better score")
	assert(not cache.expired(cache.latest("color"), 70 * MINUTE - 1))
	assert(cache.expired(cache.latest("color"), 70 * MINUTE))
	assert(cache.selected(70 * MINUTE).is_empty())
	assert(cache.displayed().size() == 1, "expired result remains visible")
	cache.clear()
	var results := _results()
	for index in results.size():
		cache.add(results[index], index * 10 * MINUTE)
	results[0].samples[0] = 999
	assert(cache.latest("color").record.samples[0] == 300000, "cache owns frozen snapshots")
	assert(cache.selected(59 * MINUTE).size() == 5)
	cache.mark_saved()
	assert(cache.selected(59 * MINUTE).is_empty(), "saved snapshots cannot be saved twice")
	assert(cache.displayed().size() == 5, "saving does not clear display")
	cache.add(_result("tracking", 0.0), 60 * MINUTE)
	assert(cache.selected(60 * MINUTE).size() == 1, "valid zero score replaces saved result")
	assert(cache.displayed().size() == 5)
	cache.clear()
	assert(cache.displayed().is_empty())
	assert(Cache.new().displayed().is_empty(), "cache never survives app restart")


func _test_grading_and_preparation() -> void:
	for project in ["color", "shooter"]:
		assert(is_equal_approx(Scores.points(project, 50.0), 100.0))
		assert(is_equal_approx(Scores.points(project, 220.0), 80.0))
		assert(Scores.points(project, 1000.0) == 0.0)
	assert(is_equal_approx(Scores.points("osu", 500.0), 100.0))
	assert(is_equal_approx(Scores.points("osu", 1800.0), 70.0))
	assert(Scores.points("osu", 6000.0) == 0.0)
	assert(is_equal_approx(Scores.points("spheres", 2400.0), 60.0))
	assert(Scores.points("spheres", 6000.0) == 0.0)
	assert(is_equal_approx(Scores.points("tracking", 30.0), 60.0))
	assert(Scores.points("tracking", 0.0) == 0.0)
	assert(is_equal_approx(Scores.points("tracking", 100.0), 100.0))
	for project in ["color", "shooter", "osu", "spheres", "tracking"]:
		var previous := Scores.points(project, 0.0)
		for value in range(1, 6100):
			var current := Scores.points(project, float(value))
			assert(current >= 0.0 and current <= 100.000001)
			assert(current >= previous - 0.000001 if project == "tracking" else current <= previous + 0.000001)
			previous = current
	var origin := Vector3(0, 1.4, 0)
	for index in 5:
		var state := Tracking.new()
		state.coverage.resize(index)
		state.prepare(0)
		for step in range(1000):
			var a := Tracking.target_position(state.path_index(), state.movement_seconds(step * 10_000)) - origin
			var b := Tracking.target_position(state.path_index(), state.movement_seconds(step * 10_000 + 1000)) - origin
			assert(rad_to_deg(a.angle_to(b)) / 0.001 <= Tracking.PREP_MAX_SPEED + 0.1)
		var before := state.movement_seconds(2_000_000)
		state.stage = Tracking.Stage.ACTIVE
		state.start_us = 2_000_000
		assert(is_equal_approx(before, state.movement_seconds(state.start_us)))
		var slow := state.preparation_speed()
		assert(absf((state.movement_seconds(state.start_us + 1000) - before) / 0.001 - slow) < 0.001)
		assert(absf((state.movement_seconds(state.start_us + 1_001_000) - state.movement_seconds(state.start_us + 1_000_000)) / 0.001 - 1.0) < 0.00001)


func _test_fixed_layouts_and_order() -> void:
	var aim_script = preload("res://scripts/sphere_aim.gd")
	assert(aim_script.LAYOUTS.size() == 5)
	var origin := Vector3(0, 1.4, 0)
	for layout in aim_script.LAYOUTS:
		assert(layout.size() == aim_script.TARGET_COUNT)
		var quadrants := [false, false, false, false]
		for index in layout.size():
			var pos: Vector3 = layout[index]
			assert(Room.contains_point(pos, aim_script.SPHERE_RADIUS + 0.1))
			assert(Vector3.FORWARD.angle_to(pos - origin) <= deg_to_rad(30.0))
			quadrants[(0 if pos.x < 0 else 1) + (0 if pos.y > origin.y else 2)] = true
			for other in range(index):
				assert(pos.distance_to(layout[other]) >= aim_script.MIN_SEPARATION)
				var a: Vector3 = pos - origin
				var b: Vector3 = layout[other] - origin
				assert(a.angle_to(b) > asin(aim_script.SPHERE_RADIUS / a.length()) + asin(aim_script.SPHERE_RADIUS / b.length()), "targets cannot overlap from the starting view")
		assert(not false in quadrants)
	var state = Tracking.new()
	var orders := {}
	for attempt in 20:
		state.reset()
		orders[str(state.path_order)] = true
		var sorted: Array = state.path_order.duplicate()
		sorted.sort()
		assert(sorted == [0, 1, 2, 3, 4])
		for index in 5:
			state.coverage.resize(index)
			assert(state.path_index() == state.path_order[index])
	assert(orders.size() > 1, "sets shuffle path order")
