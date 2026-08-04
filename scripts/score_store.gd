class_name ScoreStore
extends RefCounted

const SCORE_PATH := "user://scores.txt"
const TEMP_PATH := "user://scores.txt.tmp"
const Camera3DConfig = preload("res://scripts/camera_3d_config.gd")

# ponytail: fixed per-mode windows so radar axes are comparable; retune from real runs.
const PROFILE_AXES := [
	{"key": "color", "label": "COLOR", "name": "COLOR REACTION", "lo": 120.0, "hi": 400.0},
	{"key": "shooter", "label": "CORNER", "name": "CORNER WATCH", "lo": 150.0, "hi": 500.0},
	{"key": "osu", "label": "OSU", "name": "OSU", "lo": 400.0, "hi": 2000.0},
	{"key": "spheres", "label": "SPHERE", "name": "SPHERE AIM", "lo": 500.0, "hi": 3000.0},
]

var color := 0.0
var shooter := 0.0
var osu := 0.0
var spheres := 0.0
var look_sens := Camera3DConfig.LOOK_SENS_DEFAULT


# Lower ms → higher radius. Missing (0) returns -1 so the UI can skip the fill.
static func radar_radius(ms: float, lo: float, hi: float) -> float:
	if ms <= 0.0:
		return -1.0
	return clampf((hi - ms) / (hi - lo), 0.0, 1.0)


func profile_radii() -> Array[float]:
	var out: Array[float] = []
	for axis in PROFILE_AXES:
		out.append(radar_radius(get_best(axis.key), axis.lo, axis.hi))
	return out


func load_scores() -> void:
	if not FileAccess.file_exists(SCORE_PATH):
		return
	var file := FileAccess.open(SCORE_PATH, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		var words := file.get_line().split(" ", false)
		if words.size() != 2 or not words[1].is_valid_float():
			continue
		var value := words[1].to_float()
		if value < 0.0:
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
		_:
			return 0.0


func update(project: String, median_ms: float) -> bool:
	var current := get_best(project)
	if not is_new_best(current, median_ms):
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
		_:
			return false
	return save_scores()


func set_look_sensitivity(value: float) -> bool:
	var clamped := Camera3DConfig.clamp_look_sensitivity(value)
	if is_equal_approx(look_sens, clamped):
		return true
	look_sens = clamped
	return save_scores()


static func is_new_best(current: float, candidate: float) -> bool:
	return candidate >= 0.0 and (current == 0.0 or candidate < current)


func save_scores() -> bool:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(
		"color %.1f\nshooter %.1f\nosu %.1f\nspheres %.1f\nlook_sens %.2f\n"
		% [color, shooter, osu, spheres, look_sens]
	)
	file.close()
	var error := DirAccess.rename_absolute(TEMP_PATH, SCORE_PATH)
	return error == OK


static func statistics(samples_us: Array[int]) -> Dictionary:
	assert(samples_us.size() == 5)
	var sorted := samples_us.duplicate()
	sorted.sort()
	var sum := 0.0
	for sample in samples_us:
		sum += float(sample) / 1000.0
	var mean := sum / samples_us.size()
	var squared := 0.0
	for sample in samples_us:
		var delta := float(sample) / 1000.0 - mean
		squared += delta * delta
	return {
		"median": float(sorted[sorted.size() / 2]) / 1000.0,
		"mean": mean,
		"deviation": sqrt(squared / (samples_us.size() - 1)),
	}
