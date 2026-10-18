class_name GameSettings
extends RefCounted

const CFG_PATH: String = "user://settings.cfg"
static var is_loaded: bool = false

# Управление
static var mouse_sensitivity: float = 0.003
static var ads_mouse_multiplier: float = 0.6
static var touch_sensitivity: float = 0.005
static var invert_y: bool = false
static var crouch_toggle_mode: bool = false
static var camera_shake: float = 1.0
static var mobile_btn_opacity: float = 0.9

# Графика
static var fullscreen: bool = false
static var vsync: bool = true
static var aspect_index: int = 0
static var res_index: int = 0
static var scaling_mode: int = 0 # 0 = Bilinear, 1 = FSR 1.0
static var fsr_sharpness: float = 0.8
static var render_scale: float = 1.0
static var base_fov: float = 75.0
static var shadow_quality: int = 2 # 0=Выкл, 1=Низк, 2=Сред, 3=Выс
static var msaa: int = 0
static var fxaa: bool = false
static var glow: bool = true
static var ssao: bool = false
static var ssr: bool = false
static var fps_limit_idx: int = 0
static var potato_mode: bool = false

# Прицел
static var crosshair_color_idx: int = 0 # 0=Белый, 1=Зеленый, 2=Бирюзовый, 3=Оранжевый, 4=Желтый
static var crosshair_dot: bool = false
static var crosshair_dynamic: bool = true
static var crosshair_scale: float = 1.0

# Аудио
static var master_volume: float = 1.0
static var sfx_volume: float = 1.0
static var ui_volume: float = 1.0
static var hitmarker_sound: bool = true

# Расширения
static var show_debug: bool = false
static var show_ammo_3d: bool = false

static func ensure_loaded() -> void:
	if not is_loaded:
		load_from_disk()

static func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "ads_mouse_multiplier", ads_mouse_multiplier)
	cfg.set_value("controls", "touch_sensitivity", touch_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "crouch_toggle_mode", crouch_toggle_mode)
	cfg.set_value("controls", "camera_shake", camera_shake)
	cfg.set_value("controls", "mobile_btn_opacity", mobile_btn_opacity)

	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "aspect_index", aspect_index)
	cfg.set_value("video", "res_index", res_index)
	cfg.set_value("video", "scaling_mode", scaling_mode)
	cfg.set_value("video", "fsr_sharpness", fsr_sharpness)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "base_fov", base_fov)
	cfg.set_value("video", "shadow_quality", shadow_quality)
	cfg.set_value("video", "msaa", msaa)
	cfg.set_value("video", "fxaa", fxaa)
	cfg.set_value("video", "glow", glow)
	cfg.set_value("video", "ssao", ssao)
	cfg.set_value("video", "ssr", ssr)
	cfg.set_value("video", "fps_limit_idx", fps_limit_idx)
	cfg.set_value("video", "potato_mode", potato_mode)

	cfg.set_value("crosshair", "color_idx", crosshair_color_idx)
	cfg.set_value("crosshair", "dot", crosshair_dot)
	cfg.set_value("crosshair", "dynamic", crosshair_dynamic)
	cfg.set_value("crosshair", "scale", crosshair_scale)

	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "ui", ui_volume)
	cfg.set_value("audio", "hitmarker", hitmarker_sound)

	cfg.set_value("ext", "show_debug", show_debug)
	cfg.set_value("ext", "show_ammo_3d", show_ammo_3d)

	for act in ["move_forward", "move_back", "move_left", "move_right", "ui_accept", "crouch", "sprint", "reload", "fire", "ads"]:
		if InputMap.has_action(act):
			for ev in InputMap.action_get_events(act):
				if ev is InputEventKey:
					cfg.set_value("keys", act, int(ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode))
					break
	cfg.save(CFG_PATH)

