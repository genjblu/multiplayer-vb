class_name ScreenLobby
extends MenuScreen

signal leave_requested
signal start_game_requested

var players_container: VBoxContainer
var map_label: Label
var mode_label: Label
var ff_label: Label
var start_button: Button
var team_buttons_box: Container
var code_panel: PanelContainer
var code_label: Label
var copy_btn: Button
var current_room_code: String = ""

func _ready() -> void:
	# Растягиваем экран по родителю
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	add_child(_make_label("Комната ожидания (Лобби)", "HeadingLabel"))

	# Оборачиваем всё лобби в ScrollContainer, чтобы на телефонах и низких разрешениях ничего не срезалось
	var main_scroll := ScrollContainer.new()
	main_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_scroll.custom_minimum_size = Vector2(0, 240)
	add_child(main_scroll)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 16)
	main_scroll.add_child(hbox)

	# --- ЛЕВАЯ КОЛОНКА: СПИСОК ИГРОКОВ ---
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.custom_minimum_size = Vector2(240, 220)
	hbox.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)

	var lbl_pl := Label.new()
	lbl_pl.text = "Подключённые игроки:"
	lbl_pl.theme_type_variation = "SubheadingLabel"
	left_vbox.add_child(lbl_pl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vbox.add_child(scroll)

	players_container = VBoxContainer.new()
	players_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_container.add_theme_constant_override("separation", 4)
	scroll.add_child(players_container)

	# --- ПРАВАЯ КОЛОНКА: ИНФОРМАЦИЯ И КНОПКИ ---
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.custom_minimum_size = Vector2(280, 0)
	right_vbox.add_theme_constant_override("separation", 8)
	hbox.add_child(right_vbox)

	# Инфо-блок карты и режима
	var info_panel := PanelContainer.new()
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 4)
	info_panel.add_child(info_vbox)

	map_label = Label.new()
	mode_label = Label.new()
	ff_label = Label.new()
	info_vbox.add_child(map_label)
	info_vbox.add_child(mode_label)
	info_vbox.add_child(ff_label)
	right_vbox.add_child(info_panel)

	# Блок с кодом комнаты (для приглашения друзей)
	code_panel = PanelContainer.new()
	code_panel.visible = false
	var code_hbox := HBoxContainer.new()
	code_hbox.add_theme_constant_override("separation", 8)
	code_panel.add_child(code_hbox)

	code_label = Label.new()
	code_label.theme_type_variation = "SubheadingLabel"
	code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_hbox.add_child(code_label)

	copy_btn = _make_button(tr("BTN_COPY_CODE"))
	copy_btn.custom_minimum_size = Vector2(90, 32)
	copy_btn.pressed.connect(_on_copy_code_pressed)
	code_hbox.add_child(copy_btn)
	right_vbox.add_child(code_panel)

	# Выбор команды / цвета
	var choose_lbl := Label.new()
	choose_lbl.text = "Выберите сторону / цвет:"
	right_vbox.add_child(choose_lbl)

	team_buttons_box = VBoxContainer.new()
	team_buttons_box.add_theme_constant_override("separation", 6)
	right_vbox.add_child(team_buttons_box)

	# Кнопки действий
	start_button = _make_button("Начать игру", true)
	start_button.custom_minimum_size = Vector2(0, 38)
	start_button.pressed.connect(func(): start_game_requested.emit())
	right_vbox.add_child(start_button)

	var btn_leave := _make_button("Покинуть лобби")
	btn_leave.custom_minimum_size = Vector2(0, 36)
	btn_leave.pressed.connect(func(): leave_requested.emit())
	right_vbox.add_child(btn_leave)

	if GameStats:
		GameStats.stats_changed.connect(refresh_lobby)

