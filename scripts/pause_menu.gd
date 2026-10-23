class_name PauseMenuComponent
extends CanvasLayer

signal resumed
signal quit_requested
signal paused_toggled(is_paused: bool)

var is_paused: bool = false
var pause_card: Control = null
var settings_panel: Control = null
var extra_buttons_vbox: VBoxContainer = null
var target_player: Node = null

# Settings internal widgets
var option_aspect: OptionButton = null
var option_res: OptionButton = null
var current_res_list: Array = []
var option_fps: OptionButton = null
var btn_potato: Button = null
var is_potato_mode: bool = false
var saved_settings: Dictionary = {}

func _init() -> void:
	layer = 120

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func set_target_player(p: Node) -> void:
	target_player = p

func add_action_button(label: String, callback: Callable) -> Button:
	if not extra_buttons_vbox:
		return null
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 42)
	btn.theme = UITheme.build()
	btn.pressed.connect(callback)
	extra_buttons_vbox.add_child(btn)
	return btn

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if settings_panel and settings_panel.visible:
			_close_settings()
			get_viewport().set_input_as_handled()
		else:
			toggle_pause()
			get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	if is_paused:
		resume()
	else:
		open_pause()

func open_pause() -> void:
	is_paused = true
	if pause_card:
		pause_card.visible = true
		pause_card.mouse_filter = Control.MOUSE_FILTER_STOP
	if settings_panel:
		settings_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused_toggled.emit(true)

func resume() -> void:
	is_paused = false
	if pause_card:
		pause_card.visible = false
		pause_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if settings_panel:
		settings_panel.visible = false
		settings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var is_mob := _is_mobile()
	if not is_mob:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	paused_toggled.emit(false)
	resumed.emit()

func _open_settings() -> void:
	if pause_card:
		pause_card.visible = false
	if settings_panel:
		_update_settings_menu_size()
		settings_panel.visible = true
		settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP

func _close_settings() -> void:
	GameSettings.save_to_disk()
	if settings_panel:
		settings_panel.visible = false
		settings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_paused and pause_card:
		pause_card.visible = true
		pause_card.mouse_filter = Control.MOUSE_FILTER_STOP

func _quit_to_menu() -> void:
	quit_requested.emit()
	var stats = get_node_or_null("/root/GameStats")
	if stats and stats.has_method("reset_stats"):
		stats.reset_stats()

	var lan = get_node_or_null("/root/LanDiscovery")
	if lan and lan.has_method("stop_broadcast"):
		lan.stop_broadcast()

	var decals = get_node_or_null("/root/BulletDecals")
	if decals and decals.has_method("clear_all"):
		decals.clear_all()

	get_tree().paused = false
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager and net_manager.has_method("disconnect_peer"):
		net_manager.disconnect_peer()
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

