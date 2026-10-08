extends RefCounted

# sRGB conversions of Nigh/xianii-theme dark OKLCH tokens (MIT).
const BASE := Color("#242424")
const SURFACE := Color("#161616")
const BORDER := Color("#404040")
const INK := Color("#f2f2f2")
const MUTED := Color(0.949, 0.949, 0.949, 0.7)
const PRIMARY := Color("#ffa1ad")
const SECONDARY := Color("#d8b0ff")
const ACCENT := Color("#7fcfc4")
const SUCCESS := Color("#7fc08c")
const WARNING := Color("#eebc4a")
const ERROR := Color("#fa6863")


static func style(color: Color, border: Color = BORDER) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_border_width_all(1)
	box.border_color = border
	box.set_corner_radius_all(8)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font = load("res://assets/MapleMono-Regular.ttf")
	theme.default_font_size = 16
	for type in ["Label", "Button", "LineEdit", "OptionButton", "ItemList"]:
		theme.set_color("font_color", type, INK)
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, style(SURFACE))
		theme.set_stylebox("hover", type, style(BASE.lightened(0.08), PRIMARY))
		theme.set_stylebox("pressed", type, style(Color("#49343b"), PRIMARY))
		theme.set_stylebox("focus", type, style(Color.TRANSPARENT, PRIMARY))
		theme.set_stylebox("disabled", type, style(SURFACE))
		theme.set_color("font_disabled_color", type, MUTED)
	theme.set_stylebox("normal", "LineEdit", style(SURFACE))
	theme.set_stylebox("focus", "LineEdit", style(SURFACE, PRIMARY))
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", PRIMARY)
	theme.set_stylebox("panel", "Panel", style(SURFACE))
	theme.set_stylebox("panel", "ItemList", style(SURFACE))
	theme.set_stylebox("selected", "ItemList", style(Color("#49343b"), PRIMARY))
	theme.set_stylebox("selected_focus", "ItemList", style(Color("#49343b"), PRIMARY))
	theme.set_stylebox("panel", "PopupMenu", style(SURFACE))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_stylebox("hover", "PopupMenu", style(BASE))
	theme.set_stylebox("slider", "HSlider", style(BORDER))
	theme.set_stylebox("grabber_area", "HSlider", style(ACCENT))
	theme.set_stylebox("grabber_area_highlight", "HSlider", style(PRIMARY))
	return theme
