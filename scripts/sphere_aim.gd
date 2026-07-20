class_name SphereAim
extends Node3D

const Camera3DConfig = preload("res://scripts/camera_3d_config.gd")
const PracticeRoom = preload("res://scripts/practice_room.gd")

@onready var camera: Camera3D = $Camera3D
@onready var targets_root: Node3D = $Targets

const YAW_MIN := -PI * 0.5
const YAW_MAX := PI * 0.5
const TARGET_COUNT := 6
const SPHERE_RADIUS := 0.35
const HIT_RADIUS_SCALE := 1.1
const MIN_SEPARATION := SPHERE_RADIUS * 2.0 + 0.45
const SPREAD_FOV_DEG := 60.0
const DEPTH_MIN := 8.0
const DEPTH_MAX := 16.0

var active := false
var look_sensitivity := Camera3DConfig.LOOK_SENS_DEFAULT
var yaw := 0.0
var pitch := -0.05
var rng := RandomNumberGenerator.new()
var target_bodies: Array[StaticBody3D] = []
var alive: Array[bool] = []


func _ready() -> void:
	rng.randomize()
	PracticeRoom.build(self)
	Camera3DConfig.apply(camera)
	_apply_camera_rotation()


func set_look_sensitivity(value: float) -> void:
	look_sensitivity = Camera3DConfig.clamp_look_sensitivity(value)


func set_active(value: bool) -> void:
	active = value
	visible = value
	clear_targets()
	yaw = 0.0
	pitch = -0.05
	_apply_camera_rotation()
	camera.current = value
	if value:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func clear_targets() -> void:
	for child in targets_root.get_children():
		child.free()
	target_bodies.clear()
	alive.clear()


func spawn_targets() -> void:
	clear_targets()
	var positions: Array[Vector3] = []
	var attempts := 0
	var half := deg_to_rad(SPREAD_FOV_DEG * 0.5)
	while positions.size() < TARGET_COUNT and attempts < 1600:
		attempts += 1
		var ax := rng.randf_range(-half, half)
		# Bias upward so balls stay above the floor inside the room.
		var ay := rng.randf_range(-half * 0.35, half)
		if sqrt(ax * ax + ay * ay) > half:
			continue
		var depth := rng.randf_range(DEPTH_MIN, DEPTH_MAX)
		var pos := _world_from_view(ax, ay, depth)
		if _valid_target(positions, pos):
			positions.append(pos)
	if positions.size() < TARGET_COUNT:
		positions.clear()
		for index in TARGET_COUNT:
			var col: int = index % 3
			var row: int = int(index / 3)
			var ax := lerpf(-half * 0.75, half * 0.75, float(col) / 2.0)
			var ay := lerpf(-half * 0.15, half * 0.65, float(row))
			var depth := lerpf(DEPTH_MIN + 1.0, DEPTH_MAX - 1.0, float(index) / float(TARGET_COUNT - 1))
			var pos := _world_from_view(ax, ay, depth)
			if not PracticeRoom.contains_point(pos, SPHERE_RADIUS + 0.05):
				pos.y = clampf(pos.y, PracticeRoom.FLOOR_TOP + SPHERE_RADIUS + 0.15, PracticeRoom.CEILING_Y - SPHERE_RADIUS)
				pos.x = clampf(pos.x, -PracticeRoom.HALF_X + SPHERE_RADIUS, PracticeRoom.HALF_X - SPHERE_RADIUS)
				pos.z = clampf(pos.z, PracticeRoom.Z_FRONT + SPHERE_RADIUS, -DEPTH_MIN)
			positions.append(pos)
	for index in positions.size():
		var body := _make_sphere(positions[index], index)
		targets_root.add_child(body)
		target_bodies.append(body)
		alive.append(true)


func _world_from_view(yaw_rad: float, pitch_rad: float, depth: float) -> Vector3:
	var local := Vector3(sin(yaw_rad) * cos(pitch_rad), sin(pitch_rad), -cos(yaw_rad) * cos(pitch_rad)).normalized()
	return camera.global_position + camera.global_transform.basis * local * depth


func _valid_target(existing: Array[Vector3], pos: Vector3) -> bool:
	if not PracticeRoom.contains_point(pos, SPHERE_RADIUS + 0.1):
		return false
	for other in existing:
		if pos.distance_to(other) < MIN_SEPARATION:
			return false
	return true


func fire_ray() -> int:
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
	if best_index >= 0:
		_defeat(best_index)
	return best_index


func _defeat(index: int) -> void:
	alive[index] = false
	var body := target_bodies[index]
	body.visible = false
	body.collision_layer = 0


func _make_sphere(position: Vector3, index: int) -> StaticBody3D:
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
	material.albedo_color = Color(0.74, 0.2 + index * 0.05, 0.16, 1.0)
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
	if active and event is InputEventMouseMotion:
		var sens := Camera3DConfig.look_radians_per_pixel(look_sensitivity)
		yaw = clampf(yaw - event.relative.x * sens, YAW_MIN, YAW_MAX)
		pitch -= event.relative.y * sens
		_apply_camera_rotation()


func _apply_camera_rotation() -> void:
	camera.rotation = Vector3(pitch, yaw, 0.0)
