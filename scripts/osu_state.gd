class_name OsuState
extends RefCounted

enum Stage { READY, GATE, WAITING, ACTIVE, NEXT, INVALID, SUMMARY }

const TRIALS := 5
const TARGETS := 6
const WAIT_MIN_US := 1_000_000
const WAIT_MAX_US := 3_000_000

var stage: Stage = Stage.READY
var expected := 1
var start_us := 0
var deadline_us := 0
var reactions_us: Array[int] = []


func reset() -> void:
	stage = Stage.READY
	expected = 1
	start_us = 0
	deadline_us = 0
	reactions_us.clear()


func start_gate() -> void:
	if stage != Stage.READY and stage != Stage.INVALID and stage != Stage.NEXT:
		return
	expected = 1
	start_us = 0
	deadline_us = 0
	stage = Stage.GATE


func begin_wait(now_us: int, rng: RandomNumberGenerator) -> void:
	if stage != Stage.GATE:
		return
	deadline_us = now_us + rng.randi_range(WAIT_MIN_US, WAIT_MAX_US)
	expected = 1
	start_us = 0
	stage = Stage.WAITING


func advance(now_us: int) -> bool:
	if stage == Stage.WAITING and now_us >= deadline_us:
		expected = 1
		start_us = 0
		stage = Stage.ACTIVE
		return true
	return false


func early_input() -> void:
	if stage == Stage.WAITING:
		invalidate()


func hit_next(now_us: int) -> void:
	if stage != Stage.ACTIVE:
		return
	if expected == 1:
		start_us = now_us
	if expected == TARGETS:
		reactions_us.append(maxi(0, now_us - start_us))
		stage = Stage.SUMMARY if reactions_us.size() == TRIALS else Stage.NEXT
		return
	expected += 1


func miss() -> void:
	if stage == Stage.ACTIVE:
		invalidate()


func invalidate() -> void:
	reactions_us.clear()
	expected = 1
	start_us = 0
	deadline_us = 0
	stage = Stage.INVALID
