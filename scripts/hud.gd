extends CanvasLayer

@onready var health_bar: ProgressBar = %HealthBar if has_node("%HealthBar") else null
@onready var ammo_label: Label = %AmmoLabel if has_node("%AmmoLabel") else null
@onready var disconnect_label: Label = get_node("../DisconnectLabel") if has_node("../DisconnectLabel") else null
@onready var crosshair: Control = %Crosshair if has_node("%Crosshair") else null
@onready var touch_overlay: Control = $TouchOverlay if has_node("TouchOverlay") else null
@onready var fps_label: Label = $TouchOverlay/HUDContainer/FPSLabel

var player: CharacterBody3D
var current_spread: float = 6.0
var hit_flash_timer: float = 0.0
var crosshair_view: CrosshairView

var viewmodel: ViewmodelRenderer

var scoreboard: Scoreboard
var kill_feed: KillFeed

var pause_menu: Control
var settings_menu: Control
var audio_slider: HSlider
var is_paused: bool = false
var debug_label: Label
var weapon_button: Button

const MOBILE_HUD_CFG_PATH: String = "user://mobile_hud.cfg"
var mobile_controls_layer: Control = null
var mobile_btn_nodes: Dictionary = {} # id -> Control
var mobile_btn_defaults: Dictionary = {} # id -> { "offset": Vector2, "scale": float }
var hud_editor_panel: Control = null
var is_editing_hud: bool = false
var selected_hud_btn_id: String = ""
var hud_scale_slider: HSlider = null
var _dragging_btn_id: String = ""
var _drag_offset: Vector2 = Vector2.ZERO

# Переменные для сбора статистики FPS
var _fps_samples: Array[float] = []
var _fps_timer: float = 0.0
var _min_fps: int = 999
var _max_fps: int = 0
var _avg_fps: int = 0

# --- Элементы настроек (поля класса, чтобы лямбды не работали с копиями) ---
var chk_fullscreen: CheckBox
var chk_vsync: CheckBox
var option_msaa: OptionButton
var chk_glow: CheckBox
var slider_scale: HSlider
var chk_fxaa: CheckBox
var chk_ssao: CheckBox
var chk_ssr: CheckBox
var chk_fps: CheckBox
var btn_potato: Button
var option_fps: OptionButton
var option_aspect: OptionButton
var option_res: OptionButton
var current_res_list: Array[Vector2i] = []

# --- Режим картошки ---
var is_potato_mode: bool = false
var saved_settings: Dictionary = {}

func _ready() -> void:
	player = owner if owner is CharacterBody3D else get_parent()

	if not player or not player.is_multiplayer_authority():
		queue_free()
		return

	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	if player.has_signal("ammo_changed"):
		player.ammo_changed.connect(_on_ammo_changed)
	if player.has_signal("hit_target"):
		player.hit_target.connect(_on_hit_target)
	if player.has_signal("weapon_changed"):
		player.weapon_changed.connect(_on_weapon_changed)

	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		net_manager.server_disconnected.connect(_on_server_disconnected_ui)

	_on_health_changed(player.health)
	_on_ammo_changed(player.current_ammo, player.reserve_ammo)

	# Старые кнопки прыжка и огня скрываем всегда (вместо них новые SVG-кнопки), джойстик оставляем на мобильных
	if has_node("TouchOverlay/JumpButton"): $TouchOverlay/JumpButton.hide()
	if has_node("TouchOverlay/FireButton"): $TouchOverlay/FireButton.hide()
	if _is_mobile():
		if has_node("TouchOverlay/JoystickBase"): $TouchOverlay/JoystickBase.show()
	else:
		if has_node("TouchOverlay/JoystickBase"): $TouchOverlay/JoystickBase.hide()

	_build_pause_menu()
	_build_hud_elements()

	scoreboard = Scoreboard.new()
	add_child(scoreboard)
	kill_feed = KillFeed.new()
	add_child(kill_feed)
	if crosshair:
		crosshair.visible = false
	crosshair_view = CrosshairView.new()
	crosshair_view.player = player
	add_child(crosshair_view)
	#if weapon_root_node:
		#viewmodel = ViewmodelRenderer.new()
		#add_child(viewmodel)
		#move_child(viewmodel, 0)  # рисовать под HUD
		#viewmodel.setup(weapon_root_node)
	#else:
		#push_warning("ViewmodelRenderer: узел оружия не найден, проверь путь")

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"] or ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse")

# Environment может лежать в WorldEnvironment, а не в камере
func _get_env() -> Environment:
	var cam = get_viewport().get_camera_3d()
	if cam and cam.environment:
		return cam.environment
	var we = get_tree().root.find_child("WorldEnvironment", true, false)
	if we is WorldEnvironment:
		return we.environment
	return null

