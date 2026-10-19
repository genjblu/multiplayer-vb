extends Control

var default_ip: String = "127.0.0.1"
var default_port: int = 7777

var menu: MenuManager
var screen_main: ScreenMain
var screen_host: ScreenHost
var screen_lan: ScreenLan
var screen_lobby: ScreenLobby

@onready var ip_input: LineEdit = %IPInput
@onready var port_input: LineEdit = %PortInput
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var nick_edit: LineEdit = %NickEdit

var settings_dialog: Control = null

func _ready() -> void:
	GameSettings.apply_to_engine(get_viewport())
	ip_input.text = default_ip
	port_input.text = str(default_port)
	if nick_edit:
		nick_edit.max_length = 16
		nick_edit.placeholder_text = "Ваш ник"
		nick_edit.text = GameStats.local_nick

	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		net_manager.connection_failed.connect(_on_connection_failed)
		net_manager.server_disconnected.connect(_on_server_disconnected)
		net_manager.game_started.connect(_on_client_joined_lobby)
		net_manager.match_launch_requested.connect(_on_launch_match)

	_build_ui()

func _build_ui() -> void:
	for child in get_children():
		if child is CanvasItem:
			child.visible = false

	var ui_layer := CanvasLayer.new()
	add_child(ui_layer)
	menu = MenuManager.new()
	ui_layer.add_child(menu)

	screen_main = ScreenMain.new()
	screen_host = ScreenHost.new()
	var screen_join := ScreenJoin.new()
	screen_lan = ScreenLan.new()
	screen_lobby = ScreenLobby.new()

	menu.register("main", screen_main)
	menu.register("host", screen_host)
	menu.register("join", screen_join)
	menu.register("lan", screen_lan)
	menu.register("lobby", screen_lobby)

	_open_main_menu_settings()
	ui_layer.add_child(settings_dialog)

	for b in screen_main.find_children("*", "Button", true, false):
		if b.name == "SettingsButton" or "Настройк" in b.text or "Setting" in b.text:
			for conn in b.pressed.get_connections():
				b.pressed.disconnect(conn["callable"])
			b.pressed.connect(func():
				_open_main_menu_settings()
				if settings_dialog:
					settings_dialog.show()
			)

	screen_host.host_requested.connect(_on_host_requested)
	screen_join.join_requested.connect(_on_join_requested)
	screen_lan.join_requested.connect(_on_join_requested)
	screen_lobby.leave_requested.connect(_on_leave_lobby)
	screen_lobby.start_game_requested.connect(_on_start_game_from_lobby)

	menu.show_screen("main")
	screen_main.nick_edit.text = GameStats.local_nick

func _on_host_requested(port: int, room_name: String, map_id: String = "default_arena", mode: String = "ffa", ff: bool = false, publish_online: bool = true, custom_ip: String = "") -> void:
	GameStats.set_nick(screen_main.get_nick())
	if port <= 0:
		menu.set_status("Статус: Укажите корректный порт!", true)
		return

	menu.set_status("Статус: Запуск лобби...")
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		var err: Error = net_manager.host_game(port, map_id, mode, ff)
		if err == OK:
			var map_title := "Арена"
			var map_path := "res://maps/%s.tres" % map_id
			if ResourceLoader.exists(map_path):
				var res = load(map_path) as MapData
				if res:
					map_title = res.display_name
			LanDiscovery.start_broadcast(room_name, port, map_title, mode, ff, false)
			if publish_online and OnlineMatchmaking:
				OnlineMatchmaking.register_server(room_name, port, map_title, mode, ff, custom_ip)

			screen_lobby.setup_lobby(map_title, mode, ff, true)
			menu.show_screen("lobby")
		else:
			menu.set_status("Статус: Ошибка создания сервера!", true)

func _on_join_requested(ip: String, port: int) -> void:
	GameStats.set_nick(screen_main.get_nick())
	if ip.is_empty() or port <= 0:
		menu.set_status("Статус: Введите валидные IP и порт!", true)
		return

	var net_manager = get_node_or_null("/root/NetworkManager")
	if not net_manager:
		return

	var key := "%s:%d" % [ip, port]
	var is_server_in_game: bool = false
	var map_id: String = "default_arena"

	var s_data: Dictionary = {}
	if LanDiscovery.discovered_servers.has(key):
		s_data = LanDiscovery.discovered_servers[key]["data"]
		is_server_in_game = s_data.get("in_game", false)
		map_id = s_data.get("map_id", "default_arena")
	elif screen_lan and screen_lan.online_servers_list:
		for s in screen_lan.online_servers_list:
			if str(s.get("ip")) == ip and int(s.get("port", 7777)) == port:
				s_data = s
				is_server_in_game = s.get("in_game", false)
				map_id = s.get("map", "default_arena")
				break

	if is_server_in_game:
		net_manager.joined_as_late = true
		net_manager.pending_ip = ip
		net_manager.pending_port = port
		net_manager.current_map_id = map_id
		net_manager.current_mode = str(s_data.get("mode", "ffa"))
		net_manager.friendly_fire = bool(s_data.get("friendly_fire", s_data.get("ff", false)))
		_on_launch_match()
	else:
		net_manager.joined_as_late = false
		menu.set_status("Статус: Подключение к %s:%d..." % [ip, port])
		var err: Error = net_manager.join_game(ip, port)
		if err != OK:
			menu.set_status("Статус: Ошибка подключения!", true)

