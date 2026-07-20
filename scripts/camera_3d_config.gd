extends RefCounted

# Overwatch-style: horizontal FOV at any aspect (KEEP_WIDTH).
# At 16:9 this is ~70.5° vertical.
const HORIZONTAL_FOV := 103.0
const BASE_LOOK_SENSITIVITY := 0.006
const LOOK_SENS_MIN := 0.10
const LOOK_SENS_MAX := 5.00
const LOOK_SENS_STEP := 0.05
const LOOK_SENS_DEFAULT := 1.0


static func apply(camera: Camera3D) -> void:
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = HORIZONTAL_FOV


static func clamp_look_sensitivity(value: float) -> float:
	return clampf(value, LOOK_SENS_MIN, LOOK_SENS_MAX)


static func look_radians_per_pixel(multiplier: float) -> float:
	return BASE_LOOK_SENSITIVITY * clamp_look_sensitivity(multiplier)