func _build_hud_elements() -> void:
	var hud_container = $TouchOverlay/HUDContainer if has_node("TouchOverlay/HUDContainer") else self
	var is_mobile = _is_mobile()

	# Debug-панель (Top Right): FPS, Avg, Min/Max, Ping, Loss
	debug_label = Label.new()
	debug_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	debug_label.offset_left = -260
	debug_label.offset_top = 10
	debug_label.offset_right = -15
	debug_label.offset_bottom = 120
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.text = "DEBUG INFO"
	debug_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 0.9))
	debug_label.add_theme_font_size_override("font_size", 14)
	hud_container.add_child(debug_label)
	debug_label.visible = false

	# Верхняя панель служебных кнопок для телефона (Меню и Таблица)
	var top_bar = HBoxContainer.new()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	top_bar.offset_left = 20
	top_bar.offset_top = 16
	top_bar.offset_right = 280
	top_bar.offset_bottom = 58
	top_bar.add_theme_constant_override("separation", 10)
	top_bar.visible = is_mobile
	self.add_child(top_bar)

	var btn_menu = Button.new()
	btn_menu.text = "Меню"
	btn_menu.custom_minimum_size = Vector2(110, 40)
	btn_menu.pressed.connect(_toggle_pause)
	top_bar.add_child(btn_menu)

	var btn_score = Button.new()
	btn_score.text = "Таблица"
	btn_score.toggle_mode = true
	btn_score.custom_minimum_size = Vector2(110, 40)
	btn_score.toggled.connect(func(pressed):
		if scoreboard:
			scoreboard.pinned = pressed
	)
	top_bar.add_child(btn_score)

	# Контейнер боевых SVG-кнопок для Android/iOS
	mobile_controls_layer = Control.new()
	mobile_controls_layer.name = "MobileControlsLayer"
	mobile_controls_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mobile_controls_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mobile_controls_layer.visible = is_mobile
	self.add_child(mobile_controls_layer)

	# Создаём 6 кнопок-иконок в правом нижнем углу (относительно правого нижнего угла экрана)
	# Формат: id, путь к иконке, смещение от правого нижнего угла, базовый размер
	_create_mobile_icon_button("fire", "res://gui/shoot.svg", Vector2(-210, -200), Vector2(110, 110))
	_create_mobile_icon_button("ads", "res://gui/aim.svg", Vector2(-115, -310), Vector2(78, 78))
	_create_mobile_icon_button("jump", "res://gui/jump.svg", Vector2(-235, -315), Vector2(78, 78))
	_create_mobile_icon_button("crouch", "res://gui/crouch.svg", Vector2(-335, -135), Vector2(78, 78))
	_create_mobile_icon_button("reload", "res://gui/reload.svg", Vector2(-330, -245), Vector2(72, 72))
	_create_mobile_icon_button("cycle_weapon", "res://gui/change_weapon.svg", Vector2(-180, -405), Vector2(72, 72))

	_load_mobile_hud_layout()
	_build_hud_layout_editor()

func _input(event: InputEvent) -> void:
	if not player or not player.is_multiplayer_authority():
		return
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()

