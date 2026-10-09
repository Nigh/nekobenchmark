extends Control

signal record_selected(record: Dictionary)
const Scores = preload("res://scripts/score_store.gd")
const Palette = preload("res://scripts/app_theme.gd")
const GROUP_WIDTH := 148.0
const BAR_WIDTH := 18.0
const BAR_GAP := 3.0
var groups: Array[Dictionary] = []
var selected_id := ""
var offset := 0.0
var bars: Array[Dictionary] = []
var dragging := false
var drag_distance := 0.0


func set_groups(values: Array[Dictionary]) -> void:
	groups = values.duplicate()
	selected_id = ""
	offset = maximum_offset()
	queue_redraw()


func maximum_offset() -> float:
	return maxf(0.0, groups.size() * GROUP_WIDTH - (size.x - 64.0))


func _draw() -> void:
	bars.clear()
	var font: Font = load("res://assets/MapleMono-Regular.ttf")
	var area := Rect2(64, 34, size.x - 64, size.y - 66)
	for index in 5:
		var mode: Dictionary = Scores.PROJECTS[index]
		draw_rect(Rect2(64 + index * 220, 4, 10, 10), Palette.PROJECT_COLORS[mode.key])
		draw_string(font, Vector2(80 + index * 220, 15), mode.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.PROJECT_COLORS[mode.key])
	for value in [0, 20, 40, 60, 80, 100]:
		var y: float = area.end.y - area.size.y * value / 100.0
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Palette.BORDER)
		draw_string(font, Vector2(4, y + 4), str(value), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.MUTED)
	if groups.is_empty():
		draw_string(font, Vector2(80, size.y * 0.5), "No saved results for this selection.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.MUTED)
		return
	for index in groups.size():
		var x := area.position.x + index * GROUP_WIDTH - offset + 10
		if x + GROUP_WIDTH < area.position.x or x > area.end.x:
			continue
		var group: Dictionary = groups[index]
		for result in group.results:
			var column := 0
			for mode_index in 5:
				if Scores.PROJECTS[mode_index].key == result.project:
					column = mode_index
			var points := Scores.points(result.project, result.stats.median)
			var rect := Rect2(x + column * (BAR_WIDTH + BAR_GAP), area.end.y - points / 100.0 * area.size.y, BAR_WIDTH, points / 100.0 * area.size.y)
			var visible_rect := rect.intersection(area)
			if points == 0.0 and rect.position.x >= area.position.x and rect.end.x <= area.end.x:
				draw_line(Vector2(rect.position.x, area.end.y), Vector2(rect.end.x, area.end.y), Palette.PROJECT_COLORS[result.project], 2)
			if visible_rect.has_area():
				draw_rect(visible_rect, Palette.PROJECT_COLORS[result.project])
				if result.id == selected_id:
					draw_rect(visible_rect, Palette.INK, false, 2)
			bars.append({"rect": Rect2(rect.position.x, area.position.y, BAR_WIDTH, area.size.y).intersection(area), "record": result})
		if x >= area.position.x and x + 105 < area.end.x:
			draw_string(font, Vector2(x, area.end.y + 17), group.local_time.substr(5, 11), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.MUTED)
	if maximum_offset() > 0.0:
		var width := maxf(24, area.size.x * area.size.x / (groups.size() * GROUP_WIDTH))
		draw_rect(Rect2(area.position.x, size.y - 5, area.size.x, 3), Palette.BORDER)
		draw_rect(Rect2(area.position.x + (area.size.x - width) * offset / maximum_offset(), size.y - 5, width, 3), Palette.MUTED)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT] and event.pressed:
			var direction := -1 if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1
			offset = clampf(offset + direction * GROUP_WIDTH, 0, maximum_offset())
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed:
				drag_distance = 0.0
			elif drag_distance < 5.0:
				for bar in bars:
					if bar.rect.has_point(event.position):
						selected_id = bar.record.id
						record_selected.emit(bar.record)
						queue_redraw()
						break
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		drag_distance += absf(event.relative.x)
		offset = clampf(offset - event.relative.x, 0, maximum_offset())
		queue_redraw()
		accept_event()
	elif event is InputEventPanGesture:
		offset = clampf(offset + event.delta.x * 30.0, 0, maximum_offset())
		queue_redraw()
		accept_event()
