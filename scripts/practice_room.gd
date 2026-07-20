extends RefCounted

# Shared Overwatch-style practice room for all 3D modes.
const FLOOR_TOP := 0.0
const CEILING_Y := 8.0
const HALF_X := 12.0
const Z_BEHIND := 4.0
const Z_FRONT := -24.0
const WALL_THICK := 0.35
const FLOOR_THICK := 0.25
const TILE_SIZE := 3.0


static func contains_point(point: Vector3, margin: float = 0.0) -> bool:
	return (
		point.x >= -HALF_X + margin
		and point.x <= HALF_X - margin
		and point.y >= FLOOR_TOP + margin
		and point.y <= CEILING_Y - margin
		and point.z <= Z_BEHIND - margin
		and point.z >= Z_FRONT + margin
	)


static func grid_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/practice_grid.gdshader")
	mat.set_shader_parameter("base_color", Color(0.62, 0.63, 0.65))
	mat.set_shader_parameter("line_color", Color(0.50, 0.51, 0.54))
	mat.set_shader_parameter("tile_size", TILE_SIZE)
	mat.set_shader_parameter("line_width", 0.045)
	mat.set_shader_parameter("fade_start", 10.0)
	mat.set_shader_parameter("fade_end", 26.0)
	mat.set_shader_parameter("roughness_val", 0.92)
	return mat


static func build(parent: Node3D) -> void:
	var existing := parent.get_node_or_null("PracticeRoom")
	if existing:
		existing.free()
	var root := Node3D.new()
	root.name = "PracticeRoom"
	parent.add_child(root)
	parent.move_child(root, 0)

	var mat := grid_material()
	var depth := Z_BEHIND - Z_FRONT
	var mid_z := (Z_BEHIND + Z_FRONT) * 0.5
	var height := CEILING_Y - FLOOR_TOP
	var mid_y := FLOOR_TOP + height * 0.5

	_add_box(root, mat, Vector3(0.0, FLOOR_TOP - FLOOR_THICK * 0.5, mid_z), Vector3(HALF_X * 2.0, FLOOR_THICK, depth))
	_add_box(root, mat, Vector3(0.0, CEILING_Y + FLOOR_THICK * 0.5, mid_z), Vector3(HALF_X * 2.0, FLOOR_THICK, depth))
	_add_box(root, mat, Vector3(-HALF_X - WALL_THICK * 0.5, mid_y, mid_z), Vector3(WALL_THICK, height, depth))
	_add_box(root, mat, Vector3(HALF_X + WALL_THICK * 0.5, mid_y, mid_z), Vector3(WALL_THICK, height, depth))
	_add_box(root, mat, Vector3(0.0, mid_y, Z_FRONT - WALL_THICK * 0.5), Vector3(HALF_X * 2.0, height, WALL_THICK))
	_add_box(root, mat, Vector3(0.0, mid_y, Z_BEHIND + WALL_THICK * 0.5), Vector3(HALF_X * 2.0, height, WALL_THICK))

	if parent.get_node_or_null("WorldEnvironment") == null:
		var env_node := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.45, 0.46, 0.48)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.72, 0.73, 0.75)
		env.ambient_light_energy = 0.7
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.fog_enabled = true
		env.fog_light_color = Color(0.58, 0.59, 0.61)
		env.fog_density = 0.012
		env.fog_aerial_perspective = 0.35
		env_node.environment = env
		root.add_child(env_node)


static func _add_box(parent: Node3D, material: Material, position: Vector3, size: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.position = position
	parent.add_child(mesh_instance)
