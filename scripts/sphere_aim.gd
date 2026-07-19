class_name SphereAim
extends Node3D

@onready var camera: Camera3D = $Camera3D
@onready var targets_root: Node3D = $Targets

const YAW_MIN := -PI * 0.5
const YAW_MAX := PI * 0.5
const LOOK_SENSITIVITY := 0.006
const TARGET_COUNT := 6
const SPHERE_RADIUS := 0.35
const MIN_SEPARATION := 1.1

var active := false
var yaw := 0.0
var pitch := -0.05
var rng := RandomNumberGenerator.new()
var target_bodies: Array[StaticBody3D] = []
var alive: Array[bool] = []


func _ready() -> void:
	rng.randomize()
	_apply_camera_rotation()


func set_active(value: bool) -> void:
	active = value
	clear_targets()
	yaw = 0.0
	pitch = -0.05
	_apply_camera_rotation()
	camera.current = value
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE


func clear_targets() -> void:
	for child in targets_root.get_children():
		child.queue_free()
	target_bodies.clear()
	alive.clear()


func spawn_targets() -> void:
	clear_targets()
	var positions: Array[Vector3] = []
	var attempts := 0
	while positions.size() < TARGET_COUNT and attempts < 200:
		attempts += 1
		var pos := Vector3(
			rng.randf_range(-2.4, 2.4),
			rng.randf_range(-0.2, 1.6),
			rng.randf_range(-7.5, -4.5)
		)
		var ok := true
		for other in positions:
			if pos.distance_to(other) < MIN_SEPARATION:
				ok = false
				break
		if ok:
			positions.append(pos)
	for index in positions.size():
		var body := _make_sphere(positions[index], index)
		targets_root.add_child(body)
		target_bodies.append(body)
		alive.append(true)


func fire_ray() -> int:
	var space := camera.get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from + -camera.global_transform.basis.z * 40.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return -1
	var collider: Object = hit.collider
	for index in target_bodies.size():
		if alive[index] and target_bodies[index] == collider:
			_defeat(index)
			return index
	return -1


func _defeat(index: int) -> void:
	alive[index] = false
	var body := target_bodies[index]
	var mesh: MeshInstance3D = body.get_node("MeshInstance3D")
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.3, 0.33, 1.0)
	material.roughness = 0.9
	mesh.material_override = material
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
		yaw = clampf(yaw - event.relative.x * LOOK_SENSITIVITY, YAW_MIN, YAW_MAX)
		pitch -= event.relative.y * LOOK_SENSITIVITY
		_apply_camera_rotation()


func _apply_camera_rotation() -> void:
	camera.rotation = Vector3(pitch, yaw, 0.0)
