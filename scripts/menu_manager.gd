class_name MenuManager
extends Control

var screens: Dictionary = {}
var history: Array[String] = []
var current: String = ""
var content: VBoxContainer
var status_label: Label

func _ready() -> void:
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var is_mob := OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

	# 1. Кинематографичный левосторонний виньет (чтобы UI слева четко читался, а 3D битва справа оставалась открытой)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.04, 0.05, 0.08, 0.92))
	grad.set_offset(0, 0.0)
	grad.add_point(0.38, Color(0.04, 0.05, 0.08, 0.70))
	grad.add_point(0.70, Color(0.04, 0.05, 0.08, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)

	var bg := TextureRect.new()
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 2. Левосторонний скролл-контейнер меню
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scroll)

	var margin_container := MarginContainer.new()
	margin_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin_container.add_theme_constant_override("margin_left", 20 if is_mob else 64)
	margin_container.add_theme_constant_override("margin_top", 24 if is_mob else 48)
	margin_container.add_theme_constant_override("margin_bottom", 24 if is_mob else 48)
	scroll.add_child(margin_container)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360 if is_mob else 420, 0)
	margin_container.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10 if is_mob else 14)
	panel.add_child(outer)

	# Заголовок игры (Genjvaniya)
	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.text = tr("GENJVANIA_TITLE")
	outer.add_child(title)

	var subtitle := Label.new()
	subtitle.theme_type_variation = "HintLabel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	subtitle.text = tr("GENJVANIA_SUBTITLE")
	subtitle.add_theme_color_override("font_color", UITheme.ACCENT_COLOR)
	outer.add_child(subtitle)

	outer.add_child(HSeparator.new())

	content = VBoxContainer.new()
	outer.add_child(content)

	outer.add_child(HSeparator.new())

	status_label = Label.new()
	status_label.theme_type_variation = "HintLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	outer.add_child(status_label)
	set_status(tr("STATUS_IDLE"))

	# Подсказка по управлению 3D сценой
	var cam_hint := Label.new()
	cam_hint.theme_type_variation = "HintLabel"
	cam_hint.text = tr("HINT_CAMERA_DRAG")
	cam_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cam_hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78, 0.75))
	outer.add_child(cam_hint)

func register(screen_name: String, screen: MenuScreen) -> void:
	screens[screen_name] = screen
	screen.visible = false
	content.add_child(screen)
	screen.navigate.connect(show_screen)
	screen.back_requested.connect(go_back)
	screen.status_requested.connect(set_status)

func show_screen(screen_name: String, push_history: bool = true) -> void:
	if not screens.has(screen_name):
		push_warning("MenuManager: нет экрана " + screen_name)
		return
	if current != "" and push_history:
		history.append(current)
	if current != "" and screens.has(current):
		screens[current].visible = false
	current = screen_name
	var s: MenuScreen = screens[current]
	s.visible = true
	s.on_shown()

func go_back() -> void:
	if history.is_empty():
		return
	var prev: String = history.pop_back()
	show_screen(prev, false)

func set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	var color: Color = UITheme.ERROR_COLOR if is_error else UITheme.MUTED_COLOR
	status_label.add_theme_color_override("font_color", color)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back()
