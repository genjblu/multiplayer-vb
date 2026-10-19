class_name KillFeed
extends Control

const MAX_LINES: int = 5
const LIFETIME: float = 4.2

var list: VBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -340
	offset_top = 16
	offset_right = -16
	offset_bottom = 260

	list = VBoxContainer.new()
	list.name = "List"
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	list.alignment = BoxContainer.ALIGNMENT_BEGIN
	list.add_theme_constant_override("separation", 6)
	add_child(list)

	if GameStats:
		GameStats.kill_feed_event.connect(_on_kill_event)

func _on_kill_event(data: Dictionary) -> void:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.11, 0.85)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.15)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	row.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var my_name: String = GameStats.local_nick

	if data.get("is_suicide", false):
		var v_lbl := Label.new()
		v_lbl.text = str(data.get("victim_name", "Игрок"))
		var v_col: Color = data.get("victim_col", Color.WHITE)
		v_lbl.add_theme_color_override("font_color", v_col)
		v_lbl.add_theme_font_size_override("font_size", 14)
		hbox.add_child(v_lbl)

		var skull := Label.new()
		skull.text = "☠️ разбился"
		skull.add_theme_font_size_override("font_size", 13)
		skull.modulate = Color(0.8, 0.8, 0.8, 0.8)
		hbox.add_child(skull)
	else:
		var killer_name: String = str(data.get("killer_name", "Игрок"))
		var killer_col: Color = data.get("killer_col", Color.WHITE)
		var victim_name: String = str(data.get("victim_name", "Игрок"))
		var victim_col: Color = data.get("victim_col", Color.WHITE)
		var weapon_name: String = str(data.get("weapon_name", ""))
		var is_hs: bool = bool(data.get("is_headshot", false))

		# Имя стрелка
		var k_lbl := Label.new()
		k_lbl.text = killer_name
		k_lbl.add_theme_color_override("font_color", killer_col)
		k_lbl.add_theme_font_size_override("font_size", 14)
		if killer_name == my_name:
			k_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
		hbox.add_child(k_lbl)

		# Иконка оружия
		var w_lbl := Label.new()
		var w_text: String = weapon_name if not weapon_name.is_empty() else "🔫"
		w_lbl.text = "[%s]" % w_text
		w_lbl.add_theme_font_size_override("font_size", 13)
		w_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
		hbox.add_child(w_lbl)

		# Значок хедшота
		if is_hs:
			var hs_lbl := Label.new()
			hs_lbl.text = "🎯"
			hs_lbl.add_theme_font_size_override("font_size", 13)
			hbox.add_child(hs_lbl)

		# Имя жертвы
		var v_lbl := Label.new()
		v_lbl.text = victim_name
		v_lbl.add_theme_color_override("font_color", victim_col)
		v_lbl.add_theme_font_size_override("font_size", 14)
		if victim_name == my_name:
			v_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		hbox.add_child(v_lbl)

	_add_item_to_list(row)

func _on_legacy_message(text: String) -> void:
	# Если событие не содержит детальных метаданных
	if list == null:
		return
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	_add_item_to_list(label)

func _add_item_to_list(node: Control) -> void:
	if list == null:
		return
	list.add_child(node)
	while list.get_child_count() > MAX_LINES:
		var oldest: Node = list.get_child(0)
		list.remove_child(oldest)
		oldest.queue_free()

	# Анимация появления и затухания
	node.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 1.0, 0.15)
	tw.tween_interval(LIFETIME)
	tw.tween_property(node, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		if is_instance_valid(node):
			node.queue_free()
	)
