extends Control

signal back_requested
const Scores = preload("res://scripts/score_store.gd")
const Chart = preload("res://scripts/trend_chart.gd")
const Radar = preload("res://scripts/result_radar.gd")
const Palette = preload("res://scripts/app_theme.gd")
var store
var chart
var radar
var list: ItemList
var detail: Label
var detail_meta: Label
var detail_rows: Array[Label] = []
var detail_scores: Array[Label] = []
var detail_rules: Array[Label] = []
var heading: Label
var page_label: Label
var previous: Button
var next: Button
var tooltip: PanelContainer
var tooltip_label: Label
var filtered: Array[Dictionary] = []
var shown: Array[Dictionary] = []
var page_index := 0


func setup(history) -> void:
	store = history
	theme = Palette.create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Palette.BASE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_add_label("HISTORY", Vector2(40, 30), Vector2(600, 46), 30)
	var back := _button("Menu", Vector2(1100, 30), Vector2(140, 44))
	back.pressed.connect(func() -> void: back_requested.emit())
	heading = _add_label("", Vector2(40, 86), Vector2(1200, 28), 14)
	chart = Chart.new()
	chart.position = Vector2(40, 122)
	chart.size = Vector2(1200, 250)
	chart.clip_contents = true
	chart.group_selected.connect(_show_group)
	chart.record_hovered.connect(_show_tooltip)
	add_child(chart)
	list = ItemList.new()
	list.add_theme_font_size_override("font_size", 13)
	list.position = Vector2(40, 394)
	list.size = Vector2(540, 252)
	list.item_selected.connect(func(index: int) -> void: _show_group(shown[index]))
	add_child(list)
	detail = _add_label("Select a session", Vector2(604, 394), Vector2(336, 32), 23)
	detail_meta = _add_label("to see all five tests.", Vector2(604, 430), Vector2(336, 40), 12)
	detail_meta.add_theme_color_override("font_color", Palette.MUTED)
	detail_meta.mouse_filter = Control.MOUSE_FILTER_PASS
	detail_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for index in Scores.PROJECTS.size():
		var mode: Dictionary = Scores.PROJECTS[index]
		var y := 478 + index * 36
		var name_label := _add_label(mode.name, Vector2(604, y), Vector2(166, 20), 14)
		name_label.add_theme_color_override("font_color", Palette.PROJECT_COLORS[mode.key])
		var score := _add_label("--", Vector2(770, y), Vector2(158, 20), 18)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var rules := _add_label("", Vector2(604, y + 20), Vector2(336, 16), 12)
		rules.add_theme_color_override("font_color", Palette.MUTED)
		detail_rows.append(name_label)
		detail_scores.append(score)
		detail_rules.append(rules)
	radar = Radar.new()
	radar.position = Vector2(952, 388)
	radar.size = Vector2(288, 270)
	radar.caption = "SELECTED SESSION / -- MISSING"
	add_child(radar)
	previous = _button("Previous", Vector2(40, 664), Vector2(130, 36))
	previous.pressed.connect(func() -> void: page_index -= 1; _fill_list())
	next = _button("Next", Vector2(450, 664), Vector2(130, 36))
	next.pressed.connect(func() -> void: page_index += 1; _fill_list())
	page_label = _add_label("", Vector2(180, 664), Vector2(260, 36), 13)
	tooltip = PanelContainer.new()
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.z_index = 10
	var style: StyleBoxFlat = theme.get_stylebox("panel", "Panel").duplicate()
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	tooltip.add_theme_stylebox_override("panel", style)
	tooltip_label = Label.new()
	tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_label.add_theme_font_size_override("font_size", 13)
	tooltip.add_child(tooltip_label)
	add_child(tooltip)
	tooltip.hide()
	visibility_changed.connect(func() -> void: tooltip.hide())
	refresh()


func refresh() -> void:
	filtered.assign(store.sessions.duplicate(true))
	for record in store.legacy_records:
		filtered.append({"id": record.id, "timestamp_utc": record.timestamp_utc, "local_time": record.local_time, "utc_offset_minutes": record.utc_offset_minutes, "tag": record.tag, "results": [record], "legacy": true})
	filtered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.timestamp_utc < b.timestamp_utc)
	var groups: Array[Dictionary] = []
	groups.assign(filtered.slice(maxi(0, filtered.size() - 100)))
	chart.set_groups(groups)
	heading.text = store.error if not store.error.is_empty() else "0–100 points · %d sessions · hover for test details · click a group to select · drag or scroll horizontally" % filtered.size()
	heading.add_theme_color_override("font_color", Palette.ERROR if not store.error.is_empty() else Palette.MUTED)
	page_index = 0
	detail.text = "Select a session"
	detail_meta.text = "to see all five tests."
	detail_meta.tooltip_text = ""
	for index in detail_scores.size():
		detail_rows[index].modulate.a = 1.0
		detail_scores[index].text = "--"
		detail_rules[index].text = ""
	var empty: Array[Dictionary] = []
	radar.set_results(empty)
	tooltip.hide()
	_fill_list()


