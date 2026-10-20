class_name MenuScreen
extends VBoxContainer

signal navigate(screen_name: String)
signal back_requested
signal status_requested(text: String, is_error: bool)

func _is_mob() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

func _init() -> void:
	add_theme_constant_override("separation", 8 if _is_mob() else 10)

# Менеджер вызывает это каждый раз, когда экран показывается
func on_shown() -> void:
	pass

func _make_button(text: String, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38 if _is_mob() else 44)
	if accent:
		b.theme_type_variation = "AccentButton"
	return b

func _make_label(text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	return l

func _make_row(caption: String, field: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var cap := Label.new()
	cap.text = caption
	cap.custom_minimum_size = Vector2(95 if _is_mob() else 120, 0)
	row.add_child(cap)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row

func _make_back_button() -> Button:
	var b := _make_button("Назад")
	b.pressed.connect(func(): back_requested.emit())
	return b
