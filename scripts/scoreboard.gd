class_name Scoreboard
extends Control

var pinned: bool = false:
	set(val):
		pinned = val
		if pinned:
			show_scoreboard()
		else:
			hide_scoreboard()

var background: ColorRect
var main_container: CenterContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	# Полупрозрачное затемнение фона
	background = ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.04, 0.05, 0.07, 0.75)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	main_container = CenterContainer.new()
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main_container)

	if GameStats:
		GameStats.stats_changed.connect(_on_stats_changed)

func _input(event: InputEvent) -> void:
	# Если на телефоне кнопка "Таблица" зафиксирована (pinned), клавиша Tab не выключает её
	if pinned:
		return

	if event is InputEventKey and event.keycode == KEY_TAB and not event.echo:
		if event.pressed:
			show_scoreboard()
		else:
			hide_scoreboard()

func show_scoreboard() -> void:
	rebuild()
	visible = true

func hide_scoreboard() -> void:
	if not pinned:
		visible = false

func _on_stats_changed() -> void:
	if visible:
		rebuild()

func rebuild() -> void:
	for c in main_container.get_children():
		c.queue_free()

	var mode: String = NetworkManager.current_mode if NetworkManager else "ffa"

	if mode == "ffa" or mode == "fist_fight":
		_build_ffa_table()
	elif mode == "2v2":
		_build_teams_2_table()
	else:
		_build_teams_4_quadrants_table()

# --- 1. ТАБЛИЦА FFA (Сверху вниз по убыванию убийств) ---
func _build_ffa_table() -> void:
	var panel := _create_card_panel(Vector2(660, 440))
	main_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "ТАБЛИЦА МАТЧА (FFA)"
	title.theme_type_variation = "HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_create_table_header())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	var sorted_players = _get_sorted_players_list()
	for p_data in sorted_players:
		list.add_child(_create_player_row(p_data))

# --- 2. ТАБЛИЦА 2v2 (Две колонки) ---
func _build_teams_2_table() -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	main_container.add_child(hbox)

	var t1_box = _create_team_quadrant(1, "СИНИЕ", Color(0.15, 0.45, 0.95), Vector2(400, 420))
	var t2_box = _create_team_quadrant(2, "КРАСНЫЕ", Color(0.95, 0.22, 0.22), Vector2(400, 420))
	hbox.add_child(t1_box)
	hbox.add_child(t2_box)

# --- 3. ТАБЛИЦА 3v3v3 / 4v4 (Сетка 2x2 ровно по твоему макету) ---
func _build_teams_4_quadrants_table() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	main_container.add_child(grid)

	var card_size := Vector2(380, 240)
	grid.add_child(_create_team_quadrant(1, "СИНИЕ", Color(0.15, 0.45, 0.95), card_size))
	grid.add_child(_create_team_quadrant(2, "КРАСНЫЕ", Color(0.95, 0.22, 0.22), card_size))
	grid.add_child(_create_team_quadrant(3, "ЗЕЛЁНЫЕ", Color(0.18, 0.78, 0.30), card_size))
	grid.add_child(_create_team_quadrant(4, "ЖЁЛТЫЕ", Color(0.95, 0.78, 0.12), card_size))

# --- Вспомогательные элементы интерфейса ---
func _create_team_quadrant(team_id: int, team_name: String, team_color: Color, min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(team_color.r * 0.22, team_color.g * 0.22, team_color.b * 0.22, 0.92)
	sb.border_color = team_color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var team_players: Array = []
	var total_kills: int = 0
	for pid in GameStats.players.keys():
		var p = GameStats.players[pid]
		p["peer_id"] = pid
		if int(p.get("team", 0)) == team_id:
			team_players.append(p)
			total_kills += int(p.get("kills", 0))

	# Сортировка по убыванию убийств
	team_players.sort_custom(func(a, b):
		if a["kills"] != b["kills"]:
			return a["kills"] > b["kills"]
		return a["deaths"] < b["deaths"]
	)

	var header_hbox := HBoxContainer.new()
	var t_title := Label.new()
	t_title.text = team_name
	t_title.add_theme_font_size_override("font_size", 16)
	t_title.add_theme_color_override("font_color", team_color.lightened(0.3))
	t_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(t_title)

	var t_score := Label.new()
	t_score.text = "Фраги: %d" % total_kills
	t_score.add_theme_font_size_override("font_size", 16)
	header_hbox.add_child(t_score)
	vbox.add_child(header_hbox)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_create_table_header())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	for p_data in team_players:
		list.add_child(_create_player_row(p_data))

	return panel

