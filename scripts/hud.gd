extends CanvasLayer

const SoundFX = preload("res://scripts/sound_effects.gd")
const DamageIndicatorView = preload("res://scripts/damage_indicator.gd")

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
var weapon_wheel: WeaponWheel
var _wheel_press_time: float = 0.0
var _wheel_touch_active: bool = false
var _wheel_touch_origin: Vector2 = Vector2.ZERO
var _wheel_touch_has_moved: bool = false
var _wheel_touch_time: float = 0.0
var hit_sound_player: AudioStreamPlayer
var damage_indicator: DamageIndicatorView

var pause_menu: Control
var settings_menu: Control
var audio_slider: HSlider
var is_paused: bool = false
var debug_label: Label
var weapon_button: Button

const MOBILE_HUD_CFG_PATH: String = "user://mobile_hud.cfg"
var top_bar_ctrl: Control = null
var mobile_controls_layer: Control = null
var mobile_btn_nodes: Dictionary = {} # id -> Control
var mobile_btn_defaults: Dictionary = {} # id -> { "offset": Vector2, "scale": float }
var hud_editor_panel: Control = null
var hud_editor_top_box: Control = null
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

func _find_player() -> CharacterBody3D:
	if owner is CharacterBody3D:
		return owner as CharacterBody3D
	var p: Node = get_parent()
	while p:
		if p is CharacterBody3D:
			return p as CharacterBody3D
		p = p.get_parent()
	return null

func _ready() -> void:
	if player == null:
		player = _find_player()

	var is_local := true
	if player and player.has_method("is_local_player"):
		is_local = player.is_local_player()
	elif player and multiplayer.has_multiplayer_peer():
		is_local = player.is_multiplayer_authority()

	if not player or not is_local:
		queue_free()
		return

	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	if player.has_signal("ammo_changed"):
		player.ammo_changed.connect(_on_ammo_changed)
	if player.has_signal("hit_target"):
		player.hit_target.connect(_on_hit_target)
	if player.has_signal("damage_taken"):
		player.damage_taken.connect(_on_damage_taken)
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

	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause_menu()
	_build_hud_elements()
	
	# Применяем тему ко всем дочерним элементам интерфейса (CanvasLayer не имеет собственной темы)
	var custom_theme = UITheme.build()
	if pause_menu: pause_menu.theme = custom_theme
	if settings_menu: settings_menu.theme = custom_theme
	
	GameSettings.ensure_loaded()
	_apply_saved_settings_on_start()

	scoreboard = Scoreboard.new()
	add_child(scoreboard)
	kill_feed = KillFeed.new()
	add_child(kill_feed)
	if crosshair:
		crosshair.visible = false
	crosshair_view = CrosshairView.new()
	crosshair_view.player = player
	add_child(crosshair_view)

	damage_indicator = DamageIndicatorView.new()
	add_child(damage_indicator)
	move_child(damage_indicator, 0)

	hit_sound_player = AudioStreamPlayer.new()
	hit_sound_player.name = "HitmarkerSound2D"
	hit_sound_player.bus = "Master"
	add_child(hit_sound_player)

	weapon_wheel = WeaponWheel.new()
	weapon_wheel.player = player
	weapon_wheel.weapon_selected.connect(func(w_idx: int):
		if player and player.has_method("_switch_weapon"):
			player._switch_weapon(w_idx)
	)
	add_child(weapon_wheel)
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

	# Debug-панель (Top Left, под полоской здоровья, чтобы не перекрывать киллфид в правом углу)
	debug_label = Label.new()
	debug_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	debug_label.offset_left = 16
	debug_label.offset_top = 80
	debug_label.offset_right = 340
	debug_label.offset_bottom = 150
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	debug_label.text = "DEBUG INFO"
	debug_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 0.9))
	debug_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	debug_label.add_theme_constant_override("outline_size", 3)
	debug_label.add_theme_font_size_override("font_size", 13)
	hud_container.add_child(debug_label)
	debug_label.visible = false

	# Растягиваем TouchOverlay на весь экран и выравниваем джойстик в левом нижнем углу
	if touch_overlay:
		touch_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var joy := touch_overlay.get_node_or_null("JoystickBase") as Control
		if joy:
			joy.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			joy.offset_left = 65
			joy.offset_top = -235
			joy.offset_right = 235
			joy.offset_bottom = -65
			if joy is ColorRect:
				(joy as ColorRect).color = Color(0, 0, 0, 0)
				if not joy.has_node("RoundBg"):
					var rbg := Panel.new()
					rbg.name = "RoundBg"
					rbg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
					rbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
					var sb_j := StyleBoxFlat.new()
					sb_j.bg_color = Color(0.1, 0.12, 0.15, 0.45)
					sb_j.border_color = Color(1.0, 1.0, 1.0, 0.25)
					sb_j.set_border_width_all(2)
					sb_j.set_corner_radius_all(100)
					rbg.add_theme_stylebox_override("panel", sb_j)
					joy.add_child(rbg)
					joy.move_child(rbg, 0)

	# Верхняя панель служебных кнопок для телефона (строго по центру сверху)
	var top_bar = HBoxContainer.new()
	top_bar_ctrl = top_bar
	top_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	top_bar.offset_left = -120
	top_bar.offset_top = 12
	top_bar.offset_right = 120
	top_bar.offset_bottom = 52
	top_bar.add_theme_constant_override("separation", 12)
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

	if player and player.has_method("is_fist_fight_mode") and player.is_fist_fight_mode():
		if mobile_btn_nodes.has("cycle_weapon"):
			mobile_btn_nodes["cycle_weapon"].visible = false

	_load_mobile_hud_layout()
	_build_hud_layout_editor()