func _on_client_joined_lobby() -> void:
	var net_manager = get_node_or_null("/root/NetworkManager")
	if not net_manager:
		return

	if net_manager.is_match_running:
		net_manager.joined_as_late = true
		_on_launch_match()
		return

	var map_display: String = "Арена"
	var map_path := "res://maps/%s.tres" % net_manager.current_map_id
	if ResourceLoader.exists(map_path):
		var res = load(map_path) as MapData
		if res:
			map_display = res.display_name

	screen_lobby.setup_lobby(map_display, net_manager.current_mode, net_manager.friendly_fire, false)
	menu.show_screen("lobby")

func _on_leave_lobby() -> void:
	LanDiscovery.stop_broadcast()
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		net_manager.disconnect_peer()
	menu.show_screen("main")

func _on_start_game_from_lobby() -> void:
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		net_manager.host_start_match()

func _on_launch_match() -> void:
	if LanDiscovery:
		LanDiscovery.update_room_info(GameStats.players.size(), true)

	var net_manager = get_node_or_null("/root/NetworkManager")
	var target_scene := "res://scenes/arena.tscn"
	var map_to_load: MapData = null
	if net_manager:
		var map_path := "res://maps/%s.tres" % net_manager.current_map_id
		if ResourceLoader.exists(map_path):
			map_to_load = load(map_path) as MapData
			if map_to_load and not map_to_load.scene_path.is_empty():
				target_scene = map_to_load.scene_path

	var loader := LoadingScreen.new()
	loader.map_data = map_to_load
	get_tree().root.add_child(loader)
	get_tree().change_scene_to_file(target_scene)

func _on_connection_failed() -> void:
	if menu:
		menu.set_status("Статус: Не удалось подключиться к серверу!", true)
		menu.show_screen("main")

func _on_server_disconnected() -> void:
	if menu:
		menu.set_status("Статус: Соединение разорвано.", true)
		menu.show_screen("main")

