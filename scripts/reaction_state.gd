class_name ReactionState
extends RefCounted

enum Stage { READY, WAITING, TARGET, NEXT, INVALID, SUMMARY }

const TRIALS := 5
const WAIT_MIN_US := 1_000_000
const WAIT_MAX_US := 4_000_000
const TIMEOUT_US := 1_000_000

var stage: Stage = Stage.READY
var deadline_us := 0
var target_frame_us := 0
var reactions_us: Array[int] = []


func reset() -> void:
	stage = Stage.READY
	deadline_us = 0
	target_frame_us = 0
	reactions_us.clear()


func start_wait(now_us: int, rng: RandomNumberGenerator) -> void:
	deadline_us = now_us + rng.randi_range(WAIT_MIN_US, WAIT_MAX_US)
	target_frame_us = 0
	stage = Stage.WAITING


func advance(now_us: int) -> bool:
	if stage == Stage.WAITING and now_us >= deadline_us:
		target_frame_us = now_us
		stage = Stage.TARGET
		return true
	if stage == Stage.TARGET and now_us - target_frame_us >= TIMEOUT_US:
		invalidate()
		return true
	return false


func respond(now_us: int, valid: bool = true) -> void:
	if stage == Stage.WAITING:
		invalidate()
	elif stage == Stage.TARGET:
		if not valid:
			invalidate()
		else:
			reactions_us.append(maxi(0, now_us - target_frame_us))
			stage = Stage.SUMMARY if reactions_us.size() == TRIALS else Stage.NEXT


func activate(now_us: int, rng: RandomNumberGenerator) -> void:
	if stage == Stage.READY or stage == Stage.INVALID or stage == Stage.NEXT:
		start_wait(now_us, rng)


func invalidate() -> void:
	reactions_us.clear()
	stage = Stage.INVALID


func target_progress(now_us: int) -> float:
	if stage != Stage.TARGET:
		return 0.0
	return minf(1.0, float(now_us - target_frame_us) / TIMEOUT_US)
