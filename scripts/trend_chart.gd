extends Control

signal record_selected(record: Dictionary)
const Palette = preload("res://scripts/app_theme.gd")
var records: Array[Dictionary] = []
var points: PackedVector2Array = []
var unit := "ms"
var compact := false
var selected_id := ""


func set_records(values: Array[Dictionary], tracking: bool = false) -> void:
	records = values.duplicate()
	unit = "%" if tracking else "ms"
	selected_id = ""
	queue_redraw()


func _draw() -> void:
	points.clear()
	var font: Font = load("res://assets/MapleMono-Regular.ttf")
	var area := Rect2(8, 8, maxf(1, size.x - 16), maxf(1, size.y - 16)) if compact else Rect2(100, 26, maxf(1, size.x - 124), maxf(1, size.y - 72))
	if records.is_empty() or (compact and records.size() < 2):
		draw_string(font, Vector2(12, size.y * 0.55), "NO SAVED TREND" if compact else "No saved results for this selection.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11 if compact else 16, Palette.MUTED)
		return
	var low := float(records[0].stats.median)
	var high := low
	for record in records:
		low = minf(low, record.stats.median)
		high = maxf(high, record.stats.median)
	var padding := maxf(1.0, (high - low) * 0.15)
	low = maxf(0.0, low - padding)
	high += padding
	if unit == "%":
		low = maxf(0.0, low)
		high = minf(100.0, high)
	if not compact:
		for step in 3:
			var fraction := float(step) / 2.0
			var y := area.position.y + area.size.y * fraction
			draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Palette.BORDER, 1)
			draw_string(font, Vector2(4, y + 5), "%.1f %s" % [lerpf(high, low, fraction), unit], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.MUTED)
	var first := float(records[0].timestamp_utc)
	var last := float(records[-1].timestamp_utc)
	for index in records.size():
		var fraction := 0.5 if last == first else (float(records[index].timestamp_utc) - first) / (last - first)
		var y := 1.0 - (float(records[index].stats.median) - low) / maxf(0.0001, high - low)
		points.append(area.position + Vector2(fraction * area.size.x, y * area.size.y))
	if points.size() > 1:
		draw_polyline(points, Palette.ACCENT, 2, true)
	for index in points.size():
		draw_circle(points[index], 5 if records[index].id == selected_id else 3, Palette.PRIMARY)
	if not compact:
		draw_string(font, Vector2(area.position.x, size.y - 10), records[0].local_time, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.MUTED)
		var text: String = records[-1].local_time
		if records.size() > 1:
			draw_string(font, Vector2(area.end.x - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, size.y - 10), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.MUTED)


func _gui_input(event: InputEvent) -> void:
	if compact or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var nearest := -1
	var distance := 16.0
	for index in points.size():
		var candidate: float = event.position.distance_to(points[index])
		if candidate < distance:
			distance = candidate
			nearest = index
	if nearest >= 0:
		selected_id = records[nearest].id
		queue_redraw()
		record_selected.emit(records[nearest])
		accept_event()
