extends RefCounted

enum Stage { READY, PREPARING, ACTIVE, SUMMARY, INVALID }
const PREP_US := 3_000_000
const ROUND_US := 10_000_000
const HZ_X := [0.12, 0.15, 0.18, 0.16, 0.20]
const HZ_Y := [0.18, 0.12, 0.14, 0.23, 0.17]
const RADIUS := 0.42

var stage := Stage.READY
var deadline_us := 0
var start_us := 0
var last_us := 0
var covered_us := 0
var error_degree_us := 0.0
var coverage: Array[float] = []
var errors: Array[float] = []


func reset() -> void:
	stage = Stage.READY
	coverage.clear()
	errors.clear()
	covered_us = 0
	error_degree_us = 0.0
	start_us = 0
	last_us = 0
	deadline_us = 0


func prepare(now_us: int) -> void:
	stage = Stage.PREPARING
	deadline_us = now_us + PREP_US
	covered_us = 0
	error_degree_us = 0.0


func advance(now_us: int, covered: bool, error_degrees: float) -> bool:
	if stage == Stage.PREPARING and now_us >= deadline_us:
		stage = Stage.ACTIVE
		start_us = now_us
		last_us = now_us
		return false
	if stage != Stage.ACTIVE:
		return false
	var end_us := mini(now_us, start_us + ROUND_US)
	var duration := maxi(0, end_us - last_us)
	# ponytail: elapsed-time weighting of render samples; fixed-rate sampling if frame jitter dominates comparisons.
	if covered:
		covered_us += duration
	error_degree_us += clampf(error_degrees, 0.0, 180.0) * duration
	last_us = end_us
	if end_us < start_us + ROUND_US:
		return false
	coverage.append(100.0 * covered_us / ROUND_US)
	errors.append(error_degree_us / ROUND_US)
	if coverage.size() == 5:
		stage = Stage.SUMMARY
	else:
		prepare(now_us)
	return true


static func target_position(round_index: int, seconds: float, height: float = 1.4) -> Vector3:
	var index := clampi(round_index, 0, 4)
	var horizontal := deg_to_rad(22.0) * sin(TAU * HZ_X[index] * seconds)
	var vertical := deg_to_rad(6.0) * sin(TAU * HZ_Y[index] * seconds)
	return Vector3(8.0 * tan(horizontal), height + 8.0 * tan(vertical), -8.0)


static func aim_error(origin: Vector3, forward: Vector3, target: Vector3) -> float:
	return rad_to_deg(forward.angle_to(target - origin))


static func is_covered(origin: Vector3, forward: Vector3, target: Vector3) -> bool:
	var offset := target - origin
	var along := offset.dot(forward.normalized())
	return along > 0.0 and (offset - forward.normalized() * along).length_squared() <= RADIUS * RADIUS