func _toggle_pause() -> void:
	is_paused = !is_paused
	if pause_menu:
		pause_menu.visible = is_paused
		pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP if is_paused else Control.MOUSE_FILTER_IGNORE
	if crosshair_view:
		crosshair_view.visible = not is_paused
	if crosshair:
		crosshair.visible = false
	if is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_tree().paused = false
		if settings_menu:
			settings_menu.hide()
			settings_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_pause_menu() -> void:
	pause_menu = Control.new()
	pause_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	pause_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_menu.add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_menu.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 200)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var btn_resume = Button.new()
	btn_resume.text = "Продолжить"
	btn_resume.pressed.connect(_toggle_pause)
	vbox.add_child(btn_resume)

	var btn_settings = Button.new()
	btn_settings.text = "Настройки"
	btn_settings.pressed.connect(func():
		if settings_menu:
			settings_menu.show()
			settings_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	)
	vbox.add_child(btn_settings)

	var btn_quit = Button.new()
	btn_quit.text = "Выход в меню"
	btn_quit.pressed.connect(func():
		GameStats.reset_stats()
		LanDiscovery.stop_broadcast()
		BulletDecals.clear_all()
		get_tree().paused = false
		var net_manager = get_node_or_null("/root/NetworkManager")
		if net_manager:
			net_manager.disconnect_peer()
		else:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	vbox.add_child(btn_quit)

	add_child(pause_menu)
	_build_settings_menu()

func _build_settings_menu() -> void:
	settings_menu = Control.new()
	settings_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	settings_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_menu.visible = false
	settings_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.08, 0.9)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_menu.add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_menu.add_child(center)

	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(520, 520)
	center.add_child(main_vbox)

	var title = Label.new()
	title.text = "НАСТРОЙКИ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	main_vbox.add_child(title)

	var tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(500, 420)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tabs)

	# --- ВКЛАДКА 1: УПРАВЛЕНИЕ ---
	var scroll_input = ScrollContainer.new()
	scroll_input.name = "Управление"
	tabs.add_child(scroll_input)

	var vbox_input = VBoxContainer.new()
	vbox_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_input.add_child(vbox_input)

	var lbl_sens = Label.new()
	lbl_sens.text = "Чувствительность мыши"
	vbox_input.add_child(lbl_sens)

	var sens_slider = HSlider.new()
	sens_slider.min_value = 0.0005
	sens_slider.max_value = 0.01
	sens_slider.step = 0.0002
	sens_slider.value = player.mouse_sensitivity if player else 0.003
	sens_slider.value_changed.connect(func(val):
		if player: player.mouse_sensitivity = val
	)
	vbox_input.add_child(sens_slider)

	var lbl_ads_sens = Label.new()
	lbl_ads_sens.text = "Множитель чувствительности в прицеле (ADS)"
	vbox_input.add_child(lbl_ads_sens)

	var ads_slider = HSlider.new()
	ads_slider.min_value = 0.1
	ads_slider.max_value = 1.5
	ads_slider.step = 0.05
	ads_slider.value = player.ads_mouse_multiplier if player and "ads_mouse_multiplier" in player else 0.6
	ads_slider.value_changed.connect(func(val):
		if player and "ads_mouse_multiplier" in player:
			player.ads_mouse_multiplier = val
	)
	vbox_input.add_child(ads_slider)

	var chk_crouch_mode = CheckBox.new()
	chk_crouch_mode.text = "Приседание по нажатию (Toggle вместо удержания)"
	chk_crouch_mode.button_pressed = player.crouch_toggle_mode if player and "crouch_toggle_mode" in player else false
	chk_crouch_mode.toggled.connect(func(pressed):
		if player and "crouch_toggle_mode" in player:
			player.crouch_toggle_mode = pressed
			player._crouch_toggled = false
			player.touch_crouch = false
	)
	vbox_input.add_child(chk_crouch_mode)

	if _is_mobile():
		vbox_input.add_child(HSeparator.new())
		var lbl_mob = Label.new()
		lbl_mob.text = "Сенсорное управление:"
		vbox_input.add_child(lbl_mob)

		var btn_edit_hud = Button.new()
		btn_edit_hud.text = "Настроить расположение и размер кнопок"
		btn_edit_hud.custom_minimum_size = Vector2(0, 42)
		btn_edit_hud.pressed.connect(func():
			_open_hud_editor()
		)
		vbox_input.add_child(btn_edit_hud)
	else:
		vbox_input.add_child(HSeparator.new())
		var lbl_rebind = Label.new()
		lbl_rebind.text = "Переназначение клавиш (нажми кнопку, затем нужную клавишу):"
		vbox_input.add_child(lbl_rebind)

		var rebind_actions = [
			{"action": "move_forward", "label": "Вперёд"},
			{"action": "move_back", "label": "Назад"},
			{"action": "move_left", "label": "Влево"},
			{"action": "move_right", "label": "Вправо"},
			{"action": "ui_accept", "label": "Прыжок"},
			{"action": "crouch", "label": "Приседание"},
			{"action": "sprint", "label": "Спринт"},
			{"action": "reload", "label": "Перезарядка"},
			{"action": "fire", "label": "Огонь"},
			{"action": "ads", "label": "Прицел"}
		]

		for item in rebind_actions:
			var act_name = item["action"]
			var row = HBoxContainer.new()
			var action_label = Label.new()
			action_label.text = item["label"]
			action_label.custom_minimum_size = Vector2(180, 0)
			row.add_child(action_label)

			var btn_key = Button.new()
			btn_key.custom_minimum_size = Vector2(160, 32)
			btn_key.text = _get_action_key_name(act_name)
			btn_key.pressed.connect(_start_key_rebind.bind(act_name, btn_key))
			row.add_child(btn_key)
			vbox_input.add_child(row)

	# --- ВКЛАДКА 2: ГРАФИКА ---
	var scroll_video = ScrollContainer.new()
	scroll_video.name = "Графика"
	tabs.add_child(scroll_video)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_video.add_child(vbox)

	chk_fullscreen = CheckBox.new()
	chk_fullscreen.text = "Полноэкранный режим"
	chk_fullscreen.button_pressed = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	chk_fullscreen.toggled.connect(func(pressed):
		if pressed:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if option_res and option_res.selected >= 0 and option_res.selected < current_res_list.size():
			_apply_game_resolution(current_res_list[option_res.selected])
	)
	vbox.add_child(chk_fullscreen)

	# Выбор соотношения сторон
	var lbl_aspect = Label.new()
	lbl_aspect.text = "Соотношение сторон:"
	vbox.add_child(lbl_aspect)

	option_aspect = OptionButton.new()
	option_aspect.add_item("Автоматически (По экрану)", 0)
	option_aspect.add_item("16:9 (Широкоэкранный)", 1)
	option_aspect.add_item("16:10", 2)
	option_aspect.add_item("4:3 (Вплоть до 640x480)", 3)
	option_aspect.add_item("21:9 (Ультраширокий)", 4)
	vbox.add_child(option_aspect)

	# Выбор разрешения экрана
	var lbl_res = Label.new()
	lbl_res.text = "Разрешение экрана:"
	vbox.add_child(lbl_res)

	option_res = OptionButton.new()
	vbox.add_child(option_res)

	option_aspect.item_selected.connect(func(idx):
		_populate_resolutions(idx)
	)
	option_res.item_selected.connect(func(idx):
		if idx >= 0 and idx < current_res_list.size():
			_apply_game_resolution(current_res_list[idx])
	)

	_populate_resolutions(0)

	chk_vsync = CheckBox.new()
	chk_vsync.text = "Вертикальная синхронизация (VSync)"
	chk_vsync.button_pressed = (DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED)
	chk_vsync.toggled.connect(func(pressed):
		if pressed:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		else:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	)
	vbox.add_child(chk_vsync)

	var lbl_msaa = Label.new()
	lbl_msaa.text = "Сглаживание (MSAA)"
	vbox.add_child(lbl_msaa)

	option_msaa = OptionButton.new()
	option_msaa.add_item("Отключено", Viewport.MSAA_DISABLED)
	option_msaa.add_item("2x MSAA", Viewport.MSAA_2X)
	option_msaa.add_item("4x MSAA", Viewport.MSAA_4X)
	option_msaa.add_item("8x MSAA", Viewport.MSAA_8X)
	option_msaa.selected = option_msaa.get_item_index(get_viewport().msaa_3d)
	option_msaa.item_selected.connect(func(index):
		get_viewport().msaa_3d = option_msaa.get_item_id(index)
	)
	vbox.add_child(option_msaa)

	chk_glow = CheckBox.new()
	chk_glow.text = "Свечение (Bloom / Glow)"
	var env_init = _get_env()
	chk_glow.button_pressed = env_init.glow_enabled if env_init else true
	chk_glow.toggled.connect(func(pressed):
		var env = _get_env()
		if env:
			env.glow_enabled = pressed
	)
	vbox.add_child(chk_glow)

	var lbl_scale = Label.new()
	lbl_scale.text = "Масштаб разрешения (Resolution Scale)"
	vbox.add_child(lbl_scale)

	slider_scale = HSlider.new()
	slider_scale.min_value = 0.35
	slider_scale.max_value = 1.0
	slider_scale.step = 0.05
	slider_scale.value = get_viewport().scaling_3d_scale
	slider_scale.value_changed.connect(func(val):
		get_viewport().scaling_3d_scale = val
	)
	vbox.add_child(slider_scale)

	chk_fxaa = CheckBox.new()
	chk_fxaa.text = "FXAA сглаживание"
	chk_fxaa.button_pressed = (get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA)
	chk_fxaa.toggled.connect(func(pressed):
		if pressed:
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		else:
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	)
	vbox.add_child(chk_fxaa)

	chk_ssao = CheckBox.new()
	chk_ssao.text = "Затенение окружения (SSAO)"
	chk_ssao.button_pressed = env_init.ssao_enabled if env_init else false
	chk_ssao.toggled.connect(func(pressed):
		var env = _get_env()
		if env:
			env.ssao_enabled = pressed
	)
	vbox.add_child(chk_ssao)

	chk_ssr = CheckBox.new()
	chk_ssr.text = "Отражения в пространстве экрана (SSR)"
	chk_ssr.button_pressed = env_init.ssr_enabled if env_init else false
	chk_ssr.toggled.connect(func(pressed):
		var env = _get_env()
		if env:
			env.ssr_enabled = pressed
	)
	vbox.add_child(chk_ssr)

	if OS.has_feature("mobile"):
		chk_ssao.hide()
		chk_ssr.hide()

	btn_potato = Button.new()
	btn_potato.text = "🥔 Режим Ультра-Картошка: Выкл"
	btn_potato.pressed.connect(_toggle_potato_mode)
	vbox.add_child(btn_potato)

	var lbl_limit_fps = Label.new()
	lbl_limit_fps.text = "Лимит кадров (FPS Limit):"
	vbox.add_child(lbl_limit_fps)

	option_fps = OptionButton.new()
	option_fps.add_item("Без ограничений (0)", 0)
	option_fps.add_item("30 FPS", 30)
	option_fps.add_item("60 FPS", 60)
	option_fps.add_item("120 FPS", 120)
	option_fps.add_item("144 FPS", 144)
	_sync_fps_option()
	option_fps.item_selected.connect(func(index):
		Engine.max_fps = option_fps.get_item_id(index)
	)
	vbox.add_child(option_fps)

	# --- ВКЛАДКА 3: АУДИО ---
	var scroll_audio = ScrollContainer.new()
	scroll_audio.name = "Аудио"
	tabs.add_child(scroll_audio)

	var vbox_audio = VBoxContainer.new()
	vbox_audio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_audio.add_child(vbox_audio)

	var lbl_audio = Label.new()
	lbl_audio.text = "Общая громкость:"
	vbox_audio.add_child(lbl_audio)

	audio_slider = HSlider.new()
	audio_slider.min_value = 0.0
	audio_slider.max_value = 1.0
	audio_slider.step = 0.05
	audio_slider.value = 1.0
	audio_slider.value_changed.connect(func(val):
		AudioServer.set_bus_volume_db(0, linear_to_db(val))
	)
	vbox_audio.add_child(audio_slider)

	main_vbox.add_child(HSeparator.new())

	var btn_back = Button.new()
	btn_back.text = "Назад"
	btn_back.custom_minimum_size = Vector2(0, 36)
	btn_back.pressed.connect(func():
		settings_menu.hide()
		settings_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)
	main_vbox.add_child(btn_back)
	
	# --- ВКЛАДКА 4: РАСШИРЕНИЯ ---
	var scroll_ext = ScrollContainer.new()
	scroll_ext.name = "Расширения"
	tabs.add_child(scroll_ext)

	var vbox_ext = VBoxContainer.new()
	vbox_ext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_ext.add_child(vbox_ext)

	var chk_debug = CheckBox.new()
	chk_debug.text = "Панель отладки (Debug Info: FPS, Ping, Loss)"
	chk_debug.button_pressed = debug_label.visible if debug_label else false
	chk_debug.toggled.connect(func(pressed):
		if debug_label:
			debug_label.visible = pressed
	)
	vbox_ext.add_child(chk_debug)

	var chk_ammo_3d = CheckBox.new()
	chk_ammo_3d.text = "Патроны на оружии (3D)"
	chk_ammo_3d.button_pressed = player.show_ammo_on_weapon if player and "show_ammo_on_weapon" in player else false
	chk_ammo_3d.toggled.connect(func(pressed):
		if player and "show_ammo_on_weapon" in player:
			player.show_ammo_on_weapon = pressed
			if ammo_label:
				ammo_label.visible = not pressed
			if player.current_view and player.current_view.has_method("set_ammo_3d_visible"):
				player.current_view.set_ammo_3d_visible(pressed)
				if pressed:
					player.current_view.set_ammo_display(player.current_ammo, player.reserve_ammo)
	)
	vbox_ext.add_child(chk_ammo_3d)

	add_child(settings_menu)

