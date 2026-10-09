extends Node3D

const Config = preload("res://scripts/camera_3d_config.gd")
const Room = preload("res://scripts/practice_room.gd")
const State = preload("res://scripts/tracking_state.gd")
const Palette = preload("res://scripts/app_theme.gd")

@onready var camera: Camera3D = $Camera3D
var target: MeshInstance3D
var active := false
var yaw := 0.0
var pitch := 0.0
var look_sensitivity := 1.0


func _ready() -> void:
	Room.build(self)
	Config.apply(camera)
	target = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * State.RADIUS * 2.0 * 1.12
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/tracking_target.gdshader")
	material.set_shader_parameter("outer_color", Palette.PRIMARY)
	material.set_shader_parameter("inner_color", Palette.WARNING)
	quad.material = material
	target.mesh = quad
	add_child(target)
	target.position = State.target_position(0, 0.0)
	target.look_at(camera.global_position, Vector3.UP, true)


func set_active(value: bool) -> void:
	active = value
	visible = value
	camera.current = value
	yaw = 0.0
	pitch = 0.0
	camera.rotation = Vector3.ZERO
	if value:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_look_sensitivity(value: float) -> void:
	look_sensitivity = Config.clamp_look_sensitivity(value)


func move_target(round_index: int, seconds: float) -> void:
	target.position = State.target_position(round_index, seconds, camera.position.y)
	target.look_at(camera.global_position, Vector3.UP, true)


func score_weight() -> float:
	return State.score_weight(camera.global_position, -camera.global_basis.z, target.global_position)


func set_feedback(scoring: bool, progress: float) -> void:
	var material: ShaderMaterial = target.mesh.material
	material.set_shader_parameter("scoring", scoring)
	material.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))


func error_degrees() -> float:
	return State.aim_error(camera.global_position, -camera.global_basis.z, target.global_position)


func _input(event: InputEvent) -> void:
	if active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		var sens := Config.look_radians_per_pixel(look_sensitivity)
		yaw = clampf(yaw - event.relative.x * sens, -PI * 0.5, PI * 0.5)
		pitch -= event.relative.y * sens
		camera.rotation = Vector3(pitch, yaw, 0.0)