func _input(event: InputEvent) -> void:
	# Перехват клавиши при переназначении (гарантированно работает во время паузы)
	if _rebinding_action != "" and is_instance_valid(_rebinding_button):
		if event is InputEventKey and event.pressed and not event.is_echo():
			get_viewport().set_input_as_handled()
			if event.keycode == KEY_ESCAPE:
				_rebinding_button.text = _get_action_key_name(_rebinding_action)
			else:
				var keycode_to_bind: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
				InputMap.action_erase_events(_rebinding_action)
				var new_ev := InputEventKey.new()
				new_ev.physical_keycode = keycode_to_bind
				new_ev.keycode = keycode_to_bind
				InputMap.action_add_event(_rebinding_action, new_ev)
				_rebinding_button.text = OS.get_keycode_string(keycode_to_bind)
				GameSettings.save_to_disk()

			_rebinding_action = ""
			_rebinding_button = null
			return
		elif event is InputEventMouseButton and event.pressed:
			get_viewport().set_input_as_handled()
			InputMap.action_erase_events(_rebinding_action)
			var new_ev := InputEventMouseButton.new()
			new_ev.button_index = event.button_index
			InputMap.action_add_event(_rebinding_action, new_ev)
			_rebinding_button.text = _get_action_key_name(_rebinding_action)
			GameSettings.save_to_disk()

			_rebinding_action = ""
			_rebinding_button = null
			return

	if is_editing_hud:
		var pos := Vector2.ZERO
		var pressed := false
		var is_drag := false
		var valid_input := false

		if event is InputEventScreenTouch:
			pos = event.position
			pressed = event.pressed
			valid_input = true
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			pos = event.position
			pressed = event.pressed
			valid_input = true
		elif event is InputEventScreenDrag or (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
			pos = event.position
			is_drag = true
			valid_input = true

		if valid_input:
			# Если клик/касание внутри верхней панели редактора — даём кнопкам обработать его
			if hud_editor_top_box and hud_editor_top_box.get_global_rect().has_point(pos):
				return

			if not is_drag:
				if pressed:
					for id in mobile_btn_nodes.keys():
						var ctrl: Control = mobile_btn_nodes[id]
						if ctrl.get_global_rect().has_point(pos):
							selected_hud_btn_id = id
							_dragging_btn_id = id
							_drag_offset = ctrl.global_position - pos
							if hud_scale_slider and mobile_btn_defaults.has(id):
								var base_sz: Vector2 = mobile_btn_defaults[id]["size"]
								hud_scale_slider.set_value_no_signal(ctrl.size.x / base_sz.x)
							_update_mobile_buttons_visual()
							get_viewport().set_input_as_handled()
							return
					_dragging_btn_id = ""
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
				get_viewport().set_input_as_handled()
				return

	if player == null:
		player = _find_player()

	var is_local := true
	if player and player.has_method("is_local_player"):
		is_local = player.is_local_player()
	elif player and multiplayer.has_multiplayer_peer():
		is_local = player.is_multiplayer_authority()

	if not player or not is_local:
		return

	if event.is_action_pressed("weapon_wheel") and not is_paused:
		_wheel_press_time = Time.get_ticks_msec() / 1000.0
		if weapon_wheel and not weapon_wheel.is_open:
			weapon_wheel.open()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if crosshair_view:
				crosshair_view.visible = false
		get_viewport().set_input_as_handled()
		return

	if event.is_action_released("weapon_wheel") and not is_paused:
		var duration: float = (Time.get_ticks_msec() / 1000.0) - _wheel_press_time
		if weapon_wheel and weapon_wheel.is_open:
			# Если был короткий тап (< 0.2 сек) и мышь не двигали — переключаем на следующее оружие (Quick Switch)
			if duration < 0.2 and not weapon_wheel.has_mouse_moved:
				weapon_wheel.close_without_select()
				if player and player.has_method("cycle_weapon"):
					player.cycle_weapon()
			else:
				weapon_wheel.close()

			if not is_paused and not _is_mobile():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			if crosshair_view:
				crosshair_view.visible = true
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		if weapon_wheel and weapon_wheel.is_open:
			weapon_wheel.close()
			if not is_paused and not _is_mobile():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			if crosshair_view:
				crosshair_view.visible = true
			get_viewport().set_input_as_handled()
			return
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
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if settings_menu:
			settings_menu.hide()
			settings_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_pause_menu() -> void:
	pause_menu = Control.new()
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_menu.add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	pause_menu.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 200)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
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
			if pause_menu:
				pause_menu.hide()
			_update_settings_menu_size()
			settings_menu.show()
			settings_menu.mouse_filter = Control.MOUSE_FILTER_STOP
			move_child(settings_menu, get_child_count() - 1)
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