func _sync_fps_option() -> void:
	if not option_fps:
		return
	for i in range(option_fps.item_count):
		if option_fps.get_item_id(i) == Engine.max_fps:
			option_fps.selected = i
			return
	option_fps.selected = -1

# ---------------------------------------------------------------------------
# Режим Ультра-Картошка
# ---------------------------------------------------------------------------
func _toggle_potato_mode() -> void:
	is_potato_mode = !is_potato_mode
	var vp = get_viewport()
	var cam = vp.get_camera_3d()
	var env = _get_env()

	if is_potato_mode:
		# Запоминаем текущие настройки, чтобы вернуть именно их
		saved_settings = {
			"vsync": DisplayServer.window_get_vsync_mode(),
			"msaa": vp.msaa_3d,
			"aa": vp.screen_space_aa,
			"scale": vp.scaling_3d_scale,
			"fps": Engine.max_fps,
			"far": cam.far if cam else 4000.0,
		}
		if env:
			saved_settings["glow"] = env.glow_enabled
			saved_settings["ssao"] = env.ssao_enabled
			saved_settings["ssr"] = env.ssr_enabled
			saved_settings["vfog"] = env.volumetric_fog_enabled
			saved_settings["fog"] = env.fog_enabled
			saved_settings["sdfgi"] = env.sdfgi_enabled
			saved_settings["tonemap"] = env.tonemap_mode

		btn_potato.text = "🥔 Режим Ультра-Картошка: Вкл"

		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.scaling_3d_scale = 0.35
		Engine.max_fps = 60

		if cam:
			cam.far = 100.0
		if env:
			env.glow_enabled = false
			env.ssao_enabled = false
			env.ssr_enabled = false
			env.volumetric_fog_enabled = false
			env.fog_enabled = false
			env.sdfgi_enabled = false
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR

		for node in get_tree().get_nodes_in_group("directional_lights"):
			if node is DirectionalLight3D:
				node.shadow_enabled = false

		print("Ultra-Potato mode ON | env=", env, " vsync=", DisplayServer.window_get_vsync_mode())
	else:
		btn_potato.text = "🥔 Режим Ультра-Картошка: Выкл"

		DisplayServer.window_set_vsync_mode(saved_settings.get("vsync", DisplayServer.VSYNC_ENABLED))
		vp.msaa_3d = saved_settings.get("msaa", Viewport.MSAA_2X)
		vp.screen_space_aa = saved_settings.get("aa", Viewport.SCREEN_SPACE_AA_FXAA)
		vp.scaling_3d_scale = saved_settings.get("scale", 1.0)
		Engine.max_fps = saved_settings.get("fps", 0)

		if cam:
			cam.far = saved_settings.get("far", 4000.0)
		if env and saved_settings.has("glow"):
			env.glow_enabled = saved_settings["glow"]
			env.ssao_enabled = saved_settings["ssao"]
			env.ssr_enabled = saved_settings["ssr"]
			env.volumetric_fog_enabled = saved_settings["vfog"]
			env.fog_enabled = saved_settings["fog"]
			env.sdfgi_enabled = saved_settings["sdfgi"]
			env.tonemap_mode = saved_settings["tonemap"]

		for node in get_tree().get_nodes_in_group("directional_lights"):
			if node is DirectionalLight3D:
				node.shadow_enabled = true

		print("Normal graphics mode restored")

	_sync_settings_ui()

