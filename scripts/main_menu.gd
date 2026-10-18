extends Control

var default_ip: String = "127.0.0.1"
var default_port: int = 7777

var menu: MenuManager
var screen_main: ScreenMain

@onready var ip_input: LineEdit = %IPInput
@onready var port_input: LineEdit = %PortInput
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var nick_edit: LineEdit = %NickEdit

var settings_dialog: Control = null

func _ready() -> void:
	GameSettings.apply_to_engine(get_viewport())
	# Инициализация значений по умолчанию
	ip_input.text = default_ip
	port_input.text = str(default_port)
	if nick_edit:
		nick_edit.max_length = 16
		nick_edit.placeholder_text = "Ваш ник"
		nick_edit.text = GameStats.local_nick

	# Подключение сигналов кнопок
	if host_button:
		host_button.pressed.connect(_on_host_pressed)
	if join_button:
		join_button.pressed.connect(_on_join_pressed)

	# Подписка на сетевые события из NetworkManager
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		net_manager.connection_failed.connect(_on_connection_failed)
		net_manager.server_disconnected.connect(_on_server_disconnected)
		net_manager.game_started.connect(_on_game_started)

	_build_ui()

func _build_ui() -> void:
	# Старый интерфейс только скрываем, не удаляем
	for child in get_children():
		if child is CanvasItem:
			child.visible = false

	var ui_layer := CanvasLayer.new()
	add_child(ui_layer)
	menu = MenuManager.new()
	ui_layer.add_child(menu)

	screen_main = ScreenMain.new()
	var screen_host := ScreenHost.new()
	var screen_join := ScreenJoin.new()
	var screen_lan := ScreenLan.new()
	
	menu.register("main", screen_main)
	menu.register("host", screen_host)
	menu.register("join", screen_join)
	menu.register("lan", screen_lan)

	_open_main_menu_settings()
	ui_layer.add_child(settings_dialog)

	for b in screen_main.find_children("*", "Button", true, false):
		if "Настройк" in b.text or "Setting" in b.text:
			for conn in b.pressed.get_connections():
				b.pressed.disconnect(conn["callable"])
			b.pressed.connect(func(): settings_dialog.show())

	screen_host.host_requested.connect(_on_host_requested)
	screen_join.join_requested.connect(_on_join_requested)
	screen_lan.join_requested.connect(_on_join_requested)

	menu.show_screen("main")
	screen_main.nick_edit.text = GameStats.local_nick

func _on_host_requested(port: int, room_name: String) -> void:
	GameStats.set_nick(screen_main.get_nick())
	if port <= 0:
		menu.set_status("Статус: Укажите корректный порт!", true)
		return

	menu.set_status("Статус: Запуск сервера...")
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		var err: Error = net_manager.host_game(port)
		if err == OK:
			LanDiscovery.start_broadcast(room_name, port)
		else:
			menu.set_status("Статус: Ошибка создания сервера!", true)

func _on_join_requested(ip: String, port: int) -> void:
	GameStats.set_nick(screen_main.get_nick())
	if ip.is_empty() or port <= 0:
		menu.set_status("Статус: Введите валидные IP и порт!", true)
		return

	menu.set_status("Статус: Подключение к %s:%d..." % [ip, port])
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		var err: Error = net_manager.join_game(ip, port)
		if err != OK:
			menu.set_status("Статус: Ошибка подключения!", true)

func _on_connection_failed() -> void:
	if menu:
		menu.set_status("Статус: Не удалось подключиться к серверу!", true)
	else:
		status_label.text = "Статус: Не удалось подключиться к серверу!"
	_set_ui_disabled(false)

func _on_server_disconnected() -> void:
	if menu:
		menu.set_status("Статус: Соединение с сервером разорвано.", true)
	else:
		status_label.text = "Статус: Соединение с сервером разорвано."
	_set_ui_disabled(false)

func _on_game_started() -> void:
	if menu:
		menu.set_status("Статус: Соединение установлено!")
	else:
		status_label.text = "Статус: Соединение установлено!"
	get_tree().change_scene_to_file("res://scenes/arena.tscn")

func _set_ui_disabled(disabled: bool) -> void:
	if host_button:
		host_button.disabled = disabled
	if join_button:
		join_button.disabled = disabled
	if ip_input:
		ip_input.editable = !disabled
	if port_input:
		port_input.editable = !disabled

func _on_host_pressed() -> void:
	pass

func _on_join_pressed() -> void:
	pass

func _on_settings_pressed() -> void:
	_open_main_menu_settings()

