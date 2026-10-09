extends RefCounted

const Scores = preload("res://scripts/score_store.gd")
const Config = preload("res://scripts/camera_3d_config.gd")
const FORMAT_VERSION := 2
const RULE_VERSION := 1
const TRACKING_RULE_VERSION := 4
var path := "user://history.json"
var sessions: Array[Dictionary] = []
var legacy_records: Array[Dictionary] = []
var records: Array[Dictionary] = []
var error := ""
var writable := true


func _init(file_path: String = "user://history.json") -> void:
	path = file_path


func load_history() -> bool:
	records.clear()
	sessions.clear()
	legacy_records.clear()
	error = ""
	writable = true
	if not FileAccess.file_exists(path):
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot read history file. Existing history is protected.")
	var json := JSON.new()
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK or json.parse(text) != OK:
		return _fail("History file is damaged. Existing history is protected.")
	var data: Variant = json.data
	if not data is Dictionary or (data.get("version") != 1 and data.get("version") != FORMAT_VERSION):
		return _fail("Unsupported history format. Existing history is protected.")
	if data.get("data_epoch", 1) != 1 and data.get("data_epoch", 1) != Scores.DATA_EPOCH:
		return _fail("Unsupported history generation. Existing history is protected.")
	var old: Variant = data.get("records") if data.version == 1 else data.get("legacy_records", [])
	var groups: Variant = [] if data.version == 1 else data.get("sessions")
	if not old is Array or not groups is Array:
		return _fail("History contains invalid records. Existing history is protected.")
	var ids := {}
	for record in old:
		if not valid_record(record) or ids.has(record.id):
			return _fail("History contains invalid records. Existing history is protected.")
		ids[record.id] = true
		legacy_records.append(record)
	var session_ids := {}
	for session in groups:
		if not valid_session(session) or session_ids.has(session.id):
			return _fail("History contains invalid sessions. Existing history is protected.")
		session_ids[session.id] = true
		for record in session.results:
			if ids.has(record.id):
				return _fail("History contains repeated results. Existing history is protected.")
			ids[record.id] = true
		sessions.append(session)
	if data.get("data_epoch", 1) != Scores.DATA_EPOCH:
		sessions.clear()
		legacy_records.clear()
		if not _write_history(sessions):
			return _fail("Cannot reset old history. Restart to retry.")
	records.assign(legacy_records)
	for session in sessions:
		_index_session(session)
	return true


func _fail(message: String) -> bool:
	error = message
	writable = false
	records.clear()
	sessions.clear()
	legacy_records.clear()
	return false


static func snapshot(project: String, samples: Array, sensitivity: float, errors: Array = []) -> Dictionary:
	var unix := Time.get_unix_time_from_system()
	var offset: int = Time.get_time_zone_from_system().bias
	var local := Time.get_datetime_dict_from_unix_time(int(unix) + offset * 60)
	return {
		"id": "%d-%d-%s" % [int(unix * 1_000_000), Time.get_ticks_usec(), Crypto.new().generate_random_bytes(8).hex_encode()],
		"project": project, "rule_version": current_rule_version(project),
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


static func valid_session(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["id", "timestamp_utc", "local_time", "utc_offset_minutes", "tag", "results"]:
		if not value.has(key):
			return false
	if not value.id is String or value.id.is_empty() or not value.tag is String or value.tag.length() > 64:
		return false
	if not number_in_range(value.timestamp_utc, 0, 253402300799.0) or not number_in_range(value.utc_offset_minutes, -1440, 1440):
		return false
	if float(value.utc_offset_minutes) != floor(float(value.utc_offset_minutes)) or not value.local_time is String:
		return false
	if value.local_time != Time.get_datetime_string_from_unix_time(int(value.timestamp_utc) + int(value.utc_offset_minutes) * 60, true):
		return false
	if not value.results is Array or value.results.size() != Scores.PROJECTS.size():
		return false
	var projects := {}
	var ids := {}
	for record in value.results:
		if not valid_record(record) or projects.has(record.project) or ids.has(record.id) or record.tag != value.tag:
			return false
		projects[record.project] = true
		ids[record.id] = true
	return true


func save_session(results: Array[Dictionary], tag: String) -> bool:
	if not writable:
		return false
	var unix := Time.get_unix_time_from_system()
	var offset: int = Time.get_time_zone_from_system().bias
	var session := {
		"id": "%d-%s" % [Time.get_ticks_usec(), Crypto.new().generate_random_bytes(8).hex_encode()],
		"timestamp_utc": unix,
		"local_time": Time.get_datetime_string_from_unix_time(int(unix) + offset * 60, true),
		"utc_offset_minutes": offset, "tag": tag.strip_edges().left(64),
		"results": results.duplicate(true),
	}
	for record in session.results:
		record.tag = session.tag
	if not valid_session(session):
		error = "Complete all five tests before saving a session."
		return false
	var existing_ids := {}
	for record in records:
		existing_ids[record.id] = true
	for record in session.results:
		if existing_ids.has(record.id):
			error = "This session contains an already saved result."
			return false
	var updated := sessions.duplicate()
	updated.append(session)
	if not _write_history(updated):
		return false
	sessions.append(session)
	_index_session(session)
	error = ""
	return true


func _index_session(session: Dictionary) -> void:
	for result in session.results:
		var record: Dictionary = result.duplicate(true)
		record.session_id = session.id
		record.session_timestamp_utc = session.timestamp_utc
		record.session_local_time = session.local_time
		records.append(record)


func get_session(record: Dictionary) -> Dictionary:
	for session in sessions:
		if session.id == record.get("session_id", ""):
			return session
	return {}


func _write_history(updated: Array) -> bool:
	# shortcut: rewrite local history on save; use an append log if thousands of sessions make this slow.
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "Cannot write history. Check the storage location and retry."
		return false
	file.store_string(JSON.stringify({"version": FORMAT_VERSION, "data_epoch": Scores.DATA_EPOCH, "sessions": updated, "legacy_records": legacy_records}, "", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "Cannot finish saving history. Unsaved results remain available until expiry."
		return false
	return true


static func current_rule_version(project: String) -> int:
	if project == "tracking":
		return TRACKING_RULE_VERSION
	return 3 if project == "osu" else 2 if project == "spheres" else RULE_VERSION


func filtered(project: String, tag: String = "", rule_version: int = -1) -> Array[Dictionary]:
	if rule_version < 0:
		rule_version = current_rule_version(project)
	var out: Array[Dictionary] = []
	for record in records:
		if record.project == project and int(record.rule_version) == rule_version and (tag.is_empty() or record.tag == tag):
			out.append(record)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("session_timestamp_utc", a.timestamp_utc) < b.get("session_timestamp_utc", b.timestamp_utc))
	return out
