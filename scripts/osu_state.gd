class_name OsuState
extends RefCounted

enum Stage { READY, ACTIVE, NEXT, INVALID, SUMMARY }

const TRIALS := 5
const TARGETS := 6

var stage: Stage = Stage.READY
var expected := 1
var start_us := 0
var reactions_us: Array[int] = []


func reset() -> void:
	stage = Stage.READY
	expected = 1
	start_us = 0
	reactions_us.clear()


func begin_round() -> void:
	if stage == Stage.READY or stage == Stage.INVALID or stage == Stage.NEXT:
		expected = 1
		start_us = 0
		stage = Stage.ACTIVE


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
	stage = Stage.INVALID
