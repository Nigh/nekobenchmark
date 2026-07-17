class_name ScoreStore
extends RefCounted

const SCORE_PATH := "user://scores.txt"
const TEMP_PATH := "user://scores.txt.tmp"

var color := 0.0
var shooter := 0.0


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
		if words[0] == "color":
			color = value
		elif words[0] == "shooter":
			shooter = value


func update(project: String, median_ms: float) -> bool:
	var current := color if project == "color" else shooter
	if not is_new_best(current, median_ms):
		return false
	if project == "color":
		color = median_ms
	else:
		shooter = median_ms
	return save_scores()


static func is_new_best(current: float, candidate: float) -> bool:
	return candidate >= 0.0 and (current == 0.0 or candidate < current)


func save_scores() -> bool:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("color %.1f\nshooter %.1f\n" % [color, shooter])
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
