extends RefCounted

enum Stage { READY, PREPARING, ACTIVE, SUMMARY, INVALID }
const ACQUIRE_US := 1_000_000
const ROUND_US := 10_000_000
const LOOP_SECONDS := 10.0
const HZ_X := [0.5, 0.6, 0.7, 0.6, 0.8]
const HZ_Y := [0.7, 0.5, 0.6, 0.9, 0.7]
const RADIUS := 0.42
const INNER_RADIUS := 0.21
const PREP_MAX_SPEED := 20.0 # Degrees per second.

var path_order: Array = [0, 1, 2, 3, 4]
var stage := Stage.READY
var motion_start_us := 0
var acquired_us := 0
var was_covered := false
var start_us := 0
var last_us := 0
var covered_us := 0.0
var error_degree_us := 0.0
var coverage: Array[float] = []
var errors: Array[float] = []


func reset() -> void:
	stage = Stage.READY
	path_order.shuffle()
	coverage.clear()
	errors.clear()
	covered_us = 0.0
	error_degree_us = 0.0
	start_us = 0
	last_us = 0
	motion_start_us = 0
	acquired_us = 0
	was_covered = false


func prepare(now_us: int) -> void:
	stage = Stage.PREPARING
	motion_start_us = now_us
	last_us = now_us
	acquired_us = 0
	was_covered = false
	covered_us = 0.0
	error_degree_us = 0.0


func advance(now_us: int, weight: float, error_degrees: float) -> bool:
	if now_us < last_us:
		return false
	if stage == Stage.PREPARING:
		# shortcut: continuous coverage inferred from render samples; use fixed-rate sampling if frame jitter dominates comparisons.
		acquired_us = acquired_us + now_us - last_us if weight > 0.0 and was_covered else 0
		was_covered = weight > 0.0
		last_us = now_us
		if acquired_us >= ACQUIRE_US:
			stage = Stage.ACTIVE
			start_us = now_us
		return false
	if stage != Stage.ACTIVE:
		return false
	var end_us := mini(now_us, start_us + ROUND_US)
	var duration := maxi(0, end_us - last_us)
	covered_us += clampf(weight, 0.0, 1.0) * duration
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
	var t := fposmod(seconds, LOOP_SECONDS)
	var phase := t + 0.55 / (TAU * 0.2) * sin(TAU * 0.2 * t)
	var horizontal := deg_to_rad(22.0) * sin(TAU * HZ_X[index] * phase)
	var vertical := deg_to_rad(6.0) * sin(TAU * HZ_Y[index] * phase)
	return Vector3(8.0 * tan(horizontal), height + 8.0 * tan(vertical), -8.0)


func path_index() -> int:
	return path_order[clampi(coverage.size(), 0, 4)]


func preparation_speed() -> float:
	var index := path_index()
	var maximum := 1.55 * TAU * Vector2(22.0 * HZ_X[index], 6.0 * HZ_Y[index]).length()
	return minf(1.0, PREP_MAX_SPEED / maximum)


func movement_seconds(now_us: int) -> float:
	var slow := preparation_speed()
	if stage != Stage.ACTIVE:
		return maxf(0.0, (now_us - motion_start_us) / 1_000_000.0) * slow
	var elapsed := maxf(0.0, (now_us - start_us) / 1_000_000.0)
	var ramp := minf(elapsed, 1.0)
	return (start_us - motion_start_us) / 1_000_000.0 * slow + slow * elapsed + (1.0 - slow) * (0.5 * ramp * ramp + maxf(0.0, elapsed - 1.0))


static func aim_error(origin: Vector3, forward: Vector3, target: Vector3) -> float:
	return rad_to_deg(forward.angle_to(target - origin))


static func score_weight(origin: Vector3, forward: Vector3, target: Vector3) -> float:
	# Intersect the same camera-facing plane used by the concentric target mesh.
	var normal := (origin - target).normalized()
	var direction := forward.normalized()
	var denominator := direction.dot(normal)
	if denominator >= -0.000001:
		return 0.0
	var depth := (target - origin).dot(normal) / denominator
	if depth <= 0.0:
		return 0.0
	var distance_squared := (origin + direction * depth).distance_squared_to(target)
	if distance_squared <= INNER_RADIUS * INNER_RADIUS + 0.0000001:
		return 1.0
	return 0.5 if distance_squared <= RADIUS * RADIUS + 0.0000001 else 0.0
