class_name ScreenLan
extends MenuScreen

signal join_requested(ip: String, port: int)

var list_box: VBoxContainer

func _ready() -> void:
	add_child(_make_label("Комнаты в локальной сети", "HeadingLabel"))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(list_box)

	var b_refresh := _make_button("Обновить")
	b_refresh.pressed.connect(_on_refresh_pressed)
	add_child(b_refresh)
	add_child(_make_back_button())

	LanDiscovery.rooms_changed.connect(set_rooms)
	visibility_changed.connect(_on_visibility_changed)
	set_rooms([])

func _exit_tree() -> void:
	LanDiscovery.stop_listening()

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		LanDiscovery.start_listening()
		set_rooms(LanDiscovery.get_rooms())
	else:
		LanDiscovery.stop_listening()

func _on_refresh_pressed() -> void:
	LanDiscovery.refresh()

# rooms: массив словарей {"name": String, "ip": String, "port": int, "players": int}
func set_rooms(rooms: Array) -> void:
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	if rooms.is_empty():
		list_box.add_child(_make_label("Идёт поиск комнат...", "HintLabel"))
		return
	for room in rooms:
		var ip: String = room["ip"]
		var port: int = room["port"]
		var b := _make_button("%s  (игроков: %d)" % [room["name"], room["players"]])
		b.pressed.connect(func(): join_requested.emit(ip, port))
		list_box.add_child(b)
