class_name ScoreStore
extends RefCounted

const SCORE_PATH := "user://scores.txt"
const Camera3DConfig = preload("res://scripts/camera_3d_config.gd")

const PROJECTS := [
	{"key": "color", "page": "color", "name": "2D REACTION"},
	{"key": "shooter", "page": "corner", "name": "3D REACTION"},
	{"key": "osu", "page": "osu", "name": "OSU"},
	{"key": "spheres", "page": "spheres", "name": "3D AIM"},
	{"key": "tracking", "page": "tracking", "name": "3D TRACKING"},
]

var score_path := SCORE_PATH
var color := 0.0
var shooter := 0.0
var osu := 0.0
var spheres := 0.0
var tracking := -1.0
var look_sens := Camera3DConfig.LOOK_SENS_DEFAULT


func load_scores() -> void:
	if not FileAccess.file_exists(score_path):
		return
	var file := FileAccess.open(score_path, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		var words := file.get_line().split(" ", false)
		if words.size() != 2 or not words[1].is_valid_float():
			continue
		var value := words[1].to_float()
		if not is_finite(value) or value < 0.0:
			continue
		match words[0]:
			"color":
				color = value
			"shooter":
				shooter = value
			"osu":
				osu = value
			"spheres":
				spheres = value
			"tracking":
				if value <= 100.0:
					tracking = value
			"look_sens":
				look_sens = Camera3DConfig.clamp_look_sensitivity(value)


func get_best(project: String) -> float:
	match project:
		"color":
			return color
		"shooter":
			return shooter
		"osu":
			return osu
		"spheres":
			return spheres
		"tracking":
			return tracking
		_:
			return 0.0


func update(project: String, median_ms: float) -> bool:
	var current := get_best(project)
	if not is_finite(median_ms) or median_ms < 0.0:
		return false
	if project == "tracking":
		if median_ms > 100.0 or (current >= 0.0 and median_ms <= current):
			return false
	elif not is_new_best(current, median_ms):
		return false
	match project:
		"color":
			color = median_ms
		"shooter":
			shooter = median_ms
		"osu":
			osu = median_ms
		"spheres":
			spheres = median_ms
		"tracking":
			tracking = median_ms
		_:
			return false
	if save_scores():
		return true
	set(project, current)
	return false


func set_look_sensitivity(value: float) -> bool:
	if not is_finite(value):
		return false
	var clamped := Camera3DConfig.clamp_look_sensitivity(value)
	if is_equal_approx(look_sens, clamped):
		return true
	var previous := look_sens
	look_sens = clamped
	if save_scores():
		return true
	look_sens = previous
	return false


static func is_new_best(current: float, candidate: float) -> bool:
	return is_finite(candidate) and candidate >= 0.0 and (current == 0.0 or candidate < current)


func save_scores() -> bool:
	var file := FileAccess.open(score_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(
		"color %.1f\nshooter %.1f\nosu %.1f\nspheres %.1f\nlook_sens %.2f\n"
		% [color, shooter, osu, spheres, look_sens]
	)
	if tracking >= 0.0:
		file.store_string("tracking %.6f\n" % tracking)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return false
	var error := DirAccess.rename_absolute(score_path + ".tmp", score_path)
	return error == OK


static func statistics(samples_us: Array[int]) -> Dictionary:
	var values: Array[float] = []
	for sample in samples_us:
		values.append(float(sample) / 1000.0)
	return statistics_values(values)


static func statistics_values(values: Array) -> Dictionary:
	assert(values.size() == 5)
	var sorted := values.duplicate()
	sorted.sort()
	var mean := 0.0
	for value in values:
		mean += float(value) / values.size()
	var squared := 0.0
	for value in values:
		squared += pow(float(value) - mean, 2)
	return {"median": float(sorted[2]), "mean": mean, "deviation": sqrt(squared / 4.0)}
