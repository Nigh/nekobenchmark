extends RefCounted

const Scores = preload("res://scripts/score_store.gd")
const History = preload("res://scripts/history_store.gd")
const VALID_US := 3_600_000_000
var entries := {}


func add(record: Dictionary, now_us: int) -> void:
	if History.valid_record(record):
		entries[record.project] = {"record": record.duplicate(true), "completed_us": now_us, "saved": false}


func latest(project: String) -> Dictionary:
	return entries.get(project, {})


func expired(entry: Dictionary, now_us: int) -> bool:
	return now_us - int(entry.completed_us) >= VALID_US


func displayed() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for project in Scores.PROJECTS:
		var entry := latest(project.key)
		if not entry.is_empty():
			results.append(entry.record.duplicate(true))
	return results


func selected(now_us: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for project in Scores.PROJECTS:
		var entry := latest(project.key)
		if not entry.is_empty() and not expired(entry, now_us) and not entry.saved:
			results.append(entry.record.duplicate(true))
	return results


func mark_saved() -> void:
	for entry in entries.values():
		entry.saved = true


func clear() -> void:
	entries.clear()