func _update_settings_menu_size() -> void:
	if not settings_menu:
		return
	var center := settings_menu.get_node_or_null("CenterContainer")
	if center and center.get_child_count() > 0:
		var panel := center.get_child(0) as Control
		if panel:
			var vp := get_viewport()
			var vp_size: Vector2 = vp.get_visible_rect().size if vp else Vector2(1280, 720)
			var is_mob := _is_mobile()
			var w: float = minf(vp_size.x - 40.0, 560.0 if is_mob else 720.0)
			var h: float = maxf(vp_size.y - 44.0, 320.0)
			panel.custom_minimum_size = Vector2(w, h)

func _build_settings_menu() -> void:
	GameSettings.ensure_loaded()
	settings_menu = Control.new()
	settings_menu.name = "SettingsMenu"
	settings_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_menu.visible = false
	settings_menu.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.65)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_menu.add_child(bg)

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	settings_menu.add_child(center)

	var panel := PanelContainer.new()
	panel.theme = UITheme.build()
	var is_mob := _is_mobile()
	var vp := get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size if vp else Vector2(1280, 720)
	var w: float = minf(vp_size.x - 40.0, 560.0 if is_mob else 720.0)
	var h: float = maxf(vp_size.y - 44.0, 320.0)
	panel.custom_minimum_size = Vector2(w, h)
	center.add_child(panel)

	add_child(settings_menu)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(main_vbox)

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
		GameSettings.apply_to_player(player)
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
		GameSettings.apply_to_player(player)
	)
	vbox_input.add_child(ads_slider)

	var chk_inv := CheckBox.new()
	chk_inv.text = "Инверсия оси Y (вертикальный обзор)"
	chk_inv.button_pressed = GameSettings.invert_y
	chk_inv.toggled.connect(func(pressed):
		GameSettings.invert_y = pressed
		GameSettings.apply_to_player(player)
	)
	vbox_input.add_child(chk_inv)

	var chk_crouch_mode := CheckBox.new()
	chk_crouch_mode.text = "Приседание по нажатию (Toggle вместо удержания)"
	chk_crouch_mode.button_pressed = GameSettings.crouch_toggle_mode
	chk_crouch_mode.toggled.connect(func(pressed):
		GameSettings.crouch_toggle_mode = pressed
		if player:
			player.crouch_toggle_mode = pressed
			player._crouch_toggled = false
			player.touch_crouch = false
	)
	vbox_input.add_child(chk_crouch_mode)

	if _is_mobile():
		vbox_input.add_child(HSeparator.new())
		var lbl_tsens := Label.new()
		lbl_tsens.text = "Чувствительность тача: %.4f" % GameSettings.touch_sensitivity
		vbox_input.add_child(lbl_tsens)
		var tsens_slider := HSlider.new()
		tsens_slider.min_value = 0.001
		tsens_slider.max_value = 0.02
		tsens_slider.step = 0.0005
		tsens_slider.value = GameSettings.touch_sensitivity
		tsens_slider.value_changed.connect(func(val):
			GameSettings.touch_sensitivity = val
			lbl_tsens.text = "Чувствительность тача: %.4f" % val
			GameSettings.apply_to_player(player)
		)
		vbox_input.add_child(tsens_slider)

		var lbl_op := Label.new()
		lbl_op.text = "Прозрачность кнопок экрана: %d%%" % int(round(GameSettings.mobile_btn_opacity * 100.0))
		vbox_input.add_child(lbl_op)
		var op_slider := HSlider.new()
		op_slider.min_value = 0.2
		op_slider.max_value = 1.0
		op_slider.step = 0.05
		op_slider.value = GameSettings.mobile_btn_opacity
		op_slider.value_changed.connect(func(val):
			GameSettings.mobile_btn_opacity = val
			lbl_op.text = "Прозрачность кнопок экрана: %d%%" % int(round(val * 100.0))
		)
		vbox_input.add_child(op_slider)

		var lbl_steer := Label.new()
		lbl_steer.text = "Управление машиной на таче:"
		vbox_input.add_child(lbl_steer)
		var opt_steer := OptionButton.new()
		opt_steer.add_item("🔄 Поворотный руль", 0)
		opt_steer.add_item("◀ ▶ Кнопки влево / вправо", 1)
		opt_steer.selected = GameSettings.vehicle_touch_steering
		opt_steer.item_selected.connect(func(idx: int):
			GameSettings.vehicle_touch_steering = idx
			GameSettings.save_to_disk()
		)
		vbox_input.add_child(opt_steer)

		var btn_edit_hud := Button.new()
		btn_edit_hud.text = "Настроить расположение и размер кнопок"
		btn_edit_hud.theme_type_variation = "AccentButton"
		btn_edit_hud.custom_minimum_size = Vector2(0, 42)
		btn_edit_hud.pressed.connect(func(): _open_hud_editor())
		vbox_input.add_child(btn_edit_hud)
	else:
		vbox_input.add_child(HSeparator.new())
		var lbl_rebind := Label.new()
		lbl_rebind.text = "Переназначение клавиш:"
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
			{"action": "ads", "label": "Прицел"},
			{"action": "weapon_wheel", "label": "Колесо оружия / Быстрая смена"}
		]
		for item in rebind_actions:
			var act_name: String = item["action"]
			var row := HBoxContainer.new()
			var action_label := Label.new()
			action_label.text = item["label"]
			action_label.custom_minimum_size = Vector2(200, 0)
			row.add_child(action_label)
			var btn_key := Button.new()
			btn_key.custom_minimum_size = Vector2(180, 36)
			btn_key.text = _get_action_key_name(act_name)
			btn_key.pressed.connect(_start_key_rebind.bind(act_name, btn_key))
			row.add_child(btn_key)
			vbox_input.add_child(row)

	# === ВКЛАДКА 2: ГРАФИКА ===
	var scroll_video := ScrollContainer.new()
	scroll_video.name = "Графика"
	tabs.add_child(scroll_video)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll_video.add_child(vbox)

	chk_fullscreen = CheckBox.new()
	chk_fullscreen.text = "Полноэкранный режим"
	chk_fullscreen.button_pressed = GameSettings.fullscreen
	chk_fullscreen.toggled.connect(func(pressed):
		GameSettings.fullscreen = pressed
		GameSettings.apply_to_engine(get_viewport(), _get_env())
		if option_res and option_res.selected >= 0 and option_res.selected < current_res_list.size():
			_apply_game_resolution(current_res_list[option_res.selected])
	)
	vbox.add_child(chk_fullscreen)

	var lbl_aspect := Label.new()
	lbl_aspect.text = "Соотношение сторон:"
	vbox.add_child(lbl_aspect)
	option_aspect = OptionButton.new()
	option_aspect.add_item("Автоматически (По экрану)", 0)
	option_aspect.add_item("16:9 (Широкоэкранный)", 1)
	option_aspect.add_item("16:10", 2)
	option_aspect.add_item("4:3 (Вплоть до 640x480)", 3)
	option_aspect.add_item("21:9 (Ультраширокий)", 4)
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
			_apply_game_resolution(current_res_list[idx])
	)
	_populate_resolutions(GameSettings.aspect_index)

	var lbl_ui_sc := Label.new()
	lbl_ui_sc.text = "Масштаб интерфейса (UI Scale): %d%%" % int(round(GameSettings.ui_scale * 100.0))
	vbox.add_child(lbl_ui_sc)
	var ui_sc_slider := HSlider.new()
	ui_sc_slider.min_value = 0.75
	ui_sc_slider.max_value = 2.0
	ui_sc_slider.step = 0.05
	ui_sc_slider.value = GameSettings.ui_scale
	ui_sc_slider.value_changed.connect(func(val):
		GameSettings.ui_scale = val
		lbl_ui_sc.text = "Масштаб интерфейса (UI Scale): %d%%" % int(round(val * 100.0))
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(ui_sc_slider)

	var lbl_fov := Label.new()
	lbl_fov.text = "Угол обзора (FOV): %d°" % int(round(GameSettings.base_fov))
	vbox.add_child(lbl_fov)
	var fov_slider := HSlider.new()
	fov_slider.min_value = 65.0
	fov_slider.max_value = 110.0
	fov_slider.step = 1.0
	fov_slider.value = GameSettings.base_fov
	fov_slider.value_changed.connect(func(val):
		GameSettings.base_fov = val
		lbl_fov.text = "Угол обзора (FOV): %d°" % int(round(val))
		GameSettings.apply_to_player(player)
	)
	vbox.add_child(fov_slider)

	var lbl_up := Label.new()
	lbl_up.text = "Режим 3D масштабирования (Upscaler):"
	vbox.add_child(lbl_up)
	var opt_upscale := OptionButton.new()
	opt_upscale.add_item("Bilinear (Стандартный)", 0)
	opt_upscale.add_item("AMD FSR 1.0 (Чёткий апскейл)", 1)
	opt_upscale.selected = GameSettings.scaling_mode
	opt_upscale.item_selected.connect(func(idx):
		GameSettings.scaling_mode = idx
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(opt_upscale)

	var lbl_fsr := Label.new()
	lbl_fsr.text = "Резкость FSR: %d%%" % int(round(GameSettings.fsr_sharpness * 50.0))
	vbox.add_child(lbl_fsr)
	var slider_fsr := HSlider.new()
	slider_fsr.min_value = 0.0
	slider_fsr.max_value = 2.0
	slider_fsr.step = 0.1
	slider_fsr.value = GameSettings.fsr_sharpness
	slider_fsr.value_changed.connect(func(val):
		GameSettings.fsr_sharpness = val
		lbl_fsr.text = "Резкость FSR: %d%%" % int(round(val * 50.0))
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(slider_fsr)

	var lbl_scale := Label.new()
	lbl_scale.text = "Масштаб 3D рендера: %d%%" % int(round(GameSettings.render_scale * 100.0))
	vbox.add_child(lbl_scale)
	slider_scale = HSlider.new()
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
	opt_sh.add_item("Отключены (Макс. FPS)", 0)
	opt_sh.add_item("Низкие", 1)
	opt_sh.add_item("Средние", 2)
	opt_sh.add_item("Высокие", 3)
	opt_sh.selected = GameSettings.shadow_quality
	opt_sh.item_selected.connect(func(idx):
		GameSettings.shadow_quality = idx
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(opt_sh)

	var lbl_msaa := Label.new()
	lbl_msaa.text = "Сглаживание 3D (MSAA):"
	vbox.add_child(lbl_msaa)
	option_msaa = OptionButton.new()
	option_msaa.add_item("Выкл", Viewport.MSAA_DISABLED)
	option_msaa.add_item("2x", Viewport.MSAA_2X)
	option_msaa.add_item("4x", Viewport.MSAA_4X)
	option_msaa.add_item("8x", Viewport.MSAA_8X)
	option_msaa.selected = GameSettings.msaa
	option_msaa.item_selected.connect(func(idx):
		GameSettings.msaa = idx
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(option_msaa)

	chk_fxaa = CheckBox.new()
	chk_fxaa.text = "Экранное сглаживание (FXAA)"
	chk_fxaa.button_pressed = GameSettings.fxaa
	chk_fxaa.toggled.connect(func(pressed):
		GameSettings.fxaa = pressed
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(chk_fxaa)

	chk_glow = CheckBox.new()
	chk_glow.text = "Свечение (Bloom / Glow)"
	chk_glow.button_pressed = GameSettings.glow
	chk_glow.toggled.connect(func(pressed):
		GameSettings.glow = pressed
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(chk_glow)

	chk_ssao = CheckBox.new()
	chk_ssao.text = "Затенение углов (SSAO)"
	chk_ssao.button_pressed = GameSettings.ssao
	chk_ssao.toggled.connect(func(pressed):
		GameSettings.ssao = pressed
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(chk_ssao)

	chk_ssr = CheckBox.new()
	chk_ssr.text = "Экранные отражения (SSR)"
	chk_ssr.button_pressed = GameSettings.ssr
	chk_ssr.toggled.connect(func(pressed):
		GameSettings.ssr = pressed
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(chk_ssr)

	chk_vsync = CheckBox.new()
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
	option_fps.add_item("240 FPS", 240)
	option_fps.selected = GameSettings.fps_limit_idx
	option_fps.item_selected.connect(func(idx):
		GameSettings.fps_limit_idx = idx
		GameSettings.apply_to_engine(get_viewport(), _get_env())
	)
	vbox.add_child(option_fps)

	btn_potato = Button.new()
	btn_potato.text = "Режим Ультра-Картошки: ВЫКЛ"
	btn_potato.custom_minimum_size = Vector2(0, 40)
	btn_potato.pressed.connect(func():
		_toggle_potato_mode()
		GameSettings.potato_mode = is_potato_mode
	)
	vbox.add_child(btn_potato)

	# === ВКЛАДКА 3: ПРИЦЕЛ ===
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
	opt_ch_col.item_selected.connect(func(idx):
		GameSettings.crosshair_color_idx = idx
		_apply_crosshair_settings()
	)
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
		_apply_crosshair_settings()
	)
	vbox_ch.add_child(sl_ch_sz)

	var chk_ch_dyn := CheckBox.new()
	chk_ch_dyn.text = "Динамическое расширение прицела при стрельбе и движении"
	chk_ch_dyn.button_pressed = GameSettings.crosshair_dynamic
	chk_ch_dyn.toggled.connect(func(pressed):
		GameSettings.crosshair_dynamic = pressed
	)
	vbox_ch.add_child(chk_ch_dyn)

	# === ВКЛАДКА 4: АУДИО ===
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
	audio_slider = HSlider.new()
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
	chk_hit_snd.text = "Звуковой сигнал при попадании по врагу (Hitmarker)"
	chk_hit_snd.button_pressed = GameSettings.hitmarker_sound
	chk_hit_snd.toggled.connect(func(pressed):
		GameSettings.hitmarker_sound = pressed
	)
	vbox_audio.add_child(chk_hit_snd)

	# === ВКЛАДКА 5: РАСШИРЕНИЯ ===
	var scroll_ext := ScrollContainer.new()
	scroll_ext.name = "Расширения"
	tabs.add_child(scroll_ext)
	var vbox_ext := VBoxContainer.new()
	vbox_ext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_ext.add_theme_constant_override("separation", 10)
	var lbl_lang := Label.new()
	lbl_lang.text = "Язык интерфейса / Language:"
	vbox_ext.add_child(lbl_lang)

	var opt_lang := OptionButton.new()
	opt_lang.add_item("Русский (RU)", 0)
	opt_lang.add_item("English (EN)", 1)
	opt_lang.selected = 1 if GameSettings.language == "en" else 0
	opt_lang.item_selected.connect(func(idx: int):
		var selected_lang := "en" if idx == 1 else "ru"
		GameSettings.set_language(selected_lang)
	)
	vbox_ext.add_child(opt_lang)
	vbox_ext.add_child(HSeparator.new())
	scroll_ext.add_child(vbox_ext)

	var chk_debug := CheckBox.new()
	chk_debug.text = "Панель отладки (Debug Info: FPS, Ping, Loss)"
	chk_debug.button_pressed = GameSettings.show_debug
	chk_debug.toggled.connect(func(pressed):
		GameSettings.show_debug = pressed
		if debug_label:
			debug_label.visible = pressed
	)
	vbox_ext.add_child(chk_debug)

	var chk_ammo_3d := CheckBox.new()
	chk_ammo_3d.text = "Показывать патроны на оружии (3D вместо HUD)"
	chk_ammo_3d.button_pressed = GameSettings.show_ammo_3d
	chk_ammo_3d.toggled.connect(func(pressed):
		GameSettings.show_ammo_3d = pressed
		if player and player.has_method("set_show_ammo_on_weapon"):
			player.set_show_ammo_on_weapon(pressed)
		if ammo_label:
			ammo_label.visible = not pressed
	)
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

	var lbl_tunnel := Label.new()
	lbl_tunnel.text = "Адрес туннеля playit.gg (для хоста):"
	vbox_ext.add_child(lbl_tunnel)

	var edit_tunnel := LineEdit.new()
	edit_tunnel.text = GameSettings.playit_tunnel_address
	edit_tunnel.placeholder_text = "Авто (или 147.185.x.x:12345)"
	edit_tunnel.text_changed.connect(func(new_addr): GameSettings.playit_tunnel_address = new_addr.strip_edges())
	vbox_ext.add_child(edit_tunnel)

	main_vbox.add_child(HSeparator.new())
	var btn_back := Button.new()
	btn_back.text = "Сохранить и закрыть"
	btn_back.theme_type_variation = "AccentButton"
	btn_back.custom_minimum_size = Vector2(0, 42)
	btn_back.pressed.connect(func():
		GameSettings.save_to_disk()
		settings_menu.hide()
		settings_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_paused and pause_menu:
			pause_menu.show()
	)
	main_vbox.add_child(btn_back)

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
		if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			if multiplayer.is_server():
				ping_ms = 0
				packet_loss_pct = 0.0
			else:
				if GameStats:
					ping_ms = GameStats.get_my_ping()
				var peer = multiplayer.multiplayer_peer
				if peer is ENetMultiplayerPeer:
					var enet_peer = peer as ENetMultiplayerPeer
					var p = enet_peer.get_peer(1)
					if p:
						if ping_ms == 0:
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

func _on_hit_target(is_hs: bool = false) -> void:
	hit_flash_timer = 0.18
	if crosshair_view:
		crosshair_view.hit_is_headshot = is_hs
	if hit_sound_player:
		hit_sound_player.stream = SoundFX.get_hitmarker(is_hs)
		hit_sound_player.pitch_scale = randf_range(0.97, 1.03)
		hit_sound_player.volume_db = 0.0
		hit_sound_player.play()

func _on_damage_taken(amount: int, attacker_dir: Vector3) -> void:
	if damage_indicator:
		var cam: Camera3D = get_viewport().get_camera_3d()
		damage_indicator.add_indicator(attacker_dir, cam)

func _on_health_changed(new_health: int) -> void:
	if health_bar:
		health_bar.value = new_health

func _on_ammo_changed(current: int, reserve: int) -> void:
	if ammo_label:
		if player and player.has_method("is_fist_fight_mode") and player.is_fist_fight_mode():
			ammo_label.text = "БОЙ (КУЛАКИ)"
		elif player and "current_weapon" in player and int(player.current_weapon) == 4:
			ammo_label.text = "БОЙ (КУЛАКИ)"
		else:
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
	var is_mobile_os: bool = OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]
	var is_full: bool = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	root_win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root_win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root_win.content_scale_size = Vector2i(1280, 720)
	root_win.content_scale_factor = clampf(GameSettings.ui_scale, 0.75, 2.0)

	if not is_mobile_os and not is_full:
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
	if _rebinding_button != null and is_instance_valid(_rebinding_button) and _rebinding_action != "":
		_rebinding_button.text = _get_action_key_name(_rebinding_action)

	_rebinding_action = action
	_rebinding_button = button
	button.text = "[Нажмите клавишу...]"
	button.release_focus()
	
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
			node.modulate = Color(1.0, 0.54, 0.16, GameSettings.mobile_btn_opacity)
		else:
			node.modulate = Color(1.0, 1.0, 1.0, GameSettings.mobile_btn_opacity)

func _build_hud_layout_editor() -> void:
	hud_editor_panel = Control.new()
	hud_editor_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_editor_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_editor_panel.visible = false
	hud_editor_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_editor_panel)

	var top_box := PanelContainer.new()
	hud_editor_top_box = top_box
	top_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_box.offset_left = 30
	top_box.offset_top = 10
	top_box.offset_right = -30
	top_box.offset_bottom = 96
	top_box.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb_top := StyleBoxFlat.new()
	sb_top.bg_color = Color(0.08, 0.1, 0.14, 0.94)
	sb_top.border_color = UITheme.ACCENT_COLOR
	sb_top.set_border_width_all(2)
	sb_top.set_corner_radius_all(10)
	sb_top.content_margin_top = 6
	sb_top.content_margin_bottom = 6
	sb_top.content_margin_left = 14
	sb_top.content_margin_right = 14
	top_box.add_theme_stylebox_override("panel", sb_top)
	hud_editor_panel.add_child(top_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	top_box.add_child(vbox)

	var info := Label.new()
	info.text = "Перетаскивай кнопки пальцем. Выбери кнопку для изменения размера:"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 13)
	vbox.add_child(info)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(hbox)

	var lbl_sz := Label.new()
	lbl_sz.text = "Размер:"
	lbl_sz.add_theme_font_size_override("font_size", 13)
	hbox.add_child(lbl_sz)

	hud_scale_slider = HSlider.new()
	hud_scale_slider.custom_minimum_size = Vector2(160, 32)
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
	btn_reset.custom_minimum_size = Vector2(90, 36)
	btn_reset.pressed.connect(_reset_mobile_hud_layout)
	hbox.add_child(btn_reset)

	var btn_save := Button.new()
	btn_save.text = "Сохранить и выйти"
	btn_save.theme_type_variation = "AccentButton"
	btn_save.custom_minimum_size = Vector2(170, 36)
	btn_save.pressed.connect(func():
		_save_mobile_hud_layout()
		_close_hud_editor()
	)
	hbox.add_child(btn_save)

func _open_hud_editor() -> void:
	is_editing_hud = true
	if pause_menu: pause_menu.hide()
	if settings_menu: settings_menu.hide()
	if top_bar_ctrl: top_bar_ctrl.visible = false
	if mobile_controls_layer: mobile_controls_layer.visible = true
	hud_editor_panel.show()
	move_child(hud_editor_panel, get_child_count() - 1)
	_update_mobile_buttons_visual()

func _close_hud_editor() -> void:
	is_editing_hud = false
	_dragging_btn_id = ""
	selected_hud_btn_id = ""
	hud_editor_panel.hide()
	if top_bar_ctrl and _is_mobile(): top_bar_ctrl.visible = true
	_update_mobile_buttons_visual()
	if settings_menu:
		_update_settings_menu_size()
		settings_menu.show()
		settings_menu.mouse_filter = Control.MOUSE_FILTER_STOP
		move_child(settings_menu, get_child_count() - 1)

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

func _apply_saved_settings_on_start() -> void:
	GameSettings.apply_to_engine(get_viewport(), _get_env())
	GameSettings.apply_to_player(player)
	if debug_label:
		debug_label.visible = GameSettings.show_debug
	if ammo_label:
		ammo_label.visible = not GameSettings.show_ammo_3d
	if option_res and GameSettings.res_index >= 0 and GameSettings.res_index < current_res_list.size():
		option_res.selected = GameSettings.res_index
		_apply_game_resolution(current_res_list[GameSettings.res_index])
	if GameSettings.potato_mode and not is_potato_mode:
		_toggle_potato_mode()
	_apply_crosshair_settings()

func _apply_crosshair_settings() -> void:
	if crosshair_view:
		crosshair_view.modulate = GameSettings.get_crosshair_color()
		crosshair_view.scale = Vector2.ONE * GameSettings.crosshair_scale

func toggle_weapon_wheel() -> void:
	if weapon_wheel:
		if weapon_wheel.is_open:
			weapon_wheel.close()
			if not is_paused and not _is_mobile():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			if crosshair_view:
				crosshair_view.visible = true
		else:
			weapon_wheel.open()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if crosshair_view:
				crosshair_view.visible = false

func is_weapon_wheel_open() -> bool:
	return weapon_wheel != null and weapon_wheel.is_open

func handle_weapon_wheel_touch(pressed: bool, pos: Vector2 = Vector2.ZERO) -> void:
	if pressed:
		_wheel_touch_active = true
		_wheel_touch_origin = pos
		_wheel_touch_has_moved = false
		_wheel_touch_time = Time.get_ticks_msec() / 1000.0
		if weapon_wheel:
			weapon_wheel.open(pos)
			if crosshair_view:
				crosshair_view.visible = false
	else:
		if not _wheel_touch_active:
			return
		_wheel_touch_active = false
		var duration: float = (Time.get_ticks_msec() / 1000.0) - _wheel_touch_time
		if weapon_wheel and weapon_wheel.is_open:
			if not _wheel_touch_has_moved and duration < 0.25:
				# Быстрый одиночный тап — переключаем на следующее оружие без зависания
				weapon_wheel.close_without_select()
				if player and player.has_method("cycle_weapon"):
					player.cycle_weapon()
			else:
				# Удержание со свайпом — экипируем оружие из подсвеченного сектора
				weapon_wheel.close()

		if not is_paused and not _is_mobile():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if crosshair_view:
			crosshair_view.visible = true

func handle_weapon_wheel_drag(pos: Vector2) -> void:
	if not _wheel_touch_active or not weapon_wheel or not weapon_wheel.is_open:
		return
	var delta := pos - _wheel_touch_origin
	if delta.length() > 18.0:
		_wheel_touch_has_moved = true
		weapon_wheel.update_selection_from_vector(delta)