func _create_card_panel(min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	sb.border_color = Color(0.3, 0.35, 0.45, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	return panel

func _create_table_header() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)

	var nick := Label.new()
	nick.text = "Игрок"
	nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nick.modulate = Color(0.7, 0.7, 0.7)
	h.add_child(nick)

	var k := Label.new()
	k.text = "К"
	k.custom_minimum_size = Vector2(40, 0)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.modulate = Color(0.7, 0.7, 0.7)
	h.add_child(k)

	var d := Label.new()
	d.text = "С"
	d.custom_minimum_size = Vector2(40, 0)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.modulate = Color(0.7, 0.7, 0.7)
	h.add_child(d)

	var kd := Label.new()
	kd.text = "K/D"
	kd.custom_minimum_size = Vector2(50, 0)
	kd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kd.modulate = Color(0.7, 0.7, 0.7)
	h.add_child(kd)

	var ping := Label.new()
	ping.text = "Пинг"
	ping.custom_minimum_size = Vector2(45, 0)
	ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping.modulate = Color(0.7, 0.7, 0.7)
	h.add_child(ping)

	return h

func _create_player_row(p_data: Dictionary) -> PanelContainer:
	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	var is_me: bool = (int(p_data.get("peer_id", 0)) == my_id)

	var rsb := StyleBoxFlat.new()
	if is_me:
		rsb.bg_color = Color(1.0, 1.0, 1.0, 0.16)
		rsb.border_color = Color(1.0, 0.7, 0.2, 0.8)
		rsb.set_border_width_all(1)
	else:
		rsb.bg_color = Color(0.08, 0.09, 0.12, 0.5)

	rsb.set_corner_radius_all(4)
	rsb.content_margin_left = 6
	rsb.content_margin_right = 6
	rsb.content_margin_top = 4
	rsb.content_margin_bottom = 4
	row_panel.add_theme_stylebox_override("panel", rsb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row_panel.add_child(hbox)

	var col_rect := ColorRect.new()
	col_rect.custom_minimum_size = Vector2(12, 12)
	col_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col_rect.color = p_data.get("color", Color.WHITE) as Color
	hbox.add_child(col_rect)

	var name_lbl := Label.new()
	name_lbl.text = str(p_data.get("name", "Игрок"))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_me:
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	hbox.add_child(name_lbl)

	var k_lbl := Label.new()
	var kills: int = int(p_data.get("kills", 0))
	k_lbl.text = str(kills)
	k_lbl.custom_minimum_size = Vector2(40, 0)
	k_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(k_lbl)

	var d_lbl := Label.new()
	var deaths: int = int(p_data.get("deaths", 0))
	d_lbl.text = str(deaths)
	d_lbl.custom_minimum_size = Vector2(40, 0)
	d_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(d_lbl)

	var kd_lbl := Label.new()
	var ratio: float = float(kills) if deaths == 0 else (float(kills) / float(deaths))
	kd_lbl.text = "%.1f" % ratio
	kd_lbl.custom_minimum_size = Vector2(50, 0)
	kd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kd_lbl.modulate = Color(0.8, 0.8, 0.8)
	hbox.add_child(kd_lbl)

	var ping_val: int = int(p_data.get("ping", 0))
	if is_me and GameStats:
		ping_val = GameStats.get_my_ping()
	var ping_lbl := Label.new()
	ping_lbl.text = "%d ms" % ping_val if ping_val > 0 else "0 ms"
	ping_lbl.custom_minimum_size = Vector2(45, 0)
	ping_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping_lbl.modulate = Color(0.2, 0.9, 0.4) if ping_val < 60 else (Color(0.9, 0.8, 0.2) if ping_val < 120 else Color(0.9, 0.3, 0.3))
	hbox.add_child(ping_lbl)

	return row_panel

func _get_sorted_players_list() -> Array:
	var list: Array = []
	for pid in GameStats.players.keys():
		var p = GameStats.players[pid]
		p["peer_id"] = pid
		list.append(p)

	list.sort_custom(func(a, b):
		if a["kills"] != b["kills"]:
			return a["kills"] > b["kills"]
		return a["deaths"] < b["deaths"]
	)
	return list