# Приводит элементы интерфейса в соответствие с реальными настройками
func _sync_settings_ui() -> void:
	var vp = get_viewport()
	var env = _get_env()

	if chk_vsync:
		chk_vsync.set_pressed_no_signal(DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED)
	if option_msaa:
		option_msaa.selected = option_msaa.get_item_index(vp.msaa_3d)
	if slider_scale:
		slider_scale.set_value_no_signal(vp.scaling_3d_scale)
	if chk_fxaa:
		chk_fxaa.set_pressed_no_signal(vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA)
	if env:
		if chk_glow: chk_glow.set_pressed_no_signal(env.glow_enabled)
		if chk_ssao: chk_ssao.set_pressed_no_signal(env.ssao_enabled)
		if chk_ssr: chk_ssr.set_pressed_no_signal(env.ssr_enabled)
	_sync_fps_option()

# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not player:
		return

	# Обновление FPS и сети в Debug панели
	_fps_timer += delta
	var current_fps_val = Engine.get_frames_per_second()
	_fps_samples.append(float(current_fps_val))

	if _fps_timer >= 0.5:
		_fps_timer = 0.0
		if not _fps_samples.is_empty():
			var sum_fps: float = 0.0
			_min_fps = 9999
			_max_fps = 0
			for val in _fps_samples:
				sum_fps += val
				if val < _min_fps: _min_fps = int(val)
				if val > _max_fps: _max_fps = int(val)
			_avg_fps = int(sum_fps / _fps_samples.size())
			_fps_samples.clear()

	if debug_label:
		var ping_ms = 0
		var packet_loss_pct = 0.0
		var peer = multiplayer.multiplayer_peer
		if peer is ENetMultiplayerPeer:
			if multiplayer.is_server():
				ping_ms = 0
				packet_loss_pct = 0.0
			else:
				var enet_peer = peer as ENetMultiplayerPeer
				if enet_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
					var p = enet_peer.get_peer(1)
					if p:
						ping_ms = int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
						# В ENet статистика PEER_PACKET_LOSS нормализуется шкалой от 0 до 65536
						var raw_loss = p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)
						packet_loss_pct = clampf((float(raw_loss) / 65536.0) * 100.0, 0.0, 100.0)

		var min_display = _min_fps if _min_fps != 9999 else current_fps_val
		debug_label.text = "FPS: %d (Avg: %d | Min: %d | Max: %d)\nPing: %d ms | Loss: %.1f%%" % [
			current_fps_val, _avg_fps, min_display, _max_fps, ping_ms, packet_loss_pct
		]

	var target_spread = 6.0
	if player.get("is_ads"):
		target_spread = 2.0
	elif player.get("is_sprinting"):
		target_spread = 18.0
	elif player.velocity.length() > 0.1:
		target_spread = 12.0

	current_spread = lerp(current_spread, target_spread, delta * 12.0)
	_update_mobile_buttons_visual()
	if crosshair_view:
		crosshair_view.hit_amount = clampf(hit_flash_timer / 0.15, 0.0, 1.0)
	if crosshair:
		crosshair.custom_minimum_size = Vector2(current_spread, current_spread)
		if hit_flash_timer > 0.0:
			hit_flash_timer -= delta
			crosshair.color = Color(1, 0, 0, 1)
		else:
			crosshair.color = Color(1, 1, 1, 0.8)

