extends Control

const Scores = preload("res://scripts/score_store.gd")
const Palette = preload("res://scripts/app_theme.gd")
const NAMES := ["2D RT", "3D RT", "OSU", "3D AIM", "TRACKING"]
var values := {}
var caption := "LATEST RESULTS / -- MISSING"
var expired_projects: Array[String] = []


func set_results(results: Array[Dictionary]) -> void:
	values.clear()
	for result in results:
		values[result.project] = Scores.points(result.project, result.stats.median)
	queue_redraw()


func _draw() -> void:
	var font: Font = load("res://assets/MapleMono-Regular.ttf")
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.30
	var polygon := PackedVector2Array()
	for level in range(1, 6):
		var ring := PackedVector2Array()
		for index in 6:
			ring.append(center + Vector2.UP.rotated(TAU * (index % 5) / 5.0) * radius * level / 5.0)
		draw_polyline(ring, Palette.BORDER, 1.0, true)
	for index in 5:
		var mode: Dictionary = Scores.PROJECTS[index]
		var direction := Vector2.UP.rotated(TAU * index / 5.0)
		draw_line(center, center + direction * radius, Palette.BORDER, 1.0, true)
		var value := float(values.get(mode.key, 0.0))
		polygon.append(center + direction * radius * value / 100.0)
		var text := "%s %s" % [NAMES[index], "%.1f" % value if values.has(mode.key) else "--"]
		var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(font, center + direction * (radius + 28.0) - Vector2(extent.x * 0.5, -4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(Palette.PROJECT_COLORS[mode.key], 0.4 if mode.key in expired_projects else 1.0))
	if values.size() == 5:
		draw_colored_polygon(polygon, Color(Palette.INK, 0.10))
	polygon.append(polygon[0])
	draw_polyline(polygon, Palette.INK, 1.5, true)
	for index in 5:
		if values.has(Scores.PROJECTS[index].key):
			draw_circle(polygon[index], 3, Color(Palette.PROJECT_COLORS[Scores.PROJECTS[index].key], 0.4 if Scores.PROJECTS[index].key in expired_projects else 1.0))
	draw_string(font, Vector2(12, size.y - 8), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.MUTED)