func _open_main_menu_settings() -> void:
	if settings_dialog and is_instance_valid(settings_dialog):
		settings_dialog.show()
		return

	GameSettings.ensure_loaded()
	settings_dialog = PanelContainer.new()
	settings_dialog.theme = UITheme.build()
	settings_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	settings_dialog.custom_minimum_size = Vector2(680, 520)
	settings_dialog.offset_left = -340
	settings_dialog.offset_top = -260
	settings_dialog.offset_right = 340
	settings_dialog.offset_bottom = 260
	settings_dialog.visible = false

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	settings_dialog.add_child(main_vbox)

	var title := Label.new()
	title.text = "Настройки"
	title.theme_type_variation = "HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tabs)

	# === ВКЛАДКА 1: УПРАВЛЕНИЕ ===
	var scroll_input := ScrollContainer.new()
	scroll_input.name = "Управление"
	tabs.add_child(scroll_input)
	var vbox_input := VBoxContainer.new()
	vbox_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_input.add_theme_constant_override("separation", 10)
	scroll_input.add_child(vbox_input)

	var lbl_sens := Label.new()
	lbl_sens.text = "Чувствительность мыши: %.4f" % GameSettings.mouse_sensitivity
	vbox_input.add_child(lbl_sens)
	var sens_slider := HSlider.new()
	sens_slider.min_value = 0.0005
	sens_slider.max_value = 0.015
	sens_slider.step = 0.0005
	sens_slider.value = GameSettings.mouse_sensitivity
	sens_slider.value_changed.connect(func(val):
		GameSettings.mouse_sensitivity = val
		lbl_sens.text = "Чувствительность мыши: %.4f" % val
	)
	vbox_input.add_child(sens_slider)

	var lbl_ads_sens := Label.new()
	lbl_ads_sens.text = "Множитель чувствительности в прицеле (ADS): %d%%" % int(round(GameSettings.ads_mouse_multiplier * 100.0))
	vbox_input.add_child(lbl_ads_sens)
	var ads_slider := HSlider.new()
	ads_slider.min_value = 0.1
	ads_slider.max_value = 1.0
	ads_slider.step = 0.05
	ads_slider.value = GameSettings.ads_mouse_multiplier
	ads_slider.value_changed.connect(func(val):
		GameSettings.ads_mouse_multiplier = val
		lbl_ads_sens.text = "Множитель чувствительности в прицеле (ADS): %d%%" % int(round(val * 100.0))
	)
	vbox_input.add_child(ads_slider)

	var chk_inv := CheckBox.new()
	chk_inv.text = "Инверсия оси Y"
	chk_inv.button_pressed = GameSettings.invert_y
	chk_inv.toggled.connect(func(p): GameSettings.invert_y = p)
	vbox_input.add_child(chk_inv)

	var chk_crouch := CheckBox.new()
	chk_crouch.text = "Приседание по нажатию (Toggle вместо удержания)"
	chk_crouch.button_pressed = GameSettings.crouch_toggle_mode
	chk_crouch.toggled.connect(func(p): GameSettings.crouch_toggle_mode = p)
	vbox_input.add_child(chk_crouch)

	# === ВКЛАДКА 2: ГРАФИКА ===
	var scroll_video := ScrollContainer.new()
	scroll_video.name = "Графика"
	tabs.add_child(scroll_video)
	var vbox_video := VBoxContainer.new()
	vbox_video.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_video.add_theme_constant_override("separation", 10)
	scroll_video.add_child(vbox_video)

	var chk_fs := CheckBox.new()
	chk_fs.text = "Полноэкранный режим"
	chk_fs.button_pressed = GameSettings.fullscreen
	chk_fs.toggled.connect(func(p):
		GameSettings.fullscreen = p
		GameSettings.apply_to_engine(get_viewport())
	)
	vbox_video.add_child(chk_fs)

	var lbl_ui_sc := Label.new()
	lbl_ui_sc.text = "Масштаб интерфейса (UI Scale): %d%%" % int(round(GameSettings.ui_scale * 100.0))
	vbox_video.add_child(lbl_ui_sc)
	var ui_sc_slider := HSlider.new()
	ui_sc_slider.min_value = 0.75
	ui_sc_slider.max_value = 2.0
	ui_sc_slider.step = 0.05
	ui_sc_slider.value = GameSettings.ui_scale
	ui_sc_slider.value_changed.connect(func(val):
		GameSettings.ui_scale = val
		lbl_ui_sc.text = "Масштаб интерфейса (UI Scale): %d%%" % int(round(val * 100.0))
		GameSettings.apply_to_engine(get_viewport())
	)
	vbox_video.add_child(ui_sc_slider)

	var lbl_fov := Label.new()
	lbl_fov.text = "Угол обзора (FOV): %d°" % int(round(GameSettings.base_fov))
	vbox_video.add_child(lbl_fov)
	var fov_slider := HSlider.new()
	fov_slider.min_value = 65.0
	fov_slider.max_value = 110.0
	fov_slider.step = 1.0
	fov_slider.value = GameSettings.base_fov
	fov_slider.value_changed.connect(func(val):
		GameSettings.base_fov = val
		lbl_fov.text = "Угол обзора (FOV): %d°" % int(round(val))
	)
	vbox_video.add_child(fov_slider)

	var lbl_up := Label.new()
	lbl_up.text = "Режим 3D масштабирования (Upscaler):"
	vbox_video.add_child(lbl_up)
	var opt_upscale := OptionButton.new()
	opt_upscale.add_item("Bilinear (Стандартный)", 0)
	opt_upscale.add_item("AMD FSR 1.0 (Чёткий апскейл)", 1)
	opt_upscale.selected = GameSettings.scaling_mode
	opt_upscale.item_selected.connect(func(idx):
		GameSettings.scaling_mode = idx
		GameSettings.apply_to_engine(get_viewport())
	)
	vbox_video.add_child(opt_upscale)

	var lbl_fsr := Label.new()
	lbl_fsr.text = "Резкость FSR: %d%%" % int(round(GameSettings.fsr_sharpness * 50.0))
	vbox_video.add_child(lbl_fsr)
	var slider_fsr := HSlider.new()
	slider_fsr.min_value = 0.0
	slider_fsr.max_value = 2.0
	slider_fsr.step = 0.1
	slider_fsr.value = GameSettings.fsr_sharpness
	slider_fsr.value_changed.connect(func(val):
		GameSettings.fsr_sharpness = val
		lbl_fsr.text = "Резкость FSR: %d%%" % int(round(val * 50.0))
		GameSettings.apply_to_engine(get_viewport())
	)
	vbox_video.add_child(slider_fsr)

	var lbl_scale := Label.new()
	lbl_scale.text = "Масштаб 3D рендера: %d%%" % int(round(GameSettings.render_scale * 100.0))
	vbox_video.add_child(lbl_scale)
	var sl_scale := HSlider.new()
	sl_scale.min_value = 0.5
	sl_scale.max_value = 1.0
	sl_scale.step = 0.05
	sl_scale.value = GameSettings.render_scale
	sl_scale.value_changed.connect(func(val):
		GameSettings.render_scale = val
		lbl_scale.text = "Масштаб 3D рендера: %d%%" % int(round(val * 100.0))
		GameSettings.apply_to_engine(get_viewport())
	)
	vbox_video.add_child(sl_scale)

	var lbl_sh := Label.new()
	lbl_sh.text = "Качество теней:"
	vbox_video.add_child(lbl_sh)
	var opt_sh := OptionButton.new()
	opt_sh.add_item("Отключены", 0)
	opt_sh.add_item("Низкие", 1)
	opt_sh.add_item("Средние", 2)
	opt_sh.add_item("Высокие", 3)
	opt_sh.selected = GameSettings.shadow_quality
	opt_sh.item_selected.connect(func(idx):
		GameSettings.shadow_quality = idx
		GameSettings.apply_to_engine(get_viewport())
	)
	vbox_video.add_child(opt_sh)

	var chk_vs := CheckBox.new()
	chk_vs.text = "Вертикальная синхронизация (VSync)"
	chk_vs.button_pressed = GameSettings.vsync
	chk_vs.toggled.connect(func(p):
		GameSettings.vsync = p
		GameSettings.apply_to_engine(get_viewport())
	)
	vbox_video.add_child(chk_vs)

	var chk_glow_box := CheckBox.new()
	chk_glow_box.text = "Свечение (Bloom / Glow)"
	chk_glow_box.button_pressed = GameSettings.glow
	chk_glow_box.toggled.connect(func(p): GameSettings.glow = p)
	vbox_video.add_child(chk_glow_box)

	# --- ВКЛАДКА 3: ПРИЦЕЛ ---
	var scroll_ch := ScrollContainer.new()
	scroll_ch.name = "Прицел"
	tabs.add_child(scroll_ch)
	var vbox_ch := VBoxContainer.new()
	vbox_ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_ch.add_theme_constant_override("separation", 10)
	scroll_ch.add_child(vbox_ch)

	var lbl_ch_col := Label.new()
	lbl_ch_col.text = "Цвет прицела:"
	vbox_ch.add_child(lbl_ch_col)
	var opt_ch_col := OptionButton.new()
	opt_ch_col.add_item("Белый", 0)
	opt_ch_col.add_item("Зелёный", 1)
	opt_ch_col.add_item("Бирюзовый", 2)
	opt_ch_col.add_item("Оранжевый", 3)
	opt_ch_col.add_item("Жёлтый", 4)
	opt_ch_col.selected = GameSettings.crosshair_color_idx
	opt_ch_col.item_selected.connect(func(idx): GameSettings.crosshair_color_idx = idx)
	vbox_ch.add_child(opt_ch_col)

	var lbl_ch_sz := Label.new()
	lbl_ch_sz.text = "Масштаб прицела: %d%%" % int(round(GameSettings.crosshair_scale * 100.0))
	vbox_ch.add_child(lbl_ch_sz)
	var sl_ch_sz := HSlider.new()
	sl_ch_sz.min_value = 0.5
	sl_ch_sz.max_value = 2.0
	sl_ch_sz.step = 0.1
	sl_ch_sz.value = GameSettings.crosshair_scale
	sl_ch_sz.value_changed.connect(func(val):
		GameSettings.crosshair_scale = val
		lbl_ch_sz.text = "Масштаб прицела: %d%%" % int(round(val * 100.0))
	)
	vbox_ch.add_child(sl_ch_sz)

	var chk_ch_dyn := CheckBox.new()
	chk_ch_dyn.text = "Динамическое расширение прицела при стрельбе и беге"
	chk_ch_dyn.button_pressed = GameSettings.crosshair_dynamic
	chk_ch_dyn.toggled.connect(func(p): GameSettings.crosshair_dynamic = p)
	vbox_ch.add_child(chk_ch_dyn)

	# --- ВКЛАДКА 4: АУДИО ---
	var scroll_audio := ScrollContainer.new()
	scroll_audio.name = "Аудио"
	tabs.add_child(scroll_audio)
	var vbox_audio := VBoxContainer.new()
	vbox_audio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_audio.add_theme_constant_override("separation", 10)
	scroll_audio.add_child(vbox_audio)

	var lbl_vol := Label.new()
	lbl_vol.text = "Общая громкость (Master): %d%%" % int(round(GameSettings.master_volume * 100.0))
	vbox_audio.add_child(lbl_vol)
	var audio_slider := HSlider.new()
	audio_slider.min_value = 0.0
	audio_slider.max_value = 1.0
	audio_slider.step = 0.02
	audio_slider.value = GameSettings.master_volume
	audio_slider.value_changed.connect(func(val):
		GameSettings.master_volume = val
		lbl_vol.text = "Общая громкость (Master): %d%%" % int(round(val * 100.0))
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(val, 0.0001)))
	)
	vbox_audio.add_child(audio_slider)

	var chk_hit_snd := CheckBox.new()
	chk_hit_snd.text = "Звуковой сигнал при попадании (Hitmarker)"
	chk_hit_snd.button_pressed = GameSettings.hitmarker_sound
	chk_hit_snd.toggled.connect(func(p): GameSettings.hitmarker_sound = p)
	vbox_audio.add_child(chk_hit_snd)

	# === ВКЛАДКА 5: РАСШИРЕНИЯ ===
	var scroll_ext := ScrollContainer.new()
	scroll_ext.name = "Расширения"
	tabs.add_child(scroll_ext)
	var vbox_ext := VBoxContainer.new()
	vbox_ext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_ext.add_theme_constant_override("separation", 10)
	scroll_ext.add_child(vbox_ext)

	var chk_debug := CheckBox.new()
	chk_debug.text = "Панель отладки (Debug Info: FPS, Ping, Loss)"
	chk_debug.button_pressed = GameSettings.show_debug
	chk_debug.toggled.connect(func(p): GameSettings.show_debug = p)
	vbox_ext.add_child(chk_debug)

	var chk_ammo_3d := CheckBox.new()
	chk_ammo_3d.text = "Показывать патроны на оружии (3D вместо HUD)"
	chk_ammo_3d.button_pressed = GameSettings.show_ammo_3d
	chk_ammo_3d.toggled.connect(func(p): GameSettings.show_ammo_3d = p)
	vbox_ext.add_child(chk_ammo_3d)

	main_vbox.add_child(HSeparator.new())
	var btn_close := Button.new()
	btn_close.text = "Сохранить и закрыть"
	btn_close.theme_type_variation = "AccentButton"
	btn_close.custom_minimum_size = Vector2(0, 42)
	btn_close.pressed.connect(func():
		GameSettings.save_to_disk()
		settings_dialog.hide()
	)
	main_vbox.add_child(btn_close)
