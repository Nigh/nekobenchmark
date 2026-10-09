class_name ScoreStore
extends RefCounted

const SCORE_PATH := "user://scores.txt"
const DATA_EPOCH := 2
const Camera3DConfig = preload("res://scripts/camera_3d_config.gd")
const Lab = preload("res://scripts/sens_lab.gd")

const PROJECTS := [
	{"key": "color", "page": "color", "name": "2D REACTION"},
	{"key": "shooter", "page": "corner", "name": "3D REACTION"},
	{"key": "osu", "page": "osu", "name": "OSU"},
	{"key": "spheres", "page": "spheres", "name": "3D AIM"},
	{"key": "tracking", "page": "tracking", "name": "3D TRACKING"},
]

var score_path := SCORE_PATH
var look_sens := Camera3DConfig.LOOK_SENS_DEFAULT
var lab_spacing := 3.0
var lab_distance := Lab.DISTANCE_DEFAULT
var writable := true
var error := ""


func load_scores() -> void:
	writable = true
	error = ""
	if not FileAccess.file_exists(score_path):
		return
	var file := FileAccess.open(score_path, FileAccess.READ)
	if file == null:
		_protect("Cannot read scores. Existing file is protected.")
		return
	var values := {}
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var words := line.split(" ", false)
		if words.size() != 2 or not words[1].is_valid_float() or values.has(words[0]):
			_protect("Scores are damaged. Existing file is protected.")
			return
		if words[0] not in ["data_epoch", "color", "shooter", "osu", "spheres", "tracking", "look_sens", "lab_spacing", "lab_distance"]:
			_protect("Unsupported scores. Existing file is protected.")
			return
		var value := words[1].to_float()
		if not is_finite(value) or value < 0.0:
			_protect("Scores are damaged. Existing file is protected.")
			return
		values[words[0]] = value
	if file.get_error() != OK and file.get_error() != ERR_FILE_EOF:
		_protect("Cannot read scores. Existing file is protected.")
		return
	file.close()
	if values.is_empty() or values.get("data_epoch", 1.0) not in [1.0, float(DATA_EPOCH)] or float(values.get("tracking", 0.0)) > 100.0:
		_protect("Unsupported or damaged scores. Existing file is protected.")
		return
	look_sens = Camera3DConfig.clamp_look_sensitivity(float(values.get("look_sens", look_sens)))
	lab_distance = clampf(float(values.get("lab_distance", Lab.DISTANCE_DEFAULT)), Lab.DISTANCE_MIN, Lab.DISTANCE_MAX)
	lab_spacing = clampf(float(values.get("lab_spacing", 3.0)), Lab.SPHERE_RADIUS * 2.0, Lab.max_square_half_at(lab_distance) * 2.0)
	if values.get("data_epoch", 1.0) != DATA_EPOCH and not save_scores():
		_protect("Cannot reset old scores. Restart to retry.")


func _protect(message: String) -> void:
	writable = false
	error = message


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


func set_lab_layout(spacing: float, distance: float) -> bool:
	if not is_finite(spacing) or not is_finite(distance):
		return false
	distance = clampf(distance, Lab.DISTANCE_MIN, Lab.DISTANCE_MAX)
	spacing = clampf(spacing, Lab.SPHERE_RADIUS * 2.0, Lab.max_square_half_at(distance) * 2.0)
	if is_equal_approx(lab_spacing, spacing) and is_equal_approx(lab_distance, distance):
		return true
	var previous_spacing := lab_spacing
	var previous_distance := lab_distance
	lab_spacing = spacing
	lab_distance = distance
	if save_scores():
		return true
	lab_spacing = previous_spacing
	lab_distance = previous_distance
	return false


func save_scores() -> bool:
	if not writable:
		return false
	var file := FileAccess.open(score_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(
		"data_epoch %d\nlook_sens %.2f\nlab_spacing %.6f\nlab_distance %.2f\n"
		% [DATA_EPOCH, look_sens, lab_spacing, lab_distance]
	)
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


static func points(project: String, value: float) -> float:
	if not is_finite(value):
		return 0.0
	if project == "tracking":
		value = clampf(value, 0.0, 100.0)
		return 60.0 * log(1.0 + value) / log(31.0) if value <= 30.0 else 60.0 + 40.0 * log(value / 30.0) / log(100.0 / 30.0)
	if project == "spheres":
		return clampf(60.0 * log(6000.0 / maxf(value, 0.001)) / log(6000.0 / 2400.0), 0.0, 100.0)
	var fastest := 500.0 if project == "osu" else 50.0
	var middle := 1800.0 if project == "osu" else 220.0
	var middle_points := 70.0 if project == "osu" else 80.0
	var timeout := 6000.0 if project == "osu" else 1000.0
	if value <= fastest:
		return 100.0
	if value <= middle:
		return 100.0 - (100.0 - middle_points) * log(value / fastest) / log(middle / fastest)
	return clampf(middle_points * log(timeout / value) / log(timeout / middle), 0.0, 100.0)


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


static func display(project: String, value: float) -> String:
	return "%.1f pts / %.1f %s" % [points(project, value), value, "%" if project == "tracking" else "ms"]