func _on_hit_target() -> void:
	hit_flash_timer = 0.15

func _on_health_changed(new_health: int) -> void:
	if health_bar:
		health_bar.value = new_health

func _on_ammo_changed(current: int, reserve: int) -> void:
	if ammo_label:
		ammo_label.text = "Патроны: %d / %d" % [current, reserve]

func _on_weapon_changed(weapon_name: String) -> void:
	if weapon_button:
		weapon_button.text = "Оружие: " + weapon_name

func _on_server_disconnected_ui() -> void:
	if disconnect_label:
		disconnect_label.show()
		await get_tree().create_timer(3.0).timeout
		disconnect_label.hide()

func _populate_resolutions(aspect_mode: int) -> void:
	if not option_res:
		return
	option_res.clear()
	current_res_list.clear()

	var presets = {
		1: [ # 16:9
			Vector2i(2560, 1440), Vector2i(1920, 1080), Vector2i(1600, 900),
			Vector2i(1366, 768), Vector2i(1280, 720), Vector2i(960, 540), Vector2i(640, 360)
		],
		2: [ # 16:10
			Vector2i(1920, 1200), Vector2i(1680, 1050), Vector2i(1440, 900),
			Vector2i(1280, 800), Vector2i(960, 600), Vector2i(640, 400)
		],
		3: [ # 4:3
			Vector2i(1600, 1200), Vector2i(1400, 1050), Vector2i(1280, 960),
			Vector2i(1024, 768), Vector2i(800, 600), Vector2i(640, 480)
		],
		4: [ # 21:9
			Vector2i(3440, 1440), Vector2i(2560, 1080), Vector2i(1720, 720)
		]
	}

	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var screen_ratio: float = float(screen_size.x) / maxf(float(screen_size.y), 1.0)

	if aspect_mode == 0:
		# Автоматический подбор по физическому экрану игрока
		var matched_key: int = 0
		if absf(screen_ratio - (16.0 / 9.0)) < 0.08:
			matched_key = 1
		elif absf(screen_ratio - (16.0 / 10.0)) < 0.08:
			matched_key = 2
		elif absf(screen_ratio - (4.0 / 3.0)) < 0.08:
			matched_key = 3
		elif absf(screen_ratio - (21.0 / 9.0)) < 0.15:
			matched_key = 4

		if matched_key != 0:
			for r in presets[matched_key]:
				if r.x <= screen_size.x and r.y <= screen_size.y:
					current_res_list.append(r)
			if not current_res_list.has(screen_size):
				current_res_list.insert(0, screen_size)
		else:
			# Нестандартный экран: строим список от родного разрешения вниз до ~480p
			for scale_step in [1.0, 0.85, 0.75, 0.66, 0.5, 0.35]:
				var w: int = int(round(screen_size.x * scale_step))
				var h: int = int(round(screen_size.y * scale_step))
				if w >= 640 and h >= 360:
					var cand := Vector2i(w, h)
					if not current_res_list.has(cand):
						current_res_list.append(cand)
			if not current_res_list.has(Vector2i(640, 480)):
				current_res_list.append(Vector2i(640, 480))
	else:
		for r in presets.get(aspect_mode, []):
			current_res_list.append(r)

	var win_size: Vector2i = DisplayServer.window_get_size()
	var selected_idx: int = 0
	for i in range(current_res_list.size()):
		var r: Vector2i = current_res_list[i]
		option_res.add_item("%d x %d" % [r.x, r.y], i)
		if abs(win_size.x - r.x) < 40 and abs(win_size.y - r.y) < 40:
			selected_idx = i

	option_res.selected = selected_idx

func _apply_game_resolution(target_res: Vector2i) -> void:
	var root_win: Window = get_tree().root
	var is_full: bool = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	# Переводим режим масштабирования в viewport, чтобы менялось разрешение ВСЕЙ игры (и 3D, и UI),
	# но при родном разрешении экрана картинка оставалась пиксель-в-пиксель чёткой
	root_win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root_win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root_win.content_scale_size = target_res

	if not is_full:
		DisplayServer.window_set_size(target_res)
		var screen_center: Vector2i = DisplayServer.screen_get_position() + DisplayServer.screen_get_size() / 2
		DisplayServer.window_set_position(screen_center - target_res / 2)

	if slider_scale:
		slider_scale.set_value_no_signal(get_viewport().scaling_3d_scale)