func setup_lobby(map_name: String, mode: String, ff: bool, is_host: bool, room_code: String = "") -> void:
	map_label.text = "Карта: " + map_name
	var mode_titles := {
		"ffa": "Каждый за себя (FFA)",
		"2v2": "Команды 2v2",
		"3v3v3": "Команды 3v3v3",
		"4v4": "Команды 4v4",
		"fist_fight": "🥊 Кулачный бой",
		"highway_fury": "🏎️ Дорога ярости"
	}
	mode_label.text = "Режим: " + mode_titles.get(mode, mode)
	ff_label.text = "Огонь по своим: " + ("ВКЛ" if ff else "ВЫКЛ")

	current_room_code = room_code
	if not current_room_code.is_empty():
		code_panel.visible = true
		code_label.text = "%s %s" % [tr("LOBBY_CODE_HEADER"), current_room_code]
		copy_btn.text = tr("BTN_COPY_CODE")
	else:
		code_panel.visible = false

	start_button.visible = is_host
	_build_team_buttons(mode)
	refresh_lobby()

func _on_copy_code_pressed() -> void:
	if not current_room_code.is_empty():
		DisplayServer.clipboard_set(current_room_code)
		copy_btn.text = tr("CODE_COPIED")
		var tw := copy_btn.create_tween()
		tw.tween_interval(1.8)
		tw.tween_callback(func():
			if is_instance_valid(copy_btn):
				copy_btn.text = tr("BTN_COPY_CODE")
		)

func _build_team_buttons(mode: String) -> void:
	for c in team_buttons_box.get_children():
		c.queue_free()

	if mode == "ffa" or mode == "fist_fight" or mode == "highway_fury":
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		team_buttons_box.add_child(grid)

		var colors = [
			{"name": "Оранж", "col": Color(1.0, 0.55, 0.1)},
			{"name": "Бирюза", "col": Color(0.1, 0.85, 0.85)},
			{"name": "Фиолет", "col": Color(0.7, 0.3, 0.95)},
			{"name": "Лайм", "col": Color(0.4, 0.95, 0.2)},
			{"name": "Белый", "col": Color(0.95, 0.95, 0.95)},
			{"name": "Розовый", "col": Color(1.0, 0.35, 0.7)}
		]
		for item in colors:
			var btn := Button.new()
			btn.text = item["name"]
			btn.custom_minimum_size = Vector2(0, 36)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var col: Color = item["col"]
			btn.pressed.connect(func():
				GameStats.set_player_team_and_color.rpc_id(1, 0, col)
			)
			grid.add_child(btn)
	else:
		var teams = [
			{"id": 1, "name": "Команда 1 (Синие)", "col": Color(0.2, 0.5, 1.0)},
			{"id": 2, "name": "Команда 2 (Красные)", "col": Color(1.0, 0.25, 0.25)},
			{"id": 3, "name": "Команда 3 (Зелёные)", "col": Color(0.2, 0.85, 0.3)},
			{"id": 4, "name": "Команда 4 (Жёлтые)", "col": Color(1.0, 0.85, 0.15)}
		]
		var count: int = 2
		if mode == "3v3v3": count = 3
		elif mode == "4v4": count = 4

		for i in range(count):
			var t = teams[i]
			var btn := Button.new()
			btn.text = t["name"]
			btn.custom_minimum_size = Vector2(0, 38)
			var tid: int = t["id"]
			var col: Color = t["col"]
			btn.pressed.connect(func():
				GameStats.set_player_team_and_color.rpc_id(1, tid, col)
			)
			team_buttons_box.add_child(btn)

func refresh_lobby() -> void:
	if not players_container:
		return
	for c in players_container.get_children():
		c.queue_free()

	for peer_id in GameStats.players.keys():
		var p = GameStats.players[peer_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		# Цветной квадратик команды / скина
		var col_rect := ColorRect.new()
		col_rect.custom_minimum_size = Vector2(20, 20)
		col_rect.color = p.get("color", Color.WHITE)
		row.add_child(col_rect)

		var name_lbl := Label.new()
		var is_host_tag := " (Хост)" if peer_id == 1 else ""
		name_lbl.text = p.get("name", "Игрок") + is_host_tag
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var team_lbl := Label.new()
		var tid: int = int(p.get("team", 0))
		team_lbl.text = ("Команда " + str(tid)) if tid > 0 else "FFA"
		team_lbl.modulate = Color(0.8, 0.8, 0.8)
		row.add_child(team_lbl)

		players_container.add_child(row)
