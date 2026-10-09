extends Node

var streams := {}
var player: AudioStreamPlayer
var tracking_player: AudioStreamPlayer
var last_hover_us := -100_000
var last_slide_us := -100_000
var last_kind := ""
var play_count := 0


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.max_polyphony = 4
	player.volume_db = -16.0
	add_child(player)
	for kind in ["success", "error", "hover", "press", "slide"]:
		var frequency: float = {"success": 1000.0, "error": 220.0, "hover": 1400.0, "press": 800.0, "slide": 1700.0}[kind]
		var duration: float = {"success": 0.022, "error": 0.035, "hover": 0.010, "press": 0.015, "slide": 0.008}[kind]
		streams[kind] = _tone(frequency, duration)
	streams["start"] = _tone(650.0, 0.045)
	var start_data: PackedByteArray = streams.start.data
	start_data.append_array(_tone(1100.0, 0.045).data)
	streams.start.data = start_data

	tracking_player = AudioStreamPlayer.new()
	tracking_player.volume_db = -28.0
	var loop := _tone(440.0, 0.1, false)
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = loop.data.size() / 2
	tracking_player.stream = loop
	add_child(tracking_player)


func set_tracking_weight(weight: float) -> void:
	if weight <= 0.0:
		tracking_player.stop()
		return
	tracking_player.pitch_scale = 2.0 if weight == 1.0 else 1.0
	if not tracking_player.playing:
		tracking_player.play()


static func _tone(frequency: float, seconds: float, fade: bool = true) -> AudioStreamWAV:
	var samples := int(44100 * seconds)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for index in samples:
		var t := float(index) / 44100.0
		var envelope := sin(PI * float(index) / float(samples - 1)) if fade else 1.0
		data.encode_s16(index * 2, int(16000.0 * envelope * sin(TAU * frequency * t)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.data = data
	return stream


func play(kind: String) -> void:
	var now := Time.get_ticks_usec()
	if kind == "hover":
		if now - last_hover_us < 90_000:
			return
		last_hover_us = now
	if kind == "slide":
		if now - last_slide_us < 40_000:
			return
		last_slide_us = now
	last_kind = kind
	play_count += 1
	player.stream = streams[kind]
	player.play()


func response(valid: bool) -> void:
	play("success" if valid else "error")


func bind_controls(root: Node) -> void:
	if root is Control and (root is BaseButton or root is Slider or root is LineEdit or root is ItemList or root.has_signal("group_selected")):
		var control := root as Control
		control.mouse_entered.connect(func() -> void:
			if control.is_visible_in_tree() and not (control is BaseButton and control.disabled):
				play("hover")
		)
		if control is BaseButton:
			control.button_down.connect(func() -> void: play("press"))
			if control is OptionButton:
				control.get_popup().id_focused.connect(func(_id: int) -> void: play("hover"))
				control.get_popup().index_pressed.connect(func(_index: int) -> void: play("press"))
		else:
			control.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					play("press")
			)
	for child in root.get_children():
		bind_controls(child)
