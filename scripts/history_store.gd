extends RefCounted

const Scores = preload("res://scripts/score_store.gd")
const Config = preload("res://scripts/camera_3d_config.gd")
const FORMAT_VERSION := 1
const RULE_VERSION := 1
var path := "user://history.json"
var records: Array[Dictionary] = []
var error := ""
var writable := true


func _init(file_path: String = "user://history.json") -> void:
	path = file_path


func load_history() -> bool:
	records.clear()
	error = ""
	writable = true
	if not FileAccess.file_exists(path):
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot read history file. Existing history is protected.")
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _fail("History file is damaged. Existing history is protected.")
	var data: Variant = json.data
	if not data is Dictionary or data.get("version") != FORMAT_VERSION or not data.get("records") is Array:
		return _fail("Unsupported history format. Existing history is protected.")
	var ids := {}
	for record in data.records:
		if not valid_record(record) or ids.has(record.id):
			return _fail("History contains invalid records. Existing history is protected.")
		ids[record.id] = true
		records.append(record)
	return true


func _fail(message: String) -> bool:
	error = message
	writable = false
	records.clear()
	return false


static func snapshot(project: String, samples: Array, sensitivity: float, errors: Array = []) -> Dictionary:
	var unix := Time.get_unix_time_from_system()
	var offset: int = Time.get_time_zone_from_system().bias
	var local := Time.get_datetime_dict_from_unix_time(int(unix) + offset * 60)
	return {
		"id": "%d-%d-%s" % [int(unix * 1_000_000), Time.get_ticks_usec(), Crypto.new().generate_random_bytes(8).hex_encode()],
		"project": project, "rule_version": RULE_VERSION,
		"timestamp_utc": unix,
		"local_time": "%04d-%02d-%02d %02d:%02d:%02d" % [local.year, local.month, local.day, local.hour, local.minute, local.second],
		"utc_offset_minutes": offset,
		"samples": samples.duplicate(), "stats": summary_stats(project, samples),
		"look_sens": sensitivity, "tag": "", "errors_degrees": errors.duplicate(),
	}


static func summary_stats(project: String, samples: Array) -> Dictionary:
	var values: Array[float] = []
	for sample in samples:
		values.append(float(sample) if project == "tracking" else float(sample) / 1000.0)
	return Scores.statistics_values(values)


static func number_in_range(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high


static func valid_record(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["id", "project", "rule_version", "timestamp_utc", "local_time", "utc_offset_minutes", "samples", "stats", "look_sens", "tag", "errors_degrees"]:
		if not value.has(key):
			return false
	if not value.id is String or value.id.is_empty() or not value.project is String or not value.tag is String:
		return false
	if not value.project in ["color", "shooter", "osu", "spheres", "tracking"] or value.tag.length() > 64:
		return false
	if not number_in_range(value.rule_version, 1, 1_000_000) or float(value.rule_version) != floor(float(value.rule_version)):
		return false
	if not number_in_range(value.timestamp_utc, 0, 253402300799.0) or not number_in_range(value.utc_offset_minutes, -1440, 1440):
		return false
	if not value.local_time is String or value.local_time.length() != 19:
		return false
	if float(value.utc_offset_minutes) != floor(float(value.utc_offset_minutes)):
		return false
	var expected_local := Time.get_datetime_string_from_unix_time(int(value.timestamp_utc) + int(value.utc_offset_minutes) * 60, true)
	if value.local_time != expected_local:
		return false
	if not number_in_range(value.look_sens, Config.LOOK_SENS_MIN, Config.LOOK_SENS_MAX):
		return false
	if not value.samples is Array or value.samples.size() != 5 or not value.stats is Dictionary or not value.errors_degrees is Array:
		return false
	for sample in value.samples:
		if not number_in_range(sample, 0, 100.0 if value.project == "tracking" else 86_400_000_000.0):
			return false
	if value.project == "tracking":
		if value.errors_degrees.size() != 5:
			return false
		for degrees in value.errors_degrees:
			if not number_in_range(degrees, 0, 180):
				return false
	elif not value.errors_degrees.is_empty():
		return false
	var expected := summary_stats(value.project, value.samples)
	for key in ["median", "mean", "deviation"]:
		if not number_in_range(value.stats.get(key), 0, 86_400_000.0) or not is_equal_approx(float(value.stats[key]), expected[key]):
			return false
	return true


func save_record(record: Dictionary, tag: String) -> bool:
	if not writable:
		return false
	var candidate := record.duplicate(true)
	candidate.tag = tag.strip_edges().left(64)
	if not valid_record(candidate):
		error = "Cannot save an incomplete or invalid result."
		return false
	for existing in records:
		if existing.id == candidate.id:
			error = "This result is already saved."
			return false
	# ponytail: rewrite local history on save; use an append log if thousands of records make this slow.
	var updated := records.duplicate()
	updated.append(candidate)
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		error = "Cannot write history. Check the storage location and retry."
		return false
	file.store_string(JSON.stringify({"version": FORMAT_VERSION, "records": updated}, "", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temp_path, path) != OK:
		error = "Cannot finish saving history. Your result is available to retry."
		return false
	records.append(candidate)
	error = ""
	return true


func filtered(project: String, tag: String = "", rule_version: int = RULE_VERSION) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record in records:
		if record.project == project and int(record.rule_version) == rule_version and (tag.is_empty() or record.tag == tag):
			out.append(record)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.timestamp_utc < b.timestamp_utc)
	return out