static func total_points(group: Dictionary) -> float:
	var total := 0.0
	for result in group.results:
		total += Scores.points(result.project, result.stats.median)
	return total


func _fill_list() -> void:
	list.clear()
	shown.clear()
	var newest := filtered.duplicate()
	newest.reverse()
	shown.assign(newest.slice(page_index * 50, (page_index + 1) * 50))
	for group in shown:
		var score := "%.1f / 500" % total_points(group) if not group.get("legacy", false) else "%.1f / 100 [legacy]" % total_points(group)
		var row := "%s | %s | %s" % [group.local_time, score, group.tag if not group.tag.is_empty() else "--"]
		list.add_item(row)
		list.set_item_tooltip(list.item_count - 1, row)
	previous.disabled = page_index == 0
	next.disabled = (page_index + 1) * 50 >= filtered.size()
	page_label.text = "Page %d / %d · %d entries" % [page_index + 1, maxi(1, ceili(filtered.size() / 50.0)), filtered.size()]


func _show_group(group: Dictionary) -> void:
	var bias := int(group.utc_offset_minutes)
	detail.text = "Legacy single result" if group.get("legacy", false) else "%.1f / 500 points" % total_points(group)
	detail_meta.text = "%s UTC%s%02d:%02d\nTag: %s" % [group.local_time, "+" if bias >= 0 else "-", absi(bias) / 60, absi(bias) % 60, group.tag if not group.tag.is_empty() else "--"]
	detail_meta.tooltip_text = detail_meta.text
	for index in Scores.PROJECTS.size():
		var mode: Dictionary = Scores.PROJECTS[index]
		detail_scores[index].text = "--"
		detail_rules[index].text = "No result"
		detail_rows[index].modulate.a = 0.4
		for result in group.results:
			if result.project == mode.key:
				detail_rows[index].modulate.a = 1.0
				detail_scores[index].text = "%.1f pts" % Scores.points(mode.key, result.stats.median)
				detail_rules[index].text = "%.1f %s  /  Rules v%d  /  Sens %.2f" % [result.stats.median, "%" if mode.key == "tracking" else "ms", result.rule_version, result.look_sens]
	var results: Array[Dictionary] = []
	results.assign(group.results)
	radar.set_results(results)
	chart.selected_id = group.id
	chart.queue_redraw()
	for index in shown.size():
		if shown[index].id == group.id:
			list.select(index)
			break


func _show_tooltip(record: Dictionary) -> void:
	if record.is_empty():
		tooltip.hide()
		return
	var name := ""
	for mode in Scores.PROJECTS:
		if mode.key == record.project:
			name = mode.name
	var unit := "%" if record.project == "tracking" else "ms"
	var rounds: Array[String] = []
	for sample in record.samples:
		rounds.append("%.1f" % (float(sample) if record.project == "tracking" else float(sample) / 1000.0))
	var bias := int(record.utc_offset_minutes)
	tooltip_label.text = "%s / %s\nCompleted: %s UTC%s%02d:%02d\nRules v%d / Sens %.2f\nTag: %s\nRounds (%s): %s\nMean: %.1f / Std dev: %.1f %s" % [name, Scores.display(record.project, record.stats.median), record.local_time, "+" if bias >= 0 else "-", absi(bias) / 60, absi(bias) % 60, record.rule_version, record.look_sens, record.tag if not record.tag.is_empty() else "--", unit, ", ".join(rounds), record.stats.mean, record.stats.deviation, unit]
	if record.project == "tracking":
		var average := 0.0
		for degrees in record.errors_degrees:
			average += float(degrees) / 5.0
		tooltip_label.text += "\nMean angular error: %.2f deg" % average
	tooltip.size = tooltip.get_combined_minimum_size()
	var cursor := get_local_mouse_position()
	tooltip.position = Vector2(clampf(cursor.x + 16, 8, size.x - tooltip.size.x - 8), clampf(cursor.y + 18, 8, size.y - tooltip.size.y - 8))
	tooltip.show()


func _add_label(text: String, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_value
	label.size = size_value
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _button(text: String, position_value: Vector2, size_value: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position_value
	button.size = size_value
	add_child(button)
	return button
