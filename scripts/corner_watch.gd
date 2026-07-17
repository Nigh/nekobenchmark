class_name CornerWatch
extends Node3D

@onready var camera: Camera3D = $Camera3D
@onready var enemy: Node3D = $Enemy
@onready var enemy_mesh: MeshInstance3D = $Enemy/MeshInstance3D

const COVER_X := 2.0
const ENEMY_Y := 0.1
const YAW_MIN := -PI * 0.5
const YAW_MAX := PI * 0.5
const LOOK_SENSITIVITY := 0.006
const DEFEAT_DURATION := 0.45

var active := false
var yaw := -0.22
var pitch := -0.02
var defeat_elapsed := -1.0
var defeat_material: StandardMaterial3D
var source_x := -COVER_X
var destination_x := COVER_X


func _ready() -> void:
	defeat_material = StandardMaterial3D.new()
	defeat_material.albedo_color = Color(0.28, 0.3, 0.33, 1.0)
	defeat_material.roughness = 0.9
	defeat_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	enemy.visible = false
	_apply_camera_rotation()


func set_active(value: bool) -> void:
	active = value
	defeat_elapsed = -1.0
	enemy.visible = false
	yaw = -0.22
	pitch = -0.02
	_apply_camera_rotation()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE


func begin_target(from_left: bool) -> void:
	defeat_elapsed = -1.0
	source_x = -COVER_X if from_left else COVER_X
	destination_x = COVER_X if from_left else -COVER_X
	enemy.visible = true
	enemy.position.x = source_x
	enemy.position.y = ENEMY_Y
	enemy.rotation = Vector3.ZERO
	enemy_mesh.material_override = null
	enemy_mesh.transparency = 0.0


func show_target(progress: float) -> void:
	enemy.position.x = lerpf(source_x, destination_x, progress)


func hide_target() -> void:
	defeat_elapsed = -1.0
	enemy.visible = false


func defeat_target() -> void:
	if enemy.visible and defeat_elapsed < 0.0:
		defeat_elapsed = 0.0
		enemy_mesh.material_override = defeat_material


func _process(delta: float) -> void:
	if defeat_elapsed < 0.0:
		return
	defeat_elapsed += delta
	var progress := minf(1.0, defeat_elapsed / DEFEAT_DURATION)
	enemy.rotation.z = lerpf(0.0, deg_to_rad(78.0), progress)
	enemy.position.y = lerpf(ENEMY_Y, -0.8, progress)
	enemy_mesh.transparency = progress
	if progress == 1.0:
		hide_target()


func _input(event: InputEvent) -> void:
	if active and event is InputEventMouseMotion:
		yaw = clampf(yaw - event.relative.x * LOOK_SENSITIVITY, YAW_MIN, YAW_MAX)
		pitch -= event.relative.y * LOOK_SENSITIVITY
		_apply_camera_rotation()


func target_is_visible() -> bool:
	return enemy.visible and camera.is_position_in_frustum(enemy.global_position)


func _apply_camera_rotation() -> void:
	camera.rotation = Vector3(pitch, yaw, 0.0)
