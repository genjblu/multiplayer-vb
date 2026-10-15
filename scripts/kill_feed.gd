class_name KillFeed
extends VBoxContainer

const MAX_LINES := 5
const LIFETIME := 5.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -200
	offset_right = 200
	offset_top = 20
	GameStats.kill_feed_message.connect(_add_line)

func _add_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	while get_child_count() > MAX_LINES:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
	get_tree().create_timer(LIFETIME).timeout.connect(func():
		if is_instance_valid(label):
			label.queue_free()
	)