func _open_main_menu_settings() -> void:
	if settings_dialog and is_instance_valid(settings_dialog):
		settings_dialog.show()
		return

	GameSettings.ensure_loaded()

	# 1. Полноэкранный слой с затемнением фона
	settings_dialog = Control.new()
	settings_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_dialog.visible = false

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.07, 0.75)
	settings_dialog.add_child(bg)

	# 2. Центральная карточка настроек
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_dialog.add_child(center)

	var panel := PanelContainer.new()
	panel.theme = UITheme.build()
	panel.custom_minimum_size = Vector2(720, 540)
	center.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(main_vbox)

	var title := Label.new()
	title.text = tr("SETTINGS_TITLE")
	title.theme_type_variation = "HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tabs)

	# === ВКЛАДКА 1: УПРАВЛЕНИЕ ===
	var scroll_input := ScrollContainer.new()
	scroll_input.name = tr("TAB_CONTROLS")
	tabs.add_child(scroll_input)
	var vbox_input := VBoxContainer.new()
	vbox_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_input.add_theme_constant_override("separation", 10)
	scroll_input.add_child(vbox_input)

	var lbl_sens := Label.new()
	lbl_sens.text = _tr_fmt("LBL_MOUSE_SENS", GameSettings.mouse_sensitivity)
	vbox_input.add_child(lbl_sens)
	var sens_slider := HSlider.new()
	sens_slider.min_value = 0.0005
	sens_slider.max_value = 0.015
	sens_slider.step = 0.0005
	sens_slider.value = GameSettings.mouse_sensitivity
	sens_slider.value_changed.connect(func(val):
		GameSettings.mouse_sensitivity = val
		lbl_sens.text = _tr_fmt("LBL_MOUSE_SENS", val)
	)
	vbox_input.add_child(sens_slider)

	var lbl_ads_sens := Label.new()
	lbl_ads_sens.text = _tr_fmt("LBL_ADS_SENS", int(round(GameSettings.ads_mouse_multiplier * 100.0)))
	vbox_input.add_child(lbl_ads_sens)
	var ads_slider := HSlider.new()
	ads_slider.min_value = 0.1
	ads_slider.max_value = 1.0
	ads_slider.step = 0.05
	ads_slider.value = GameSettings.ads_mouse_multiplier
	ads_slider.value_changed.connect(func(val):
		GameSettings.ads_mouse_multiplier = val
		lbl_ads_sens.text = _tr_fmt("LBL_ADS_SENS", int(round(val * 100.0)))
	)
	vbox_input.add_child(ads_slider)

	var chk_inv := CheckBox.new()
	chk_inv.text = tr("CHK_INVERT_Y")
	chk_inv.button_pressed = GameSettings.invert_y
	chk_inv.toggled.connect(func(pressed): GameSettings.invert_y = pressed)
	vbox_input.add_child(chk_inv)

	var chk_crouch_mode := CheckBox.new()
	chk_crouch_mode.text = tr("CHK_CROUCH_TOGGLE")
	chk_crouch_mode.button_pressed = GameSettings.crouch_toggle_mode
	chk_crouch_mode.toggled.connect(func(pressed): GameSettings.crouch_toggle_mode = pressed)
	vbox_input.add_child(chk_crouch_mode)

	# === ВКЛАДКА 2: ГРАФИКА ===
	var scroll_video := ScrollContainer.new()
	scroll_video.name = tr("TAB_VIDEO")
	tabs.add_child(scroll_video)
	var vbox_video := VBoxContainer.new()
	vbox_video.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_video.add_theme_constant_override("separation", 10)
	scroll_video.add_child(vbox_video)

	var chk_full := CheckBox.new()
	chk_full.text = tr("CHK_FULLSCREEN")
	chk_full.button_pressed = GameSettings.fullscreen
	chk_full.toggled.connect(func(pressed):
		GameSettings.fullscreen = pressed
		GameSettings.apply_to_engine(get_viewport())
	)
	vbox_video.add_child(chk_full)

	var lbl_ui_sc := Label.new()
	lbl_ui_sc.text = _tr_fmt("LBL_UI_SCALE", int(round(GameSettings.ui_scale * 100.0)))
	vbox_video.add_child(lbl_ui_sc)
	var ui_sc_slider := HSlider.new()
	ui_sc_slider.min_value = 0.75
	ui_sc_slider.max_value = 2.0
	ui_sc_slider.step = 0.05
	ui_sc_slider.value = GameSettings.ui_scale
	ui_sc_slider.value_changed.connect(func(val):
		GameSettings.ui_scale = val
		lbl_ui_sc.text = _tr_fmt("LBL_UI_SCALE", int(round(val * 100.0)))
		GameSettings.apply_to_engine(get_viewport())
	)
	vbox_video.add_child(ui_sc_slider)

	var lbl_fov := Label.new()
	lbl_fov.text = _tr_fmt("LBL_FOV", int(round(GameSettings.base_fov)))
	vbox_video.add_child(lbl_fov)
	var fov_slider := HSlider.new()
	fov_slider.min_value = 65.0
	fov_slider.max_value = 110.0
	fov_slider.step = 1.0
	fov_slider.value = GameSettings.base_fov
	fov_slider.value_changed.connect(func(val):
		GameSettings.base_fov = val
		lbl_fov.text = _tr_fmt("LBL_FOV", int(round(val)))
	)
	vbox_video.add_child(fov_slider)

	var lbl_scale := Label.new()
	lbl_scale.text = _tr_fmt("LBL_RENDER_SCALE", int(round(GameSettings.render_scale * 100.0)))
	vbox_video.add_child(lbl_scale)
	var slider_scale := HSlider.new()
	slider_scale.min_value = 0.5
	slider_scale.max_value = 1.0
	slider_scale.step = 0.05
	slider_scale.value = GameSettings.render_scale
	slider_scale.value_changed.connect(func(val):
		GameSettings.render_scale = val
		lbl_scale.text = _tr_fmt("LBL_RENDER_SCALE", int(round(val * 100.0)))
		GameSettings.apply_to_engine(get_viewport())
	)
	vbox_video.add_child(slider_scale)

	var chk_vsync := CheckBox.new()
	chk_vsync.text = tr("CHK_VSYNC")
	chk_vsync.button_pressed = GameSettings.vsync
	chk_vsync.toggled.connect(func(pressed):
		GameSettings.vsync = pressed
		GameSettings.apply_to_engine(get_viewport())
	)
	vbox_video.add_child(chk_vsync)

	# === ВКЛАДКА 3: АУДИО ===
	var scroll_audio := ScrollContainer.new()
	scroll_audio.name = tr("TAB_AUDIO")
	tabs.add_child(scroll_audio)
	var vbox_audio := VBoxContainer.new()
	vbox_audio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_audio.add_theme_constant_override("separation", 10)
	scroll_audio.add_child(vbox_audio)

	var lbl_vol := Label.new()
	lbl_vol.text = _tr_fmt("LBL_MASTER_VOL", int(round(GameSettings.master_volume * 100.0)))
	vbox_audio.add_child(lbl_vol)
	var audio_slider := HSlider.new()
	audio_slider.min_value = 0.0
	audio_slider.max_value = 1.0
	audio_slider.step = 0.02
	audio_slider.value = GameSettings.master_volume
	audio_slider.value_changed.connect(func(val):
		GameSettings.master_volume = val
		lbl_vol.text = _tr_fmt("LBL_MASTER_VOL", int(round(val * 100.0)))
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(val, 0.0001)))
	)
	vbox_audio.add_child(audio_slider)

	var chk_hit_snd := CheckBox.new()
	chk_hit_snd.text = tr("CHK_HIT_SOUND")
	chk_hit_snd.button_pressed = GameSettings.hitmarker_sound
	chk_hit_snd.toggled.connect(func(pressed): GameSettings.hitmarker_sound = pressed)
	vbox_audio.add_child(chk_hit_snd)

	# === ВКЛАДКА 4: РАСШИРЕНИЯ ===
	var scroll_ext := ScrollContainer.new()
	scroll_ext.name = tr("TAB_EXTENSIONS")
	tabs.add_child(scroll_ext)
	var vbox_ext := VBoxContainer.new()
	vbox_ext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_ext.add_theme_constant_override("separation", 10)
	scroll_ext.add_child(vbox_ext)

	var lbl_lang := Label.new()
	lbl_lang.text = tr("LBL_LANG")
	vbox_ext.add_child(lbl_lang)

	var opt_lang := OptionButton.new()
	opt_lang.add_item("Русский (RU)", 0)
	opt_lang.add_item("English (EN)", 1)
	opt_lang.selected = 1 if GameSettings.language == "en" else 0
	opt_lang.item_selected.connect(func(idx: int):
		var selected_lang := "en" if idx == 1 else "ru"
		GameSettings.set_language(selected_lang)

		# Пересобираем всё меню с новыми текстами и сразу открываем настройки обратно
		_rebuild_all_ui()
		_open_main_menu_settings()
		if settings_dialog:
			settings_dialog.show()
	)
	vbox_ext.add_child(opt_lang)
	vbox_ext.add_child(HSeparator.new())

	var chk_debug := CheckBox.new()
	chk_debug.text = tr("CHK_DEBUG_INFO")
	chk_debug.button_pressed = GameSettings.show_debug
	chk_debug.toggled.connect(func(pressed): GameSettings.show_debug = pressed)
	vbox_ext.add_child(chk_debug)

	var chk_ammo_3d := CheckBox.new()
	chk_ammo_3d.text = tr("CHK_AMMO_3D")
	chk_ammo_3d.button_pressed = GameSettings.show_ammo_3d
	chk_ammo_3d.toggled.connect(func(pressed): GameSettings.show_ammo_3d = pressed)
	vbox_ext.add_child(chk_ammo_3d)

	vbox_ext.add_child(HSeparator.new())
	var lbl_ms := Label.new()
	lbl_ms.text = "URL мастер-сервера (Интернет):"
	vbox_ext.add_child(lbl_ms)

	var edit_ms := LineEdit.new()
	edit_ms.text = GameSettings.master_server_url
	edit_ms.placeholder_text = "https://your-server.onrender.com"
	edit_ms.text_changed.connect(func(new_url): GameSettings.master_server_url = new_url.strip_edges())
	vbox_ext.add_child(edit_ms)

	main_vbox.add_child(HSeparator.new())
	var btn_close := Button.new()
	btn_close.text = tr("BTN_SAVE_CLOSE")
	btn_close.theme_type_variation = "AccentButton"
	btn_close.custom_minimum_size = Vector2(0, 42)
	btn_close.pressed.connect(func():
		GameSettings.save_to_disk()
		settings_dialog.hide()
	)
	main_vbox.add_child(btn_close)

func _tr_fmt(key: String, arg) -> String:
	var text: String = tr(key)
	if "%" in text:
		return text % arg
	return "%s: %s" % [key, str(arg)]
	
	
func _rebuild_all_ui() -> void:
	# 1. Удаляем старое окно настроек, если оно открыто
	if settings_dialog and is_instance_valid(settings_dialog):
		settings_dialog.queue_free()
		settings_dialog = null

	# 2. Удаляем старый CanvasLayer с меню
	for child in get_children():
		if child is CanvasLayer:
			child.queue_free()

	# 3. Заново собираем интерфейс с новыми переводами
	_build_ui()