static func load_from_disk() -> void:
	is_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	ads_mouse_multiplier = float(cfg.get_value("controls", "ads_mouse_multiplier", ads_mouse_multiplier))
	touch_sensitivity = float(cfg.get_value("controls", "touch_sensitivity", touch_sensitivity))
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	crouch_toggle_mode = bool(cfg.get_value("controls", "crouch_toggle_mode", crouch_toggle_mode))
	camera_shake = float(cfg.get_value("controls", "camera_shake", camera_shake))
	mobile_btn_opacity = float(cfg.get_value("controls", "mobile_btn_opacity", mobile_btn_opacity))

	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	aspect_index = int(cfg.get_value("video", "aspect_index", aspect_index))
	res_index = int(cfg.get_value("video", "res_index", res_index))
	scaling_mode = int(cfg.get_value("video", "scaling_mode", scaling_mode))
	fsr_sharpness = float(cfg.get_value("video", "fsr_sharpness", fsr_sharpness))
	render_scale = float(cfg.get_value("video", "render_scale", render_scale))
	base_fov = float(cfg.get_value("video", "base_fov", base_fov))
	shadow_quality = int(cfg.get_value("video", "shadow_quality", shadow_quality))
	msaa = int(cfg.get_value("video", "msaa", msaa))
	fxaa = bool(cfg.get_value("video", "fxaa", fxaa))
	glow = bool(cfg.get_value("video", "glow", glow))
	ssao = bool(cfg.get_value("video", "ssao", ssao))
	ssr = bool(cfg.get_value("video", "ssr", ssr))
	fps_limit_idx = int(cfg.get_value("video", "fps_limit_idx", fps_limit_idx))
	potato_mode = bool(cfg.get_value("video", "potato_mode", potato_mode))

	crosshair_color_idx = int(cfg.get_value("crosshair", "color_idx", crosshair_color_idx))
	crosshair_dot = bool(cfg.get_value("crosshair", "dot", crosshair_dot))
	crosshair_dynamic = bool(cfg.get_value("crosshair", "dynamic", crosshair_dynamic))
	crosshair_scale = float(cfg.get_value("crosshair", "scale", crosshair_scale))

	master_volume = float(cfg.get_value("audio", "master", master_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	ui_volume = float(cfg.get_value("audio", "ui", ui_volume))
	hitmarker_sound = bool(cfg.get_value("audio", "hitmarker", hitmarker_sound))

	show_debug = bool(cfg.get_value("ext", "show_debug", show_debug))
	show_ammo_3d = bool(cfg.get_value("ext", "show_ammo_3d", show_ammo_3d))

	if cfg.has_section("keys"):
		for act in cfg.get_section_keys("keys"):
			var kcode: int = int(cfg.get_value("keys", act, 0))
			if kcode > 0 and InputMap.has_action(act):
				var old_events := InputMap.action_get_events(act)
				for ev in old_events:
					if ev is InputEventKey:
						InputMap.action_erase_event(act, ev)
				var new_ev := InputEventKey.new()
				new_ev.keycode = kcode as Key
				InputMap.action_add_event(act, new_ev)

static func get_crosshair_color() -> Color:
	match crosshair_color_idx:
		1: return Color(0.2, 1.0, 0.3, 0.95) # Зеленый
		2: return Color(0.2, 0.95, 1.0, 0.95) # Бирюзовый
		3: return Color(1.0, 0.54, 0.16, 0.95) # Оранжевый
		4: return Color(1.0, 0.95, 0.2, 0.95) # Желтый
		_: return Color(1.0, 1.0, 1.0, 0.9) # Белый

static func apply_to_engine(vp: Viewport, env: Environment = null) -> void:
	ensure_loaded()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	var is_mobile_os: bool = OS.get_name() in ["Android", "iOS"]
	if not is_mobile_os:
		var cur_mode := DisplayServer.window_get_mode()
		var is_cur_fs: bool = (cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		if fullscreen != is_cur_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var fps_caps: Array[int] = [0, 30, 60, 120, 144, 240]
	if fps_limit_idx >= 0 and fps_limit_idx < fps_caps.size():
		Engine.max_fps = fps_caps[fps_limit_idx]

	match shadow_quality:
		0: RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		1: RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
		2: RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		3: RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)

	if vp:
		vp.msaa_3d = msaa as Viewport.MSAA
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scaling_mode == 1 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.fsr_sharpness = 2.0 - clampf(fsr_sharpness, 0.0, 2.0)
		vp.scaling_3d_scale = 0.5 if potato_mode else render_scale
		var dir_lights := vp.get_tree().root.find_children("*", "DirectionalLight3D", true, false)
		for dl in dir_lights:
			if dl is DirectionalLight3D:
				dl.shadow_enabled = (shadow_quality > 0) and not potato_mode

	if env:
		env.glow_enabled = glow and not potato_mode
		env.ssao_enabled = ssao and not potato_mode
		env.ssr_enabled = ssr and not potato_mode

static func apply_to_player(p: Node) -> void:
	if not is_instance_valid(p):
		return
	ensure_loaded()
	p.mouse_sensitivity = mouse_sensitivity
	p.ads_mouse_multiplier = ads_mouse_multiplier
	p.touch_sensitivity = touch_sensitivity
	p.crouch_toggle_mode = crouch_toggle_mode
	if "invert_y" in p:
		p.invert_y = invert_y
	if "base_fov" in p:
		p.base_fov = base_fov
	if p.has_method("set_show_ammo_on_weapon"):
		p.set_show_ammo_on_weapon(show_ammo_3d)
