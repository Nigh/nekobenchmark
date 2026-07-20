class_name SphereState
extends RefCounted

enum Stage { READY, GATE, AIMING, NEXT, INVALID, SUMMARY }

const TRIALS := 5
const TARGETS := 6
const TIMEOUT_US := 6_000_000
const FIRE_COOLDOWN_US := 150_000

var stage: Stage = Stage.READY
var target_frame_us := 0
var hits_remaining := TARGETS
var last_fire_us := -FIRE_COOLDOWN_US
var reactions_us: Array[int] = []


func reset() -> void:
	stage = Stage.READY
	target_frame_us = 0
	hits_remaining = TARGETS
	last_fire_us = -FIRE_COOLDOWN_US
	reactions_us.clear()


func start_gate() -> void:
	if stage != Stage.READY and stage != Stage.INVALID and stage != Stage.NEXT:
		return
	target_frame_us = 0
	hits_remaining = TARGETS
	last_fire_us = -FIRE_COOLDOWN_US
	stage = Stage.GATE


func begin_aiming(now_us: int) -> void:
	if stage != Stage.GATE:
		return
	target_frame_us = now_us
	hits_remaining = TARGETS
	stage = Stage.AIMING


func advance(now_us: int) -> bool:
	if stage == Stage.AIMING and now_us - target_frame_us >= TIMEOUT_US:
		invalidate()
		return true
	return false


## Returns true when a fire attempt was accepted (cooldown passed). Hit validity is separate.
func try_fire(now_us: int) -> bool:
	if stage != Stage.GATE and stage != Stage.AIMING:
		return false
	if now_us - last_fire_us < FIRE_COOLDOWN_US:
		return false
	last_fire_us = now_us
	return true


func register_hit(now_us: int) -> void:
	if stage != Stage.AIMING or hits_remaining <= 0:
		return
	hits_remaining -= 1
	if hits_remaining == 0:
		reactions_us.append(maxi(0, now_us - target_frame_us))
		stage = Stage.SUMMARY if reactions_us.size() == TRIALS else Stage.NEXT


func invalidate() -> void:
	reactions_us.clear()
	target_frame_us = 0
	hits_remaining = TARGETS
	last_fire_us = -FIRE_COOLDOWN_US
	stage = Stage.INVALID
