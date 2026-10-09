class_name SphereAim
extends Node3D

const Palette = preload("res://scripts/app_theme.gd")

const Camera3DConfig = preload("res://scripts/camera_3d_config.gd")
const PracticeRoom = preload("res://scripts/practice_room.gd")

@onready var camera: Camera3D = $Camera3D
@onready var targets_root: Node3D = $Targets

const YAW_MIN := -PI * 0.5
const YAW_MAX := PI * 0.5
const TARGET_COUNT := 6
const SPHERE_RADIUS := 0.42 # 1.2× prior 0.35
const HIT_RADIUS_SCALE := 1.1
const MIN_SEPARATION := SPHERE_RADIUS * 2.0 + 0.45
const SPREAD_FOV_DEG := 60.0
const GATE_Z := -8.0 # Same as Sens Lab's default distance.
const GATE_COLOR := Palette.SUCCESS

# Fixed world-space layouts; each set uses every layout once.
const LAYOUTS := [
	[Vector3(-3.5, 3.5, -10), Vector3(3.5, 3.5, -10), Vector3(-3.5, 0.7, -10), Vector3(3.5, 0.7, -10), Vector3(-1.2, 2.2, -12), Vector3(1.2, 4.5, -12)],
	[Vector3(-4, 4, -12), Vector3(2, 3, -10), Vector3(-2, 0.7, -10), Vector3(4, 0.7, -12), Vector3(-0.8, 3.5, -14), Vector3(1.2, 1.5, -14)],
	[Vector3(-2, 4.5, -12), Vector3(4, 3, -12), Vector3(-4, 0.7, -12), Vector3(2, 0.7, -10), Vector3(-1, 2, -10), Vector3(1, 3.2, -14)],
	[Vector3(-4, 2.5, -12), Vector3(4, 4.5, -12), Vector3(-2, 0.7, -12), Vector3(3.5, 0.7, -14), Vector3(-1, 4, -10), Vector3(1.2, 2, -10)],
	[Vector3(-3, 4.5, -14), Vector3(3, 4.5, -14), Vector3(-4, 0.7, -10), Vector3(4, 0.7, -10), Vector3(-1.5, 2.5, -10), Vector3(1.5, 1.8, -12)],
]

var active := false
var gate_active := false
var look_sensitivity := Camera3DConfig.LOOK_SENS_DEFAULT
var yaw := 0.0
var pitch := -0.05
var layout_order: Array = [0, 1, 2, 3, 4]
var layout_cursor := 0
var target_bodies: Array[StaticBody3D] = []
var alive: Array[bool] = []


func _ready() -> void:
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
		layout_order.shuffle()
		layout_cursor = 0
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func clear_targets() -> void:
	for child in targets_root.get_children():
		child.free()
	target_bodies.clear()
	alive.clear()
	gate_active = false


func spawn_gate() -> void:
	clear_targets()
	gate_active = true
	# Fixed world-center like SensLab, not camera-look relative.
	var pos := Vector3(0.0, camera.position.y, GATE_Z)
	if not PracticeRoom.contains_point(pos, SPHERE_RADIUS + 0.05):
		pos.y = clampf(pos.y, PracticeRoom.FLOOR_TOP + SPHERE_RADIUS + 0.15, PracticeRoom.CEILING_Y - SPHERE_RADIUS)
	var body := _make_sphere(pos, GATE_COLOR)
	targets_root.add_child(body)
	target_bodies.append(body)
	alive.append(true)


func spawn_targets() -> void:
	clear_targets()
	var positions: Array = LAYOUTS[layout_order[layout_cursor]]
	layout_cursor += 1
	for index in positions.size():
		var color := Palette.PRIMARY.lerp(Palette.SECONDARY, float(index) / 5.0)
		var body := _make_sphere(positions[index], color)
		targets_root.add_child(body)
		target_bodies.append(body)
		alive.append(true)


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
	if active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		var sens := Camera3DConfig.look_radians_per_pixel(look_sensitivity)
		yaw = clampf(yaw - event.relative.x * sens, YAW_MIN, YAW_MAX)
		pitch -= event.relative.y * sens
		_apply_camera_rotation()


func _apply_camera_rotation() -> void:
	camera.rotation = Vector3(pitch, yaw, 0.0)
