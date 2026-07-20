class_name SensLab
extends Node3D

const Camera3DConfig = preload("res://scripts/camera_3d_config.gd")
const PracticeRoom = preload("res://scripts/practice_room.gd")

@onready var camera: Camera3D = $Camera3D
@onready var targets_root: Node3D = $Targets

const YAW_MIN := -PI * 0.5
const YAW_MAX := PI * 0.5
const TARGET_COUNT := 4
const SPHERE_RADIUS := 0.35
const HIT_RADIUS_SCALE := 1.1
const TARGET_Z := -8.0
const SPACING_STEP := 0.08
const FOV_LIMIT_DEG := 90.0

var active := false
var cursor_mode := false
var look_sensitivity := Camera3DConfig.LOOK_SENS_DEFAULT
var yaw := 0.0
var pitch := -0.05
var square_half := 1.5
var target_bodies: Array[StaticBody3D] = []
var alive: Array[bool] = []
var gate_active := false


func _ready() -> void:
	PracticeRoom.build(self)
	Camera3DConfig.apply(camera)
	square_half = clampf(square_half, min_square_half(), max_square_half())
	_apply_camera_rotation()


func set_look_sensitivity(value: float) -> void:
	look_sensitivity = Camera3DConfig.clamp_look_sensitivity(value)


func set_active(value: bool) -> void:
	active = value
	visible = value
	cursor_mode = false
	gate_active = false
	clear_targets()
	yaw = 0.0
	pitch = -0.05
	_apply_camera_rotation()
	camera.current = value
	if value:
		spawn_targets()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_cursor_mode(enabled: bool) -> void:
	if not active:
		return
	cursor_mode = enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if enabled else Input.MOUSE_MODE_CAPTURED


func min_square_half() -> float:
	return SPHERE_RADIUS


func max_square_half() -> float:
	var depth := absf(TARGET_Z - camera.position.z)
	var half_fov := deg_to_rad(FOV_LIMIT_DEG * 0.5)
	var by_fov := (depth * tan(half_fov)) / sqrt(2.0)
	# Raise the square instead of capping by the floor; ceiling still limits size.
	var by_ceiling := (PracticeRoom.CEILING_Y - PracticeRoom.FLOOR_TOP - SPHERE_RADIUS * 2.0) * 0.5
	return maxf(min_square_half(), minf(by_fov, by_ceiling))


func square_center_y() -> float:
	# Lift the whole square when spacing would push the bottom spheres into the floor.
	var min_center := PracticeRoom.FLOOR_TOP + SPHERE_RADIUS + square_half
	return maxf(camera.position.y, min_center)


func nudge_spacing(delta: float) -> float:
	square_half = clampf(square_half + delta, min_square_half(), max_square_half())
	if not gate_active and target_bodies.size() == TARGET_COUNT:
		_reposition_square()
	return square_half * 2.0


func spacing_side() -> float:
	return square_half * 2.0


func clear_targets() -> void:
	for child in targets_root.get_children():
		child.free()
	target_bodies.clear()
	alive.clear()
	gate_active = false


func spawn_targets() -> void:
	clear_targets()
	square_half = clampf(square_half, min_square_half(), max_square_half())
	for index in TARGET_COUNT:
		var body := _make_sphere(_square_offset(index), Color(0.74, 0.2 + index * 0.08, 0.16, 1.0))
		targets_root.add_child(body)
		target_bodies.append(body)
		alive.append(true)


func spawn_gate() -> void:
	clear_targets()
	gate_active = true
	var body := _make_sphere(Vector3(0.0, square_center_y(), TARGET_Z), Color(0.22, 0.82, 0.38, 1.0))
	targets_root.add_child(body)
	target_bodies.append(body)
	alive.append(true)


func alive_count() -> int:
	var count := 0
	for flag in alive:
		if flag:
			count += 1
	return count


func fire_ray() -> int:
	if cursor_mode:
		return -1
	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var hit_r := SPHERE_RADIUS * HIT_RADIUS_SCALE
	var hit_r2 := hit_r * hit_r
	var best_index := -1
	var best_depth := INF
	for index in target_bodies.size():
		if not alive[index]:
			continue
		var center: Vector3 = target_bodies[index].global_position
		var to_center := center - origin
		var depth := to_center.dot(forward)
		if depth < 0.0 or depth >= best_depth:
			continue
		var closest := origin + forward * depth
		if closest.distance_squared_to(center) <= hit_r2:
			best_depth = depth
			best_index = index
	if best_index < 0:
		return -1
	_defeat(best_index)
	if alive_count() == 0:
		if gate_active:
			spawn_targets()
		else:
			spawn_gate()
	return best_index


func _square_offset(index: int) -> Vector3:
	var cy := square_center_y()
	var sx := -square_half if index % 2 == 0 else square_half
	var sy := square_half if index < 2 else -square_half
	return Vector3(sx, cy + sy, TARGET_Z)


func _reposition_square() -> void:
	for index in target_bodies.size():
		if index >= TARGET_COUNT:
			break
		target_bodies[index].position = _square_offset(index)


func _defeat(index: int) -> void:
	alive[index] = false
	var body := target_bodies[index]
	body.visible = false
	body.collision_layer = 0


func _make_sphere(position: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	var sphere := SphereMesh.new()
	sphere.radius = SPHERE_RADIUS
	sphere.height = SPHERE_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	sphere.material = material
	mesh_instance.mesh = sphere
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = SPHERE_RADIUS
	collision.shape = shape
	body.add_child(collision)
	return body


func _input(event: InputEvent) -> void:
	if active and not cursor_mode and event is InputEventMouseMotion:
		var sens := Camera3DConfig.look_radians_per_pixel(look_sensitivity)
		yaw = clampf(yaw - event.relative.x * sens, YAW_MIN, YAW_MAX)
		pitch -= event.relative.y * sens
		_apply_camera_rotation()


func _apply_camera_rotation() -> void:
	camera.rotation = Vector3(pitch, yaw, 0.0)