var _rebinding_action: String = ""
var _rebinding_button: Button = null

func _get_action_key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "Не назначено"
	var events = InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode)
		elif ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: return "ЛКМ"
				MOUSE_BUTTON_RIGHT: return "ПКМ"
				MOUSE_BUTTON_MIDDLE: return "СКМ"
				_: return "Мышь %d" % ev.button_index
	return "Не назначено"

func _start_key_rebind(action: String, button: Button) -> void:
	_rebinding_action = action
	_rebinding_button = button
	button.text = "[Нажмите клавишу...]"

func _unhandled_key_input(event: InputEvent) -> void:
	if _rebinding_action == "" or _rebinding_button == null:
		return
	if event is InputEventKey and event.pressed:
		InputMap.action_erase_events(_rebinding_action)
		InputMap.action_add_event(_rebinding_action, event)
		_rebinding_button.text = _get_action_key_name(_rebinding_action)
		_rebinding_action = ""
		_rebinding_button = null
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		InputMap.action_erase_events(_rebinding_action)
		InputMap.action_add_event(_rebinding_action, event)
		_rebinding_button.text = _get_action_key_name(_rebinding_action)
		_rebinding_action = ""
		_rebinding_button = null
		get_viewport().set_input_as_handled()

func _create_mobile_icon_button(id: String, icon_path: String, bottom_right_offset: Vector2, base_size: Vector2) -> void:
	var holder := Panel.new()
	holder.name = "Btn_" + id
	holder.custom_minimum_size = base_size
	holder.size = base_size
	holder.pivot_offset = base_size * 0.5
	holder.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	holder.offset_left = bottom_right_offset.x
	holder.offset_top = bottom_right_offset.y
	holder.offset_right = bottom_right_offset.x + base_size.x
	holder.offset_bottom = bottom_right_offset.y + base_size.y
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.15, 0.55)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(base_size.x * 0.5))
	holder.add_theme_stylebox_override("panel", sb)

	var tex_rect := TextureRect.new()
	tex_rect.name = "Icon"
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_rect.offset_left = base_size.x * 0.18
	tex_rect.offset_top = base_size.y * 0.18
	tex_rect.offset_right = -base_size.x * 0.18
	tex_rect.offset_bottom = -base_size.y * 0.18
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(icon_path):
		tex_rect.texture = load(icon_path)
	holder.add_child(tex_rect)

	mobile_controls_layer.add_child(holder)
	mobile_btn_nodes[id] = holder
	mobile_btn_defaults[id] = {
		"offset": bottom_right_offset,
		"size": base_size,
		"scale": 1.0
	}
	if player and "mobile_hud_buttons" in player:
		player.mobile_hud_buttons[id] = holder

func _update_mobile_buttons_visual() -> void:
	if not player or mobile_btn_nodes.is_empty():
		return
	for id in mobile_btn_nodes.keys():
		var node: Control = mobile_btn_nodes[id]
		var active: bool = false
		match id:
			"fire": active = player.touch_fire
			"ads": active = player.is_ads
			"crouch": active = player.is_crouching
		if is_editing_hud and selected_hud_btn_id == id:
			node.modulate = Color(1.0, 0.65, 0.2, 1.0)
		elif active:
			node.modulate = Color(1.0, 0.54, 0.16, 1.0)
		else:
			node.modulate = Color(1.0, 1.0, 1.0, 0.9)

func _build_hud_layout_editor() -> void:
	hud_editor_panel = Control.new()
	hud_editor_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	hud_editor_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_editor_panel.visible = false
	hud_editor_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(hud_editor_panel)

	var top_box := PanelContainer.new()
	top_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_box.offset_left = 40
	top_box.offset_top = 15
	top_box.offset_right = -40
	top_box.offset_bottom = 115
	hud_editor_panel.add_child(top_box)

	var vbox := VBoxContainer.new()
	top_box.add_child(vbox)

	var info := Label.new()
	info.text = "Перетаскивай кнопки пальцем. Выбери кнопку для изменения размера:"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	var lbl_sz := Label.new()
	lbl_sz.text = "Размер:"
	hbox.add_child(lbl_sz)

	hud_scale_slider = HSlider.new()
	hud_scale_slider.custom_minimum_size = Vector2(200, 32)
	hud_scale_slider.min_value = 0.5
	hud_scale_slider.max_value = 2.0
	hud_scale_slider.step = 0.05
	hud_scale_slider.value = 1.0
	hud_scale_slider.value_changed.connect(func(val):
		if selected_hud_btn_id != "" and mobile_btn_nodes.has(selected_hud_btn_id):
			_set_mobile_btn_scale(selected_hud_btn_id, val)
	)
	hbox.add_child(hud_scale_slider)

	var btn_reset := Button.new()
	btn_reset.text = "Сброс"
	btn_reset.pressed.connect(_reset_mobile_hud_layout)
	hbox.add_child(btn_reset)

	var btn_save := Button.new()
	btn_save.text = "Сохранить и выйти"
	btn_save.pressed.connect(func():
		_save_mobile_hud_layout()
		_close_hud_editor()
	)
	hbox.add_child(btn_save)

	hud_editor_panel.gui_input.connect(_on_hud_editor_input)