# ========================================================
# ПОСТРОЕНИЕ ИНТЕРФЕЙСА
# ========================================================
func _build_ui() -> void:
	GameSettings.ensure_loaded()
	var theme_built := UITheme.build()

	# 1. КАРТОЧКА ПАУЗЫ
	pause_card = Control.new()
	pause_card.name = "PauseCard"
	pause_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_card.visible = false
	pause_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pause_card)

	var bg_dim := ColorRect.new()
	bg_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_dim.color = Color(0.04, 0.06, 0.09, 0.72)
	bg_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_card.add_child(bg_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	pause_card.add_child(center)

	var panel := PanelContainer.new()
	panel.theme = theme_built
	var is_mob := _is_mobile()
	panel.custom_minimum_size = Vector2(340 if is_mob else 380, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "⏸ ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24 if is_mob else 26)
	title.modulate = Color(1.0, 0.85, 0.4)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var btn_resume := Button.new()
	btn_resume.text = "▶  Продолжить"
	btn_resume.theme = theme_built
	btn_resume.theme_type_variation = "AccentButton"
	btn_resume.custom_minimum_size = Vector2(0, 46)
	btn_resume.pressed.connect(resume)
	vbox.add_child(btn_resume)

	extra_buttons_vbox = VBoxContainer.new()
	extra_buttons_vbox.add_theme_constant_override("separation", 10)
	vbox.add_child(extra_buttons_vbox)

	var btn_settings := Button.new()
	btn_settings.text = "⚙  Настройки"
	btn_settings.theme = theme_built
	btn_settings.custom_minimum_size = Vector2(0, 44)
	btn_settings.pressed.connect(_open_settings)
	vbox.add_child(btn_settings)

	var btn_quit := Button.new()
	btn_quit.text = "🚪  Выход в главное меню"
	btn_quit.theme = theme_built
	btn_quit.custom_minimum_size = Vector2(0, 44)
	btn_quit.modulate = Color(1.0, 0.45, 0.45)
	btn_quit.pressed.connect(_quit_to_menu)
	vbox.add_child(btn_quit)

	# 2. ПАНЕЛЬ НАСТРОЕК
	_build_settings_panel(theme_built)

func _build_settings_panel(theme_built: Theme) -> void:
	settings_panel = Control.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.visible = false
	settings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(settings_panel)

	var bg_dim := ColorRect.new()
	bg_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_dim.color = Color(0.04, 0.06, 0.09, 0.85)
	bg_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_panel.add_child(bg_dim)

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	settings_panel.add_child(center)

	var panel := PanelContainer.new()
	panel.theme = theme_built
	panel.name = "Panel"
	center.add_child(panel)

	_update_settings_menu_size()

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(main_vbox)

	var title := Label.new()
	title.text = "⚙  НАСТРОЙКИ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(1.0, 0.85, 0.4)
	main_vbox.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.theme = theme_built
	main_vbox.add_child(tabs)

	_build_input_tab(tabs)
	_build_graphics_tab(tabs)
	_build_crosshair_tab(tabs)
	_build_audio_tab(tabs)
	_build_extensions_tab(tabs)

	main_vbox.add_child(HSeparator.new())

	var btn_save := Button.new()
	btn_save.text = "💾  Сохранить и закрыть"
	btn_save.theme = theme_built
	btn_save.theme_type_variation = "AccentButton"
	btn_save.custom_minimum_size = Vector2(0, 44)
	btn_save.pressed.connect(_close_settings)
	main_vbox.add_child(btn_save)

func _update_settings_menu_size() -> void:
	if not settings_panel:
		return
	var center := settings_panel.get_node_or_null("CenterContainer")
	if center and center.get_child_count() > 0:
		var panel := center.get_child(0) as Control
		if panel:
			var vp := get_viewport()
			var vp_size: Vector2 = vp.get_visible_rect().size if vp else Vector2(1280, 720)
			var is_mob := _is_mobile()
			var w: float = minf(vp_size.x - 30.0, 580.0 if is_mob else 760.0)
			var h: float = maxf(vp_size.y - 40.0, 360.0)
			panel.custom_minimum_size = Vector2(w, h)

# --- ВКЛАДКА 1: УПРАВЛЕНИЕ ---
func _build_input_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Управление"
	tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var lbl_sens := Label.new()
	lbl_sens.text = "Чувствительность мыши: %.4f" % GameSettings.mouse_sensitivity
	vbox.add_child(lbl_sens)

	var sens_slider := HSlider.new()
	sens_slider.min_value = 0.0005
	sens_slider.max_value = 0.015
	sens_slider.step = 0.0005
	sens_slider.value = GameSettings.mouse_sensitivity
	sens_slider.value_changed.connect(func(val):
		GameSettings.mouse_sensitivity = val
		lbl_sens.text = "Чувствительность мыши: %.4f" % val
		if target_player:
			GameSettings.apply_to_player(target_player)
	)
	vbox.add_child(sens_slider)

	var lbl_ads_sens := Label.new()
	lbl_ads_sens.text = "Множитель в прицеле (ADS): %d%%" % int(round(GameSettings.ads_mouse_multiplier * 100.0))
	vbox.add_child(lbl_ads_sens)

	var ads_slider := HSlider.new()
	ads_slider.min_value = 0.1
	ads_slider.max_value = 1.0
	ads_slider.step = 0.05
	ads_slider.value = GameSettings.ads_mouse_multiplier
	ads_slider.value_changed.connect(func(val):
		GameSettings.ads_mouse_multiplier = val
		lbl_ads_sens.text = "Множитель в прицеле (ADS): %d%%" % int(round(val * 100.0))
		if target_player:
			GameSettings.apply_to_player(target_player)
	)
	vbox.add_child(ads_slider)

	var chk_inv := CheckBox.new()
	chk_inv.text = "Инверсия оси Y"
	chk_inv.button_pressed = GameSettings.invert_y
	chk_inv.toggled.connect(func(pressed):
		GameSettings.invert_y = pressed
		if target_player:
			GameSettings.apply_to_player(target_player)
	)
	vbox.add_child(chk_inv)

	var chk_crouch := CheckBox.new()
	chk_crouch.text = "Приседание по нажатию (Toggle вместо удержания)"
	chk_crouch.button_pressed = GameSettings.crouch_toggle_mode
	chk_crouch.toggled.connect(func(pressed):
		GameSettings.crouch_toggle_mode = pressed
		if target_player and "crouch_toggle_mode" in target_player:
			target_player.crouch_toggle_mode = pressed
	)
	vbox.add_child(chk_crouch)

	if _is_mobile():
		vbox.add_child(HSeparator.new())
		var lbl_tsens := Label.new()
		lbl_tsens.text = "Чувствительность тача: %.4f" % GameSettings.touch_sensitivity
		vbox.add_child(lbl_tsens)
		var tsens_slider := HSlider.new()
		tsens_slider.min_value = 0.001
		tsens_slider.max_value = 0.02
		tsens_slider.step = 0.0005
		tsens_slider.value = GameSettings.touch_sensitivity
		tsens_slider.value_changed.connect(func(val):
			GameSettings.touch_sensitivity = val
			lbl_tsens.text = "Чувствительность тача: %.4f" % val
			if target_player:
				GameSettings.apply_to_player(target_player)
		)
		vbox.add_child(tsens_slider)

		var lbl_steer := Label.new()
		lbl_steer.text = "Управление машиной на таче:"
		vbox.add_child(lbl_steer)
		var opt_steer := OptionButton.new()
		opt_steer.add_item("🔄 Поворотный руль", 0)
		opt_steer.add_item("◀ ▶ Кнопки влево / вправо", 1)
		opt_steer.selected = GameSettings.vehicle_touch_steering
		opt_steer.item_selected.connect(func(idx: int):
			GameSettings.vehicle_touch_steering = idx
			GameSettings.save_to_disk()
		)
		vbox.add_child(opt_steer)

# --- ВКЛАДКА 2: ГРАФИКА ---
func _build_graphics_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Графика"
	tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var chk_fs := CheckBox.new()
	chk_fs.text = "Полноэкранный режим"
	chk_fs.button_pressed = GameSettings.fullscreen
	chk_fs.toggled.connect(func(pressed):
		GameSettings.fullscreen = pressed
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(chk_fs)

	var lbl_aspect := Label.new()
	lbl_aspect.text = "Соотношение сторон:"
	vbox.add_child(lbl_aspect)
	option_aspect = OptionButton.new()
	option_aspect.add_item("Автоматически (По экрану)", 0)
	option_aspect.add_item("16:9", 1)
	option_aspect.add_item("16:10", 2)
	option_aspect.add_item("4:3", 3)
	option_aspect.add_item("21:9", 4)
	option_aspect.selected = GameSettings.aspect_index
	vbox.add_child(option_aspect)

	var lbl_res := Label.new()
	lbl_res.text = "Разрешение экрана:"
	vbox.add_child(lbl_res)
	option_res = OptionButton.new()
	vbox.add_child(option_res)

	option_aspect.item_selected.connect(func(idx):
		GameSettings.aspect_index = idx
		_populate_resolutions(idx)
	)
	option_res.item_selected.connect(func(idx):
		GameSettings.res_index = idx
		if idx >= 0 and idx < current_res_list.size():
			_apply_resolution(current_res_list[idx])
	)
	_populate_resolutions(GameSettings.aspect_index)

	var lbl_scale := Label.new()
	lbl_scale.text = "Масштаб 3D рендера: %d%%" % int(round(GameSettings.render_scale * 100.0))
	vbox.add_child(lbl_scale)
	var slider_scale := HSlider.new()
	slider_scale.min_value = 0.5
	slider_scale.max_value = 1.0
	slider_scale.step = 0.05
	slider_scale.value = GameSettings.render_scale
	slider_scale.value_changed.connect(func(val):
		GameSettings.render_scale = val
		lbl_scale.text = "Масштаб 3D рендера: %d%%" % int(round(val * 100.0))
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(slider_scale)

	var lbl_sh := Label.new()
	lbl_sh.text = "Качество теней:"
	vbox.add_child(lbl_sh)
	var opt_sh := OptionButton.new()
	opt_sh.add_item("Отключены", 0)
	opt_sh.add_item("Низкие", 1)
	opt_sh.add_item("Средние", 2)
	opt_sh.add_item("Высокие", 3)
	opt_sh.selected = GameSettings.shadow_quality
	opt_sh.item_selected.connect(func(idx):
		GameSettings.shadow_quality = idx
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(opt_sh)

	var chk_glow := CheckBox.new()
	chk_glow.text = "Свечение (Bloom / Glow)"
	chk_glow.button_pressed = GameSettings.glow
	chk_glow.toggled.connect(func(pressed):
		GameSettings.glow = pressed
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(chk_glow)

	var chk_vsync := CheckBox.new()
	chk_vsync.text = "Вертикальная синхронизация (VSync)"
	chk_vsync.button_pressed = GameSettings.vsync
	chk_vsync.toggled.connect(func(pressed):
		GameSettings.vsync = pressed
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(chk_vsync)

	var lbl_fps := Label.new()
	lbl_fps.text = "Лимит FPS:"
	vbox.add_child(lbl_fps)
	option_fps = OptionButton.new()
	option_fps.add_item("Без лимита", 0)
	option_fps.add_item("30 FPS", 30)
	option_fps.add_item("60 FPS", 60)
	option_fps.add_item("120 FPS", 120)
	option_fps.add_item("144 FPS", 144)
	option_fps.selected = GameSettings.fps_limit_idx
	option_fps.item_selected.connect(func(idx):
		GameSettings.fps_limit_idx = idx
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(option_fps)

	btn_potato = Button.new()
	btn_potato.text = "Режим Ультра-Картошки: " + ("ВКЛ" if is_potato_mode else "ВЫКЛ")
	btn_potato.custom_minimum_size = Vector2(0, 40)
	btn_potato.pressed.connect(func():
		_toggle_potato()
		btn_potato.text = "Режим Ультра-Картошки: " + ("ВКЛ" if is_potato_mode else "ВЫКЛ")
	)
	vbox.add_child(btn_potato)

# --- ВКЛАДКА 3: ПРИЦЕЛ ---
func _build_crosshair_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Прицел"
	tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var lbl_col := Label.new()
	lbl_col.text = "Цвет прицела:"
	vbox.add_child(lbl_col)
	var opt_col := OptionButton.new()
	opt_col.add_item("Белый", 0)
	opt_col.add_item("Зелёный", 1)
	opt_col.add_item("Бирюзовый", 2)
	opt_col.add_item("Оранжевый", 3)
	opt_col.add_item("Жёлтый", 4)
	opt_col.selected = GameSettings.crosshair_color_idx
	opt_col.item_selected.connect(func(idx):
		GameSettings.crosshair_color_idx = idx
	)
	vbox.add_child(opt_col)

	var chk_dyn := CheckBox.new()
	chk_dyn.text = "Динамическое расширение прицела"
	chk_dyn.button_pressed = GameSettings.crosshair_dynamic
	chk_dyn.toggled.connect(func(pressed): GameSettings.crosshair_dynamic = pressed)
	vbox.add_child(chk_dyn)

# --- ВКЛАДКА 4: АУДИО ---
func _build_audio_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Аудио"
	tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var lbl_vol := Label.new()
	lbl_vol.text = "Общая громкость (Master): %d%%" % int(round(GameSettings.master_volume * 100.0))
	vbox.add_child(lbl_vol)

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
	vbox.add_child(audio_slider)

	var chk_hit := CheckBox.new()
	chk_hit.text = "Звуковой сигнал при попадании (Hitmarker)"
	chk_hit.button_pressed = GameSettings.hitmarker_sound
	chk_hit.toggled.connect(func(pressed): GameSettings.hitmarker_sound = pressed)
	vbox.add_child(chk_hit)

# --- ВКЛАДКА 5: РАСШИРЕНИЯ ---
func _build_extensions_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Расширения"
	tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var lbl_lang := Label.new()
	lbl_lang.text = "Язык интерфейса / Language:"
	vbox.add_child(lbl_lang)

	var opt_lang := OptionButton.new()
	opt_lang.add_item("Русский (RU)", 0)
	opt_lang.add_item("English (EN)", 1)
	opt_lang.selected = 1 if GameSettings.language == "en" else 0
	opt_lang.item_selected.connect(func(idx: int):
		var selected_lang := "en" if idx == 1 else "ru"
		GameSettings.set_language(selected_lang)
	)
	vbox.add_child(opt_lang)

	var lbl_tunnel := Label.new()
	lbl_tunnel.text = "Адрес туннеля playit.gg (для хоста):"
	vbox.add_child(lbl_tunnel)

	var edit_tunnel := LineEdit.new()
	edit_tunnel.text = GameSettings.playit_tunnel_address
	edit_tunnel.placeholder_text = "Авто (или 147.185.x.x:12345)"
	edit_tunnel.text_changed.connect(func(new_addr): GameSettings.playit_tunnel_address = new_addr.strip_edges())
	vbox.add_child(edit_tunnel)

# --- РАЗРЕШЕНИЯ И КАРТОШКА ---
func _populate_resolutions(aspect_idx: int) -> void:
	if not option_res:
		return
	option_res.clear()
	current_res_list.clear()

	var presets: Array = []
	match aspect_idx:
		1: presets = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
		2: presets = [Vector2i(1280, 800), Vector2i(1440, 900), Vector2i(1680, 1050), Vector2i(1920, 1200)]
		3: presets = [Vector2i(640, 480), Vector2i(800, 600), Vector2i(1024, 768), Vector2i(1280, 960)]
		4: presets = [Vector2i(2560, 1080), Vector2i(3440, 1440)]
		_:
			var scr_size: Vector2i = DisplayServer.screen_get_size()
			presets = [Vector2i(1280, 720), Vector2i(1920, 1080), scr_size]

	for res in presets:
		current_res_list.append(res)
		option_res.add_item("%d × %d" % [res.x, res.y])

	if GameSettings.res_index < current_res_list.size():
		option_res.selected = GameSettings.res_index
	else:
		option_res.selected = 0

func _apply_resolution(res: Vector2i) -> void:
	if not GameSettings.fullscreen:
		DisplayServer.window_set_size(res)

func _get_env() -> Environment:
	var we: WorldEnvironment = get_tree().root.find_child("WorldEnvironment", true, false)
	return we.environment if we else null

func _toggle_potato() -> void:
	is_potato_mode = not is_potato_mode
	var vp := get_viewport()
	if is_potato_mode:
		saved_settings = {
			"msaa": vp.msaa_3d if vp else 0,
			"scale": vp.scaling_3d_scale if vp else 1.0,
			"fps": Engine.max_fps
		}
		if vp:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = 0.5
		Engine.max_fps = 60
	else:
		if saved_settings.has("scale") and vp:
			vp.scaling_3d_scale = saved_settings["scale"]
			vp.msaa_3d = saved_settings["msaa"]
			Engine.max_fps = saved_settings["fps"]
