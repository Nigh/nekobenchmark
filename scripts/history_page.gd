extends Control

signal back_requested
const Scores = preload("res://scripts/score_store.gd")
const Chart = preload("res://scripts/trend_chart.gd")
const Palette = preload("res://scripts/app_theme.gd")
const History = preload("res://scripts/history_store.gd")
var store
var project_select: OptionButton
var tag_select: OptionButton
var version_select: OptionButton
var chart
var list: ItemList
var detail: Label
var heading: Label
var page_label: Label
var previous: Button
var next: Button
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
	project_select = OptionButton.new()
	project_select.position = Vector2(40, 96)
	project_select.size = Vector2(300, 44)
	for mode in Scores.PROJECTS:
		project_select.add_item(mode.name)
	add_child(project_select)
	project_select.item_selected.connect(func(_index: int) -> void: refresh(true))
	tag_select = OptionButton.new()
	tag_select.clip_text = true
	tag_select.fit_to_longest_item = false
	tag_select.position = Vector2(360, 96)
	tag_select.size = Vector2(360, 44)
	add_child(tag_select)
	tag_select.item_selected.connect(func(_index: int) -> void: refresh())
	version_select = OptionButton.new()
	version_select.position = Vector2(740, 96)
	version_select.size = Vector2(440, 44)
	add_child(version_select)
	version_select.item_selected.connect(func(_index: int) -> void: refresh())
	heading = _add_label("", Vector2(40, 150), Vector2(1200, 28), 14)
	chart = Chart.new()
	chart.position = Vector2(40, 186)
	chart.size = Vector2(1200, 216)
	chart.clip_contents = true
	chart.record_selected.connect(_show_record)
	add_child(chart)
	list = ItemList.new()
	list.position = Vector2(40, 422)
	list.size = Vector2(740, 224)
	list.item_selected.connect(func(index: int) -> void: _show_record(shown[index]))
	add_child(list)
	detail = _add_label("Select a session to see all five tests.", Vector2(810, 422), Vector2(430, 240), 13)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	previous = _button("Previous", Vector2(40, 664), Vector2(130, 36))
	previous.pressed.connect(func() -> void: page_index -= 1; _fill_list())
	next = _button("Next", Vector2(650, 664), Vector2(130, 36))
	next.pressed.connect(func() -> void: page_index += 1; _fill_list())
	page_label = _add_label("", Vector2(190, 664), Vector2(440, 36), 14)
	refresh(true)


func refresh(rebuild_filters: bool = false) -> void:
	var project: String = Scores.PROJECTS[project_select.selected].key
	if rebuild_filters:
		tag_select.clear()
		tag_select.add_item("All tags")
		tag_select.set_item_metadata(0, "")
		var tags: Array[String] = []
		var current_versions: Array[int] = []
		for mode in Scores.PROJECTS:
			current_versions.append(History.current_rule_version(mode.key))
		var versions: Array = [current_versions]
		for session in store.sessions:
			var signature := _session_versions(session)
			if not signature in versions:
				versions.append(signature)
		for record in store.records:
			if record.project == project and not record.tag.is_empty() and not record.tag in tags:
				tags.append(record.tag)
		tags.sort()
		for tag in tags:
			tag_select.add_item(tag)
			tag_select.set_item_metadata(tag_select.item_count - 1, tag)
		version_select.clear()
		for signature in versions:
			var labels: Array[String] = []
			for version in signature:
				labels.append(str(version))
			version_select.add_item("Set rules " + "/".join(labels))
			version_select.set_item_metadata(version_select.item_count - 1, {"versions": signature})
		var legacy_versions: Array[int] = []
		for record in store.legacy_records:
			if record.project == project and not int(record.rule_version) in legacy_versions:
				legacy_versions.append(int(record.rule_version))
		legacy_versions.sort()
		for version in legacy_versions:
			version_select.add_item("Legacy single / v%d" % version)
			version_select.set_item_metadata(version_select.item_count - 1, {"legacy": version})
		version_select.select(0)
	var selection: Dictionary = version_select.get_selected_metadata()
	var version: int = selection.legacy if selection.has("legacy") else selection.versions[project_select.selected]
	filtered.clear()
	for record in store.filtered(project, tag_select.get_selected_metadata(), version):
		var session: Dictionary = store.get_session(record)
		if (selection.has("legacy") and session.is_empty()) or (selection.has("versions") and not session.is_empty() and _session_versions(session) == selection.versions):
			filtered.append(record)
	var groups: Array[Dictionary] = []
	for record in filtered.slice(maxi(0, filtered.size() - 100)):
		var session: Dictionary = store.get_session(record).duplicate(true)
		if session.is_empty():
			session = {"local_time": record.local_time, "results": [record]}
		else:
			for result in session.results:
				result.session_id = session.id
				result.session_local_time = session.local_time
		groups.append(session)
	chart.set_groups(groups)
	heading.text = store.error if not store.error.is_empty() else "0–100 points · %d entries · latest 100 groups · drag or scroll horizontally · click a bar for details" % filtered.size()
	heading.add_theme_color_override("font_color", Palette.ERROR if not store.error.is_empty() else Palette.MUTED)
	page_index = 0
	detail.text = "Select a session to see all five tests."
	_fill_list()


