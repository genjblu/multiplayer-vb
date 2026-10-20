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

	# Фон: кинематографичный радиально-вертикальный градиент
	var grad := Gradient.new()
	grad.set_color(0, Color("1a202c"))
	grad.set_color(1, Color("080a0e"))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.4)
	tex.fill_to = Vector2(1.0, 1.0)
	var bg := TextureRect.new()
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	panel.add_child(outer)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "3D FPS MULTIPLAYER"
	outer.add_child(title)

	var subtitle := Label.new()
	subtitle.theme_type_variation = "HintLabel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.text = "TACTICAL COMBAT • MULTIPLAYER & TRAINING"
	subtitle.add_theme_color_override("font_color", Color("ff9933"))
	outer.add_child(subtitle)

	outer.add_child(HSeparator.new())

	content = VBoxContainer.new()
	outer.add_child(content)

	outer.add_child(HSeparator.new())
	status_label = Label.new()
	status_label.theme_type_variation = "HintLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(status_label)
	set_status("Статус: ожидание...")

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