func _open_hud_editor() -> void:
	is_editing_hud = true
	if pause_menu: pause_menu.hide()
	if settings_menu: settings_menu.hide()
	if mobile_controls_layer: mobile_controls_layer.visible = true
	hud_editor_panel.show()

func _close_hud_editor() -> void:
	is_editing_hud = false
	_dragging_btn_id = ""
	hud_editor_panel.hide()
	if pause_menu: pause_menu.show()
	if settings_menu: settings_menu.show()

func _on_hud_editor_input(event: InputEvent) -> void:
	if not is_editing_hud:
		return
	var pos: Vector2 = Vector2.ZERO
	var pressed: bool = false
	var is_drag: bool = false

	if event is InputEventScreenTouch:
		pos = event.position
		pressed = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = event.pressed
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		pos = event.position
		is_drag = true
	else:
		return

	if not is_drag:
		if pressed:
			for id in mobile_btn_nodes.keys():
				var ctrl: Control = mobile_btn_nodes[id]
				if ctrl.get_global_rect().has_point(pos):
					selected_hud_btn_id = id
					_dragging_btn_id = id
					_drag_offset = ctrl.global_position - pos
					if hud_scale_slider:
						var base_sz: Vector2 = mobile_btn_defaults[id]["size"]
						hud_scale_slider.set_value_no_signal(ctrl.size.x / base_sz.x)
					break
		else:
			_dragging_btn_id = ""
	elif _dragging_btn_id != "" and mobile_btn_nodes.has(_dragging_btn_id):
		var ctrl: Control = mobile_btn_nodes[_dragging_btn_id]
		var btn_size: Vector2 = ctrl.custom_minimum_size
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		var new_global: Vector2 = pos + _drag_offset
		new_global.x = clampf(new_global.x, 0.0, maxf(vp_size.x - btn_size.x, 0.0))
		new_global.y = clampf(new_global.y, 0.0, maxf(vp_size.y - btn_size.y, 0.0))
		var br_offset: Vector2 = new_global - vp_size
		ctrl.offset_left = br_offset.x
		ctrl.offset_top = br_offset.y
		ctrl.offset_right = br_offset.x + btn_size.x
		ctrl.offset_bottom = br_offset.y + btn_size.y

func _set_mobile_btn_scale(id: String, sc: float) -> void:
	var ctrl: Control = mobile_btn_nodes[id]
	var base_size: Vector2 = mobile_btn_defaults[id]["size"]
	var old_size: Vector2 = ctrl.custom_minimum_size
	var new_size: Vector2 = base_size * sc
	var center_offset: Vector2 = Vector2(ctrl.offset_left + old_size.x * 0.5, ctrl.offset_top + old_size.y * 0.5)
	ctrl.custom_minimum_size = new_size
	var new_left: float = center_offset.x - new_size.x * 0.5
	var new_top: float = center_offset.y - new_size.y * 0.5
	ctrl.offset_left = new_left
	ctrl.offset_top = new_top
	ctrl.offset_right = new_left + new_size.x
	ctrl.offset_bottom = new_top + new_size.y

	var sb := ctrl.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.set_corner_radius_all(int(new_size.x * 0.5))
	var icon := ctrl.get_node_or_null("Icon") as Control
	if icon:
		icon.offset_left = new_size.x * 0.18
		icon.offset_top = new_size.y * 0.18
		icon.offset_right = -new_size.x * 0.18
		icon.offset_bottom = -new_size.y * 0.18

func _save_mobile_hud_layout() -> void:
	var cfg := ConfigFile.new()
	for id in mobile_btn_nodes.keys():
		var ctrl: Control = mobile_btn_nodes[id]
		var base_sz: Vector2 = mobile_btn_defaults[id]["size"]
		cfg.set_value(id, "offset_x", ctrl.offset_left)
		cfg.set_value(id, "offset_y", ctrl.offset_top)
		cfg.set_value(id, "scale", ctrl.custom_minimum_size.x / base_sz.x)
	cfg.save(MOBILE_HUD_CFG_PATH)

func _load_mobile_hud_layout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(MOBILE_HUD_CFG_PATH) != OK:
		return
	for id in mobile_btn_nodes.keys():
		if not cfg.has_section(id):
			continue
		var ctrl: Control = mobile_btn_nodes[id]
		var sc: float = float(cfg.get_value(id, "scale", 1.0))
		_set_mobile_btn_scale(id, sc)
		var btn_size: Vector2 = ctrl.custom_minimum_size
		var ox: float = float(cfg.get_value(id, "offset_x", ctrl.offset_left))
		var oy: float = float(cfg.get_value(id, "offset_y", ctrl.offset_top))
		ctrl.offset_left = ox
		ctrl.offset_top = oy
		ctrl.offset_right = ox + btn_size.x
		ctrl.offset_bottom = oy + btn_size.y

func _reset_mobile_hud_layout() -> void:
	for id in mobile_btn_nodes.keys():
		var def: Dictionary = mobile_btn_defaults[id]
		var ctrl: Control = mobile_btn_nodes[id]
		_set_mobile_btn_scale(id, 1.0)
		var off: Vector2 = def["offset"]
		var sz: Vector2 = def["size"]
		ctrl.offset_left = off.x
		ctrl.offset_top = off.y
		ctrl.offset_right = off.x + sz.x
		ctrl.offset_bottom = off.y + sz.y
	if hud_scale_slider:
		hud_scale_slider.set_value_no_signal(1.0)
