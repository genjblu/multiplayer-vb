class_name ScreenLan
extends MenuScreen

signal join_requested(ip: String, port: int)
signal server_found(server_info: Dictionary)

var list_container: VBoxContainer
var status_lbl: Label
var scroll: ScrollContainer
var _refresh_timer: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(500, 380)

	add_child(_make_label("Поиск серверов в локальной сети", "HeadingLabel"))

	status_lbl = Label.new()
	status_lbl.text = "Сканирование локальной сети..."
	status_lbl.modulate = Color(0.8, 0.8, 0.8)
	add_child(status_lbl)

	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.add_theme_constant_override("separation", 8)
	scroll.add_child(list_container)

	var hbox_btns := HBoxContainer.new()
	hbox_btns.add_theme_constant_override("separation", 12)
	add_child(hbox_btns)

	var btn_refresh := _make_button("Обновить")
	btn_refresh.pressed.connect(_refresh_list)
	hbox_btns.add_child(btn_refresh)

	hbox_btns.add_child(_make_back_button())

	visibility_changed.connect(func():
		if visible:
			LanDiscovery.start_listening()
			_refresh_list()
		else:
			LanDiscovery.stop_listening()
	)

	if LanDiscovery and LanDiscovery.has_signal("server_found"):
		LanDiscovery.server_found.connect(func(info):
			server_found.emit(info)
			_render_servers()
		)

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer += delta
	if _refresh_timer >= 0.5:
		_refresh_timer = 0.0
		_render_servers()

func _refresh_list() -> void:
	LanDiscovery.discovered_servers.clear()
	_render_servers()

func _render_servers() -> void:
	if not list_container:
		return

	var servers = LanDiscovery.discovered_servers.values()
	if servers.is_empty():
		status_lbl.text = "Серверы не найдены. Создайте игру на другом устройстве."
	else:
		status_lbl.text = "Найдено серверов: %d" % servers.size()

	for c in list_container.get_children():
		c.queue_free()

	for entry in servers:
		var d: Dictionary = entry["data"]
		var ip: String = d.get("ip", "127.0.0.1")
		var port: int = int(d.get("port", 7777))
		var room: String = d.get("room", "Комната")
		var host: String = d.get("host", "Хост")
		var map_name: String = d.get("map", "Арена")
		var mode: String = d.get("mode", "ffa")
		var ff: bool = d.get("ff", false)
		var in_game: bool = d.get("in_game", false)
		var players: int = int(d.get("players", 1))
		var max_p: int = int(d.get("max_players", 16))

		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(0, 56)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.16, 0.20, 0.9)
		sb.border_color = Color(0.3, 0.35, 0.45, 0.6)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", sb)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		panel.add_child(row)

		var tag_lbl := Label.new()
		tag_lbl.custom_minimum_size = Vector2(75, 0)
		tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if in_game:
			tag_lbl.text = "[В ИГРЕ]"
			tag_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
		else:
			tag_lbl.text = "[В ЛОББИ]"
			tag_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		row.add_child(tag_lbl)

		var info_box := VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_lbl := Label.new()
		name_lbl.text = "%s (Хост: %s)" % [room, host]
		name_lbl.add_theme_font_size_override("font_size", 15)
		info_box.add_child(name_lbl)

		var mode_names = {"ffa": "FFA", "2v2": "2v2", "3v3v3": "3v3v3", "4v4": "4v4"}
		var sub_lbl := Label.new()
		sub_lbl.text = "%s | %s | FF: %s | %d/%d" % [
			map_name, mode_names.get(mode, mode), ("Вкл" if ff else "Выкл"), players, max_p
		]
		sub_lbl.add_theme_font_size_override("font_size", 12)
		sub_lbl.modulate = Color(0.7, 0.7, 0.7)
		info_box.add_child(sub_lbl)
		row.add_child(info_box)

		var btn_join := Button.new()
		btn_join.text = "Войти"
		btn_join.custom_minimum_size = Vector2(80, 36)
		btn_join.pressed.connect(func():
			join_requested.emit(ip, port)
		)
		row.add_child(btn_join)

		list_container.add_child(panel)