func _fill_list() -> void:
	list.clear()
	shown.clear()
	var newest := filtered.duplicate()
	newest.reverse()
	shown.assign(newest.slice(page_index * 50, (page_index + 1) * 50))
	for record in shown:
		list.add_item("%s | %s | %s" % [record.get("session_local_time", record.local_time), Scores.display(record.project, record.stats.median), record.tag + ("  [legacy single result]" if not record.has("session_id") else "")])
	previous.disabled = page_index == 0
	next.disabled = (page_index + 1) * 50 >= filtered.size()
	page_label.text = "Page %d / %d · %d records" % [page_index + 1, maxi(1, ceili(filtered.size() / 50.0)), filtered.size()]


func _show_record(record: Dictionary) -> void:
	var project_name := ""
	for mode in Scores.PROJECTS:
		if mode.key == record.project:
			project_name = mode.name
	var unit := "%" if record.project == "tracking" else "ms"
	var rounds: Array[String] = []
	for sample in record.samples:
		rounds.append("%.1f" % (float(sample) if record.project == "tracking" else float(sample) / 1000.0))
	var session: Dictionary = store.get_session(record)
	var bias: int = int(record.utc_offset_minutes if session.is_empty() else session.utc_offset_minutes)
	var saved_time: String = record.local_time if session.is_empty() else session.local_time
	detail.text = "%s  UTC%s%02d:%02d\nTag: %s" % [saved_time, "+" if bias >= 0 else "-", absi(bias) / 60, absi(bias) % 60, record.tag if not record.tag.is_empty() else "--"]
	if session.is_empty():
		detail.text += "\nLegacy single result\nMedian: %s" % Scores.display(record.project, record.stats.median)
	else:
		for mode in Scores.PROJECTS:
			for result in session.results:
				if result.project == mode.key:
					detail.text += "\n%s: %s" % [mode.name, Scores.display(mode.key, result.stats.median)]
	detail.text += "\n%s: sens %.2f / v%d\nCompleted: %s\nRounds (%s): %s\nMean: %.1f / Std dev: %.1f %s" % [project_name, record.look_sens, record.rule_version, record.local_time, unit, ", ".join(rounds), record.stats.mean, record.stats.deviation, unit]
	if record.project == "tracking":
		var average := 0.0
		for degrees in record.errors_degrees:
			average += float(degrees) / 5.0
		detail.text += "\nMean angular error: %.2f deg" % average
	chart.selected_id = record.id
	chart.queue_redraw()


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


func _session_versions(session: Dictionary) -> Array[int]:
	var versions: Array[int] = []
	for mode in Scores.PROJECTS:
		for result in session.results:
			if result.project == mode.key:
				versions.append(int(result.rule_version))
	return versions
