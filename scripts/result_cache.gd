extends RefCounted

const Scores = preload("res://scripts/score_store.gd")
const History = preload("res://scripts/history_store.gd")
const VALID_US := 3_600_000_000
var candidates := {}


func prune(now_us: int) -> bool:
	var expired := false
	for project in candidates:
		var queue: Array = candidates[project]
		while not queue.is_empty() and now_us - int(queue[0].completed_us) >= VALID_US:
			queue.pop_front()
			expired = true
	return expired


func add(record: Dictionary, now_us: int) -> void:
	if not History.valid_record(record):
		return
	prune(now_us)
	var project: String = record.project
	if not candidates.has(project):
		candidates[project] = []
	var queue: Array = candidates[project]
	# A newer equal/better result outlives every older result it replaces.
	while not queue.is_empty():
		var previous: float = queue[-1].record.stats.median
		var better: bool = record.stats.median >= previous if project == "tracking" else record.stats.median <= previous
		if not better:
			break
		queue.pop_back()
	queue.append({"record": record.duplicate(true), "completed_us": now_us})


func best(project: String) -> Dictionary:
	var queue: Array = candidates.get(project, [])
	return {} if queue.is_empty() else queue[0]


func selected(now_us: int) -> Array[Dictionary]:
	prune(now_us)
	var results: Array[Dictionary] = []
	for project in Scores.PROJECTS:
		var entry := best(project.key)
		if not entry.is_empty():
			results.append(entry.record.duplicate(true))
	return results


func clear() -> void:
	candidates.clear()
