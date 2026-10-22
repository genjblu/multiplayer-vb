extends CharacterBody3D

signal health_changed(new_health: int)
signal ammo_changed(current: int, reserve: int)
signal hit_target(is_headshot: bool)
signal damage_taken(amount: int, attacker_dir: Vector3)
signal weapon_changed(weapon_name: String)

const SoundFX = preload("res://scripts/sound_effects.gd")

enum WeaponType { PISTOL, ASSAULT, SHOTGUN, SNIPER }

@export var max_health: int = 100
@export var base_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5

@export_group("Приседание")
@export var crouch_speed: float = 2.5
@export var crouch_height: float = 1.2
@export var standing_height: float = 2.0
@export var crouch_head_y: float = 0.9
@export var standing_head_y: float = 1.6
@export var crouch_transition_speed: float = 10.0

@export_group("Подкат (Slide)")
## Длительность подката в секундах
@export var slide_duration: float = 0.6
## Множитель скорости подката относительно base_speed
@export var slide_speed_multiplier: float = 2.2

@export_group("Паркур (Titanfall Style)")
@export var wall_run_enabled: bool = true
@export var wall_run_speed: float = 9.5
@export var wall_run_max_duration: float = 2.2
@export var wall_run_gravity_scale: float = 0.16
@export var wall_jump_up_velocity: float = 5.6
@export var wall_jump_push_force: float = 6.2
@export var wall_jump_forward_force: float = 6.5
@export var wall_camera_tilt_deg: float = 14.0
@export var double_jump_enabled: bool = true
@export var double_jump_velocity: float = 5.2
@export var mantle_enabled: bool = true
@export var mantle_duration: float = 0.28

@export var mouse_sensitivity: float = 0.003
@export var ads_mouse_multiplier: float = 0.6
@export var touch_sensitivity: float = 0.005
## Доля ширины экрана слева, где касания НЕ вращают камеру (зона джойстика)
@export var look_zone_start: float = 0.4
@export var scope_overlay: Control # Ссылка на ноду ScopeOverlay из HUD

const DEFAULT_WEAPON_PATHS: Array[String] = ["res://weapons/pistol.tres", "res://weapons/assault.tres", "res://weapons/shotgun.tres", "res://weapons/sniper.tres"]
const SCOPED_SPEED_PENALTY: float = 0.42 # Замедление до 42% скорости при зуме
# Порядок такой же, как в enum WeaponType: пистолет, автомат, дробовик, снайперка
@export var weapon_data: Array[WeaponData] = []
var weapon_holder: Node3D = null
var current_view: Node3D = null
var show_ammo_on_weapon: bool = false
var invert_y: bool = false
var base_fov: float = 75.0

var current_weapon: WeaponType = WeaponType.ASSAULT
var weapon_stats = {
	WeaponType.PISTOL: {
		"name": "Пистолет",
		"damage": 22,
		"max_ammo": 15,
		"reserve": 60,
		"recoil": 0.004	,
		"ads_fov": 55.0,
		"mesh_size": Vector3(0.08, 0.08, 0.4),
		"hip_pos": Vector3(0.18, -0.22, -0.35),
		"ads_pos": Vector3(0, -0.12, -0.3)
	},
	WeaponType.ASSAULT: {
		"name": "Автомат",
		"damage": 25,
		"max_ammo": 30,
		"reserve": 90,
		"recoil": 0.007,
		"ads_fov": 45.0,
		"mesh_size": Vector3(0.1, 0.1, 0.7),
		"hip_pos": Vector3(0.2, -0.2, -0.4),
		"ads_pos": Vector3(0.08, -0.17, -0.35)
	},
	WeaponType.SHOTGUN: {
		"name": "Дробовик",
		"damage": 15,
		"pellets": 6,
		"max_ammo": 8,
		"reserve": 32,
		"recoil": 0.02,
		"ads_fov": 60.0,
		"mesh_size": Vector3(0.12, 0.12, 0.8),
		"hip_pos": Vector3(0.22, -0.24, -0.45),
		"ads_pos": Vector3(0, -0.14, -0.38)
	},
	WeaponType.SNIPER: {
		"name": "Снайперская винтовка",
		"damage": 95,
		"max_ammo": 5,
		"reserve": 20,
		"recoil": 0.03,
		"ads_fov": 20.0,
		"mesh_size": Vector3(0.08, 0.08, 1.1),
		"hip_pos": Vector3(0.22, -0.22, -0.5),
		"ads_pos": Vector3(0, -0.13, -0.4)
	}
}

var next_shot_time: float = 0.0
@export var spawn_protection_time: float = 2.0
var invulnerable_until: float = 0.0
var reload_id: int = 0
var ammo_state: Dictionary = {}
var _weapon_initialized: bool = false
var max_ammo: int = 30
var current_spread_deg: float = 0.5
var fire_bloom: float = 0.0
var is_crouching: bool = false
var _fallback_weapon_data: WeaponData = WeaponData.new()
var current_ammo: int = 30
var reserve_ammo: int = 90
var sync_position: Vector3
var sync_rotation: Vector3
var sync_flags: int = 0
var remote_walk_cycle: float = 0.0
var health: int = 100
var is_reloading: bool = false
var is_ads: bool = false
var is_sprinting: bool = false
var is_sliding: bool = false
var slide_timer: float = 0.0
var slide_vector: Vector2 = Vector2.ZERO
var reload_pending: bool = false
var touch_crouch: bool = false
var crouch_toggle_mode: bool = false
var _crouch_toggled: bool = false
var collision_shape: CollisionShape3D = null
var default_capsule_height: float = 2.0
var mobile_hud_buttons: Dictionary = {} # action_name -> Control
var is_cycling_bolt: bool = false

# --- Паркур (Wall Run, Double Jump, Mantle) ---
var is_wall_running: bool = false
var wall_run_side: int = 0 # -1 = слева, 1 = справа
var wall_run_normal: Vector3 = Vector3.ZERO
var wall_run_dir: Vector3 = Vector3.ZERO
var wall_run_timer: float = 0.0
var wall_run_cooldown_normal: Vector3 = Vector3.ZERO
var wall_run_cooldown_timer: float = 0.0
var _wall_step_timer: float = 0.0
var can_double_jump: bool = false

var is_mantling: bool = false
var mantle_timer: float = 0.0
var mantle_start_pos: Vector3 = Vector3.ZERO
var mantle_target_pos: Vector3 = Vector3.ZERO

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var touch_look_index: int = -1
var recoil_pitch: float = 0.0

var fire_timer: float = 0.0
@export var assault_fire_rate: float = 0.12  # интервал между выстрелами автомата (сек)
var is_firing: bool = false
var touch_fire: bool = false

# --- Мобильное управление ---
var is_mobile: bool = false
var touch_move: Vector2 = Vector2.ZERO
var touch_sprint: bool = false
var touch_ads: bool = false
var touch_jump_req: bool = false
var touch_crouch_req: bool = false
var touch_buttons: Dictionary = {"FireButton": "fire", "JumpButton": "jump"}
var button_touches: Dictionary = {}  # индекс пальца -> действие

@onready var head: Node3D = $Head
@onready var camera: Camera3D = %Camera3D
@onready var weapon_ray: RayCast3D = %WeaponRay
@onready var muzzle_flash: OmniLight3D = %MuzzleFlash
@onready var weapon_pistol: MeshInstance3D = $Head/Camera3D/WeaponPistol
@onready var weapon_assault: MeshInstance3D = $Head/Camera3D/WeaponAssault
@onready var weapon_shotgun: MeshInstance3D = $Head/Camera3D/WeaponShotgun
@onready var weapon_sniper: MeshInstance3D = $Head/Camera3D/WeaponSniper
@onready var touch_ui: CanvasLayer = %TouchUI
@onready var synchronizer: MultiplayerSynchronizer = %MultiplayerSynchronizer
var gunshot_sound_3d: AudioStreamPlayer3D = null
var footstep_sound_3d: AudioStreamPlayer3D = null
var _step_distance_accum: float = 0.0
var _was_on_floor: bool = true
var _fall_velocity: float = 0.0
var remote_step_distance_accum: float = 0.0

func _init() -> void:
	if not InputMap.has_action("reload"):
		InputMap.add_action("reload")
		var ev = InputEventKey.new()
		ev.keycode = KEY_R
		InputMap.action_add_event("reload", ev)
	if not InputMap.has_action("sprint"):
		InputMap.add_action("sprint")
		var ev = InputEventKey.new()
		ev.keycode = KEY_SHIFT
		InputMap.action_add_event("sprint", ev)
	if not InputMap.has_action("crouch"):
		InputMap.add_action("crouch")
		var ev = InputEventKey.new()
		ev.keycode = KEY_CTRL
		InputMap.action_add_event("crouch", ev)
	if not InputMap.has_action("ads"):
		InputMap.add_action("ads")
		var ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("ads", ev)
	if not InputMap.has_action("weapon_wheel"):
		InputMap.add_action("weapon_wheel")
		var ev = InputEventKey.new()
		ev.keycode = KEY_Q
		InputMap.action_add_event("weapon_wheel", ev)
	for i in range(4):
		var act = "weapon_%d" % (i + 1)
		if not InputMap.has_action(act):
			InputMap.add_action(act)
			var ev = InputEventKey.new()
			ev.keycode = KEY_1 + i
			InputMap.action_add_event(act, ev)

func _enter_tree() -> void:
	var peer_id: int = name.to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id)
		if has_node("MultiplayerSynchronizer"):
			$MultiplayerSynchronizer.set_multiplayer_authority(peer_id)

func is_local_player() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return is_multiplayer_authority()

func _ready() -> void:
	if not is_in_group("players"):
		add_to_group("players")
	if scope_overlay == null:
		scope_overlay = get_node_or_null("TouchUI/TouchOverlay/HUDContainer/ScopeOverlay") as Control
	if scope_overlay:
		scope_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_make_click_through(scope_overlay)
	# Цвет должен обновляться ДЛЯ ВСЕХ игроков (и своих, и чужих) ДО всяких return!
	if not GameStats.stats_changed.is_connected(_update_body_color):
		GameStats.stats_changed.connect(_update_body_color)
	_update_body_color()
	
	if not ammo_changed.is_connected(_sync_weapon_ammo_3d):
		ammo_changed.connect(_sync_weapon_ammo_3d)
	_load_weapon_data()
	_setup_weapon_holder()
	_setup_audio_players()
	_reset_all_ammo()
	_switch_weapon(WeaponType.ASSAULT)
	health = max_health
	collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		default_capsule_height = (collision_shape.shape as CapsuleShape3D).height
	else:
		default_capsule_height = standing_height

	if weapon_ray:
		weapon_ray.add_exception(self)

	if not is_local_player():
		camera.clear_current()
		touch_ui.hide()
		return

	camera.make_current()
	if multiplayer.has_multiplayer_peer():
		GameStats.register_name.rpc_id(1, GameStats.local_nick)
	# Своё 3D-тело скрываем для себя в виде от первого лица (чтобы голова не перекрывала камеру)
	var soldier = get_node_or_null("SoldierModel")
	if soldier:
		soldier.visible = not is_local_player()
	var body_mesh = get_node_or_null("MeshInstance3D")
	if body_mesh:
		body_mesh.visible = not is_local_player()

	GameSettings.apply_to_player(self)
	health_changed.emit(health)
	ammo_changed.emit(current_ammo, reserve_ammo)

	if not GameStats.stats_changed.is_connected(_update_body_color):
		GameStats.stats_changed.connect(_update_body_color)
	_update_body_color()

	is_mobile = OS.get_name() in ["Android", "iOS"]

	# HUD (прицел, здоровье, патроны) показываем всегда
	touch_ui.show()

	# Сенсорные элементы (кнопки, джойстик) только на мобильных.
	# HUDContainer лежит внутри TouchOverlay, поэтому скрываем детей по отдельности.
	var overlay: Node = touch_ui.get_node_or_null("TouchOverlay")
	if overlay:
		overlay.visible = true
		for child in overlay.get_children():
			if child is CanvasItem and child.name != "HUDContainer":
				child.visible = is_mobile

	if is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	

var current_weapon_node: Node3D = null

func _switch_weapon(type: WeaponType) -> void:
	# Запоминаем патроны прежнего оружия
	if _weapon_initialized:
		ammo_state[current_weapon] = {"mag": current_ammo, "reserve": reserve_ammo}
	# Смена оружия отменяет незавершённую перезарядку
	reload_id += 1
	reload_pending = false
	is_reloading = false
	current_weapon = type
	var stats = weapon_stats[current_weapon]
	max_ammo = stats["max_ammo"]
	var saved: Dictionary = ammo_state.get(current_weapon, {"mag": max_ammo, "reserve": stats["reserve"]})
	current_ammo = saved["mag"]
	reserve_ammo = saved["reserve"]
	_weapon_initialized = true

	# Убираем сцену предыдущего оружия, если она была
	if is_instance_valid(current_view):
		current_view.queue_free()
	current_view = null

	if weapon_pistol:
		weapon_pistol.visible = false
		weapon_pistol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if weapon_assault:
		weapon_assault.visible = false
		weapon_assault.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if weapon_shotgun:
		weapon_shotgun.visible = false
		weapon_shotgun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if weapon_sniper:
		weapon_sniper.visible = false
		weapon_sniper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	match current_weapon:
		WeaponType.PISTOL:
			current_weapon_node = weapon_pistol
		WeaponType.ASSAULT:
			current_weapon_node = weapon_assault
		WeaponType.SHOTGUN:
			current_weapon_node = weapon_shotgun
		WeaponType.SNIPER:
			current_weapon_node = weapon_sniper

	var view_scene: PackedScene = stats.get("view_scene", null)
	if view_scene != null:
		# Сцена оружия с анимациями
		current_view = view_scene.instantiate() as Node3D
		if is_local_player():
			if weapon_holder != null:
				weapon_holder.add_child(current_view)
				current_view.position = stats.get("hip_pos", Vector3(0.2, -0.2, -0.4))
				current_view.rotation = Vector3.ZERO
			current_weapon_node = current_view
			if current_view.has_method("setup_ammo_3d_params"):
				var a_off: Vector3 = stats.get("ammo_3d_offset", Vector3(-0.06, 0.05, -0.18))
				var a_rot: Vector3 = stats.get("ammo_3d_rotation_deg", Vector3.ZERO)
				var a_font: int = stats.get("ammo_3d_font_size", 96)
				var a_scale: float = stats.get("ammo_3d_scale", 0.0005)
				current_view.call("setup_ammo_3d_params", a_off, a_rot, a_font, a_scale)
			_sync_weapon_ammo_3d(current_ammo, reserve_ammo)
			_setup_robot_viewmodel_hands(current_view)
			_update_viewmodel_hands_visibility()
		else:
			# Для удалённых игроков оружие крепится прямо к правой руке 3D-модели робота (SoldierModel)
			var soldier: SoldierModel = get_node_or_null("SoldierModel") as SoldierModel
			var mount: Node3D = soldier.get_weapon_mount() if (soldier and soldier.has_method("get_weapon_mount")) else null
			if mount != null:
				mount.add_child(current_view)
				current_view.position = Vector3.ZERO
				current_view.rotation = Vector3.ZERO
			elif weapon_holder != null:
				weapon_holder.add_child(current_view)
			current_weapon_node = current_view
			_update_viewmodel_hands_visibility()
	elif current_weapon_node:
		# Старый способ: узел-заглушка (запасной вариант)
		current_weapon_node.visible = true
		current_weapon_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var old_mesh := current_weapon_node as MeshInstance3D
		if old_mesh and old_mesh.mesh is BoxMesh:
			var box: BoxMesh = old_mesh.mesh as BoxMesh
			box.size = stats["mesh_size"]

	ammo_changed.emit(current_ammo, reserve_ammo)
	weapon_changed.emit(stats["name"])

func refill_ammo() -> void:
	for w in weapon_stats.keys():
		var stats = weapon_stats[w]
		ammo_state[w] = {"mag": stats["max_ammo"], "reserve": stats["reserve"] * 2}
	var cur_stats = weapon_stats[current_weapon]
	current_ammo = cur_stats["max_ammo"]
	reserve_ammo = cur_stats["reserve"] * 2
	ammo_changed.emit(current_ammo, reserve_ammo)

func switch_weapon_by_index(idx: int) -> void:
	if idx >= 0 and idx < WeaponType.size():
		_switch_weapon(idx as WeaponType)

func _sync_weapon_ammo_3d(current: int, reserve: int) -> void:
	if is_instance_valid(current_view):
		if current_view.has_method("set_ammo_display"):
			current_view.call("set_ammo_display", current, reserve)
		if current_view.has_method("set_ammo_3d_visible"):
			current_view.call("set_ammo_3d_visible", show_ammo_on_weapon and is_local_player())
	elif is_instance_valid(current_weapon_node):
		var lbl: Label3D = current_weapon_node.get_node_or_null("BoxAmmoLabel3D") as Label3D
		if show_ammo_on_weapon and is_local_player():
			if lbl == null:
				lbl = Label3D.new()
				lbl.name = "BoxAmmoLabel3D"
				lbl.font_size = 80
				lbl.outline_size = 20
				lbl.pixel_size = 0.0006
				lbl.no_depth_test = true
				lbl.position = Vector3(0, 0.1, 0)
				current_weapon_node.add_child(lbl)
			lbl.visible = true
			lbl.text = "%d/%d" % [current, reserve]
		elif lbl != null:
			lbl.visible = false

func cycle_weapon() -> void:
	if is_reloading:
		return
	var weapons = [WeaponType.PISTOL, WeaponType.ASSAULT, WeaponType.SHOTGUN, WeaponType.SNIPER]
	var idx = weapons.find(current_weapon)
	idx = (idx + 1) % weapons.size()
	_switch_weapon(weapons[idx])
	
func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player():
		return

	# На телефоне игнорируем мышиные события, которые Godot эмулирует из касаний
	if is_mobile and event is InputEventMouse:
		return

	if event.is_action_pressed("fire") and not is_reloading and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or is_mobile):
		shoot()

	if event.is_action_pressed("reload") and not is_reloading and current_ammo < max_ammo and reserve_ammo > 0:
		reload()

	if event.is_action_pressed("weapon_1"): _switch_weapon(WeaponType.PISTOL)
	if event.is_action_pressed("weapon_2"): _switch_weapon(WeaponType.ASSAULT)
	if event.is_action_pressed("weapon_3"): _switch_weapon(WeaponType.SHOTGUN)
	if event.is_action_pressed("weapon_4"): _switch_weapon(WeaponType.SNIPER)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var current_sens: float = mouse_sensitivity * (ads_mouse_multiplier if is_ads else 1.0)
		_rotate_camera(event.relative * current_sens)
		
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		print("touch ", event.index, " ", event.pressed, " ", event.position, " mobile=", is_mobile)
		
	if not is_local_player() or not is_mobile:
		return

	if touch_ui:
		if ("is_paused" in touch_ui and touch_ui.is_paused) or ("is_editing_hud" in touch_ui and touch_ui.is_editing_hud):
			return

	if event is InputEventScreenTouch:
		if event.pressed:
			var act: String = _button_action_at(event.position)
			if act != "":
				button_touches[event.index] = act
				touch_action(act, true, event.position)
				return
			if touch_ui and touch_ui.has_method("is_weapon_wheel_open") and touch_ui.is_weapon_wheel_open():
				return
			var screen_w: float = get_viewport().get_visible_rect().size.x
			if touch_look_index == -1 \
					and event.position.x > screen_w * look_zone_start \
					and not _is_over_joystick(event.position):
				touch_look_index = event.index
		else:
			if button_touches.has(event.index):
				var act: String = button_touches[event.index]
				touch_action(act, false, event.position)
				button_touches.erase(event.index)
			elif event.index == touch_look_index:
				touch_look_index = -1

	elif event is InputEventScreenDrag:
		var act: String = button_touches.get(event.index, "")
		if act == "cycle_weapon":
			if touch_ui and touch_ui.has_method("handle_weapon_wheel_drag"):
				touch_ui.handle_weapon_wheel_drag(event.position)
			return
		# Вращаем камеру, если тянет палец обзора ИЛИ палец, зажимающий кнопку стрельбы (Aim While Firing)
		var is_fire_finger: bool = act == "fire"
		if event.index == touch_look_index or is_fire_finger:
			_rotate_camera(event.relative * touch_sensitivity)

func _node_rect(n: Node) -> Rect2:
	if n is Control:
		return (n as Control).get_global_rect()
	if n is TouchScreenButton:
		var b := n as TouchScreenButton
		var sc: Vector2 = b.global_scale
		if b.texture_normal:
			return Rect2(b.global_position, b.texture_normal.get_size() * sc)
		if b.shape is RectangleShape2D:
			var s: Vector2 = (b.shape as RectangleShape2D).size * sc
			return Rect2(b.global_position - s / 2.0, s)
		if b.shape is CircleShape2D:
			var r: float = (b.shape as CircleShape2D).radius * maxf(sc.x, sc.y)
			return Rect2(b.global_position - Vector2(r, r), Vector2(r, r) * 2.0)
	return Rect2()

func _button_action_at(pos: Vector2) -> String:
	for act_name in mobile_hud_buttons.keys():
		var ctrl: Control = mobile_hud_buttons[act_name]
		if is_instance_valid(ctrl) and ctrl.visible and ctrl.get_global_rect().has_point(pos):
			return act_name
	var overlay: Node = touch_ui.get_node_or_null("TouchOverlay")
	if overlay == null:
		return ""
	for btn_name in touch_buttons:
		var n: Node = overlay.get_node_or_null(btn_name)
		if n and n.visible and _node_rect(n).has_point(pos):
			return touch_buttons[btn_name]
	return ""

func _is_over_joystick(pos: Vector2) -> bool:
	var n: Node = touch_ui.get_node_or_null("TouchOverlay/JoystickBase")
	return n != null and _node_rect(n).has_point(pos)
func touch_action(action: String, pressed: bool, pos: Vector2 = Vector2.ZERO) -> void:
	if not is_local_player():
		return
	if touch_ui:
		if ("is_paused" in touch_ui and touch_ui.is_paused) or ("is_editing_hud" in touch_ui and touch_ui.is_editing_hud):
			return
	match action:
		"fire":
			touch_fire = pressed
			if pressed and not is_reloading and current_weapon != WeaponType.ASSAULT:
				shoot()
		"reload":
			if pressed and not is_reloading and current_ammo < max_ammo and reserve_ammo > 0:
				reload()
		"jump":
			if pressed:
				touch_jump_req = true
		"crouch":
			if crouch_toggle_mode:
				if pressed:
					_crouch_toggled = not _crouch_toggled
					touch_crouch = _crouch_toggled
					touch_crouch_req = true
			else:
				touch_crouch = pressed
				if pressed:
					touch_crouch_req = true
		"sprint":
			touch_sprint = pressed
		"ads":
			if pressed and not is_cycling_bolt:
				touch_ads = not touch_ads
		"cycle_weapon":
			if touch_ui and touch_ui.has_method("handle_weapon_wheel_touch"):
				touch_ui.handle_weapon_wheel_touch(pressed, pos)
			elif pressed:
				cycle_weapon()
		"weapon_1":
			if pressed: _switch_weapon(WeaponType.PISTOL)
		"weapon_2":
			if pressed: _switch_weapon(WeaponType.ASSAULT)
		"weapon_3":
			if pressed: _switch_weapon(WeaponType.SHOTGUN)
		"weapon_4":
			if pressed: _switch_weapon(WeaponType.SNIPER)

func _physics_process(delta: float) -> void:
	var target_speed := base_speed

	# Замедление снайпера в зуме
	if is_ads and current_weapon == WeaponType.SNIPER:
		target_speed *= SCOPED_SPEED_PENALTY
	if not is_local_player():
		var prev_pos := global_position
		# Если дистанция слишком велика (возрождение, телепортация), моментальный перенос без рывка
		if global_position.distance_squared_to(sync_position) > 64.0:
			global_position = sync_position
		else:
			var smooth_weight: float = 1.0 - exp(-22.0 * delta)
			global_position = global_position.lerp(sync_position, smooth_weight)

		var rot_weight: float = 1.0 - exp(-20.0 * delta)
		rotation.y = lerp_angle(rotation.y, sync_rotation.y, rot_weight)
		# sync_rotation: x = наклон головы, y = поворот тела, z = номер оружия
		head.rotation.x = lerp_angle(head.rotation.x, sync_rotation.x, rot_weight)
		var remote_weapon: int = int(round(sync_rotation.z))
		if remote_weapon != int(current_weapon) and weapon_stats.has(remote_weapon):
			_switch_weapon(remote_weapon as WeaponType)

		# Распаковка состояний соперника
		var rem_crouch: bool = bool(sync_flags & (1 << 0))
		var rem_sprint: bool = bool(sync_flags & (1 << 1))
		var rem_slide: bool = bool(sync_flags & (1 << 2))
		var rem_ads: bool = bool(sync_flags & (1 << 3))
		var rem_on_floor: bool = bool(sync_flags & (1 << 4))
		var rem_wall_run: bool = bool(sync_flags & (1 << 5))
		var rem_wall_side: int = -1 if bool(sync_flags & (1 << 6)) else 1
		var rem_mantle: bool = bool(sync_flags & (1 << 7))

		# 1. Приседание и высота коллизии/головы для удалённого игрока
		var target_rem_head_y: float = crouch_head_y if rem_crouch else standing_head_y
		head.position.y = lerpf(head.position.y, target_rem_head_y, delta * crouch_transition_speed)
		if collision_shape and collision_shape.shape is CapsuleShape3D:
			var capsule := collision_shape.shape as CapsuleShape3D
			var target_h: float = crouch_height if rem_crouch else default_capsule_height
			capsule.height = lerpf(capsule.height, target_h, delta * crouch_transition_speed)
			collision_shape.position.y = capsule.height * 0.5

		# Масштаб и позиция меша тела
		var body_m = get_node_or_null("MeshInstance3D") as MeshInstance3D
		if body_m:
			var mesh_target_scale_y: float = (crouch_height / standing_height) if rem_crouch else 1.0
			body_m.scale.y = lerpf(body_m.scale.y, mesh_target_scale_y, delta * crouch_transition_speed)
			body_m.position.y = lerpf(body_m.position.y, mesh_target_scale_y, delta * crouch_transition_speed)

		# 2. Процедурный наклон торса в движении (Slide & Sprint & Wall Run)
		var moved_dist := (global_position - prev_pos).length()
		var rem_speed := moved_dist / maxf(delta, 0.001)
		var target_pitch: float = 0.0
		var target_roll: float = 0.0

		if rem_slide:
			target_pitch = deg_to_rad(28.0) # наклон назад в подкате (отклонение тела назад)
			target_roll = deg_to_rad(4.0)
		elif rem_wall_run:
			target_roll = deg_to_rad(-16.0 * float(rem_wall_side))
			target_pitch = deg_to_rad(-6.0)
		elif rem_sprint and rem_speed > 2.0:
			target_pitch = deg_to_rad(-10.0) # лёгкий наклон вперёд при спринте

		if body_m:
			body_m.rotation.x = lerp_angle(body_m.rotation.x, target_pitch, delta * 12.0)
			body_m.rotation.z = lerp_angle(body_m.rotation.z, target_roll, delta * 12.0)

		# 3. Анимация покачивания (Walk Bobbing) и шаги для удалённого игрока
		if rem_on_floor and rem_speed > 0.5:
			var bob_speed: float = 14.0 if rem_sprint else 9.0
			remote_walk_cycle += delta * bob_speed

			remote_step_distance_accum += rem_speed * delta
			var rem_step_threshold: float = 1.4 if rem_crouch else (2.4 if rem_sprint else 1.8)
			if remote_step_distance_accum >= rem_step_threshold:
				remote_step_distance_accum = 0.0
				if footstep_sound_3d:
					footstep_sound_3d.stream = SoundFX.get_footstep()
					footstep_sound_3d.pitch_scale = randf_range(0.92, 1.08)
					footstep_sound_3d.volume_db = -9.0 if rem_crouch else (2.0 if rem_sprint else -1.0)
					footstep_sound_3d.play()
		else:
			remote_walk_cycle = lerpf(remote_walk_cycle, 0.0, delta * 8.0)
			remote_step_distance_accum = 0.0

		var bob_offset: float = sin(remote_walk_cycle) * (0.04 if rem_sprint else 0.02)
		if body_m:
			body_m.position.y += bob_offset

		# 4. Процедурная анимация low-poly бойца (шаги, колени, присед, подкат, наклон торса, паркур)
		var soldier = get_node_or_null("SoldierModel")
		if soldier and soldier.has_method("update_animation"):
			soldier.update_animation(delta, rem_speed, rem_on_floor, rem_sprint, rem_crouch, rem_slide, head.rotation.x, rem_wall_run, rem_wall_side, rem_mantle)

		# 5. Оружие от 3-го лица для удалённого наблюдателя
		if is_instance_valid(current_view):
			current_view.visible = true
			_update_viewmodel_hands_visibility()
			var mount: Node3D = soldier.get_weapon_mount() if (soldier and soldier.has_method("get_weapon_mount")) else null
			if mount != null and current_view.get_parent() != mount:
				current_view.reparent(mount)
				current_view.position = Vector3.ZERO
				current_view.rotation = Vector3.ZERO

		return

	if global_position.y < -10.0:
		if multiplayer.has_multiplayer_peer():
			GameStats.report_death.rpc_id(1, 0, "", false)
		die()
		return

	# === 0. КАРАБКАНИЕ НА УСТУП (MANTLE) ===
	if is_mantling:
		mantle_timer += delta
		var progress: float = clampf(mantle_timer / maxf(mantle_duration, 0.01), 0.0, 1.0)

		var t_vert: float = ease(progress, -1.8)
		var t_horiz: float = 1.0 - pow(1.0 - progress, 2.0)

		var cur_y: float = lerpf(mantle_start_pos.y, mantle_target_pos.y, t_vert)
		var cur_x: float = lerpf(mantle_start_pos.x, mantle_target_pos.x, t_horiz)
		var cur_z: float = lerpf(mantle_start_pos.z, mantle_target_pos.z, t_horiz)
		global_position = Vector3(cur_x, cur_y, cur_z)
		velocity = Vector3.ZERO

		if mantle_timer >= mantle_duration:
			is_mantling = false
			global_position = mantle_target_pos
			var fwd: Vector3 = -camera.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			if fwd.length_squared() < 0.01:
				fwd = -transform.basis.z
			velocity = fwd * (base_speed * 1.1)
			if footstep_sound_3d:
				footstep_sound_3d.stream = SoundFX.get_jump_land()
				footstep_sound_3d.pitch_scale = randf_range(1.05, 1.15)
				footstep_sound_3d.volume_db = -1.0
				footstep_sound_3d.play()

		camera.rotation.z = lerpf(camera.rotation.z, 0.0, delta * 12.0)
		sync_position = global_position
		sync_rotation = Vector3(head.rotation.x, rotation.y, float(current_weapon))
		sync_flags = (int(is_crouching) << 0) | (int(is_sprinting) << 1) | (int(is_sliding) << 2) | (int(is_ads) << 3) | (int(is_on_floor()) << 4) | (int(is_wall_running) << 5) | (int(wall_run_side < 0) << 6) | (int(is_mantling) << 7)
		_send_rpc_transform_sync(delta)
		return

	if is_mobile:
		# На телефоне игнорируем мышь, эмулируемую из касаний
		is_ads = touch_ads
		is_firing = touch_fire
	else:
		var can_mouse_act: bool = (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
		is_ads = ((Input.is_action_pressed("ads") and can_mouse_act) or touch_ads) and not is_cycling_bolt
		is_firing = (Input.is_action_pressed("fire") and can_mouse_act) or touch_fire
	if current_weapon == WeaponType.ASSAULT and is_firing and not is_reloading:
		fire_timer -= delta
		if fire_timer <= 0.0:
			shoot()
			fire_timer = weapon_stats[current_weapon].get("fire_rate", assault_fire_rate)
	else:
		fire_timer = 0.0

	var stats = weapon_stats[current_weapon]
	var target_fov = stats["ads_fov"] if is_ads else base_fov
	camera.fov = lerp(camera.fov, target_fov, delta * 15.0)

	# Логика оптического оверлея и скрытия винтовки
	if current_weapon == WeaponType.SNIPER and is_local_player():
		if scope_overlay:
			scope_overlay.visible = is_ads
		if current_view:
			current_view.visible = not is_ads
		elif current_weapon_node:
			current_weapon_node.visible = not is_ads
	else:
		if scope_overlay and is_local_player():
			scope_overlay.visible = false
		if current_view:
			current_view.visible = true
		elif current_weapon_node:
			current_weapon_node.visible = true

	var target_weapon_pos: Vector3 = stats.get("ads_pos", Vector3(0, -0.12, -0.35)) if is_ads else stats.get("hip_pos", Vector3(0.2, -0.2, -0.4))
	if current_weapon_node:
		current_weapon_node.position = current_weapon_node.position.lerp(target_weapon_pos, delta * 15.0)
	if not is_on_floor() and not is_wall_running:
		velocity.y -= gravity * delta

	if wall_run_cooldown_timer > 0.0:
		wall_run_cooldown_timer -= delta

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input_dir = (input_dir + touch_move).limit_length(1.0)
	var move_strength: float = input_dir.length()
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var crouch_just_pressed: bool = Input.is_action_just_pressed("crouch") or touch_crouch_req
	touch_crouch_req = false

	if not is_mobile and crouch_toggle_mode and Input.is_action_just_pressed("crouch"):
		_crouch_toggled = not _crouch_toggled

	var crouch_hold: bool = false
	if crouch_toggle_mode:
		crouch_hold = _crouch_toggled
	else:
		crouch_hold = Input.is_action_pressed("crouch") or touch_crouch

	var on_flr: bool = is_on_floor()

	# Обработка паркура в воздухе и на полу
	if on_flr:
		if is_wall_running:
			_end_wall_run(0.1)
		can_double_jump = true
		wall_run_cooldown_normal = Vector3.ZERO
		wall_run_cooldown_timer = 0.0
	else:
		# 1. Проверяем карабкание на уступ (Mantle)
		if mantle_enabled and not is_sliding and not is_crouching:
			if _check_mantle(input_dir):
				return

		# 2. Проверяем бег по стене (Wall Run)
		if is_wall_running:
			_update_active_wall_run(delta, input_dir, crouch_hold)
		elif wall_run_enabled and not is_crouching and not is_sliding:
			_check_wall_run_start(delta, input_dir)

	# Прыжки: со стены (Wall Jump), с пола (Jump), в воздухе (Double Jump)
	var jump_pressed: bool = Input.is_action_just_pressed("ui_accept") or touch_jump_req
	touch_jump_req = false
	if jump_pressed:
		if is_wall_running:
			_perform_wall_jump()
		elif on_flr:
			if is_sliding:
				is_sliding = false
				slide_timer = 0.0
			velocity.y = jump_velocity
			can_double_jump = true
		elif double_jump_enabled and can_double_jump and not is_mantling:
			_perform_double_jump(direction)

	# На телефоне авто-спринт при наклоне джойстика вперёд до упора
	var auto_mobile_sprint: bool = is_mobile and touch_move.y < -0.82
	# Спринт возможен только если мы не приседаем
	is_sprinting = (Input.is_action_pressed("sprint") or touch_sprint or auto_mobile_sprint) \
		and (on_flr or is_wall_running) and not is_ads and not is_sliding and not is_crouching

	if is_sprinting and crouch_toggle_mode:
		_crouch_toggled = false

	# Подкат начинается только если игрок нажал приседание ВО ВРЕМЯ спринта на полу
	if crouch_just_pressed and on_flr and not is_sliding and is_sprinting and input_dir.length() > 0:
		is_sliding = true
		slide_timer = slide_duration
		slide_vector = input_dir.normalized()

	# Проверка препятствия над головой для вставания
	var ceiling_blocked: bool = _has_ceiling_above()

	if is_sliding:
		is_crouching = true
	elif crouch_hold or ceiling_blocked:
		is_crouching = on_flr or is_crouching
	else:
		is_crouching = false

	var current_speed = target_speed
	if is_sprinting:
		current_speed = sprint_speed
	elif is_crouching:
		current_speed = crouch_speed

	if is_wall_running:
		# Движение вдоль стены со скоростью wall_run_speed и легким прижатием к стене
		var target_vel: Vector3 = (wall_run_dir * wall_run_speed) - (wall_run_normal * 1.5)
		velocity.x = lerpf(velocity.x, target_vel.x, delta * 15.0)
		velocity.z = lerpf(velocity.z, target_vel.z, delta * 15.0)

		# Плавное зависание / спуск по стене в стиле Titanfall 2
		if wall_run_timer > (wall_run_max_duration - 0.75):
			velocity.y = move_toward(velocity.y, 0.0, delta * 6.0)
		else:
			velocity.y = move_toward(velocity.y, -3.5, gravity * wall_run_gravity_scale * delta)

		_wall_step_timer += delta
		if _wall_step_timer >= 0.22:
			_wall_step_timer = 0.0
			if footstep_sound_3d:
				footstep_sound_3d.stream = SoundFX.get_footstep()
				footstep_sound_3d.pitch_scale = randf_range(1.15, 1.3)
				footstep_sound_3d.volume_db = 1.0
				footstep_sound_3d.play()
	elif is_sliding:
		slide_timer -= delta
		var progress: float = clampf(slide_timer / maxf(slide_duration, 0.01), 0.0, 1.0)
		var slide_speed: float = base_speed * slide_speed_multiplier * progress
		var forward = (transform.basis * Vector3(slide_vector.x, 0, slide_vector.y)).normalized()
		velocity.x = forward.x * slide_speed
		velocity.z = forward.z * slide_speed
		if slide_timer <= 0.0 or not is_on_floor():
			is_sliding = false
	elif direction:
		velocity.x = direction.x * current_speed * move_strength
		velocity.z = direction.z * current_speed * move_strength
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	# Шаги и приземление локального игрока
	on_flr = is_on_floor()
	if on_flr:
		if not _was_on_floor and _fall_velocity > 3.0:
			if footstep_sound_3d:
				footstep_sound_3d.stream = SoundFX.get_jump_land()
				footstep_sound_3d.pitch_scale = randf_range(0.95, 1.05)
				footstep_sound_3d.volume_db = clampf(-4.0 + (_fall_velocity - 3.0) * 0.8, -4.0, 4.0)
				footstep_sound_3d.play()
		_fall_velocity = 0.0

		var horizontal_vel: float = Vector2(velocity.x, velocity.z).length()
		if horizontal_vel > 0.5:
			_step_distance_accum += horizontal_vel * delta
			var step_threshold: float = 1.4 if is_crouching else (2.4 if is_sprinting else 1.8)
			if _step_distance_accum >= step_threshold:
				_step_distance_accum = 0.0
				if footstep_sound_3d:
					footstep_sound_3d.stream = SoundFX.get_footstep()
					footstep_sound_3d.pitch_scale = randf_range(0.92, 1.08)
					footstep_sound_3d.volume_db = -9.0 if is_crouching else (2.0 if is_sprinting else -1.0)
					footstep_sound_3d.play()
		else:
			_step_distance_accum = lerpf(_step_distance_accum, 0.0, delta * 5.0)
	else:
		_fall_velocity = -velocity.y
	_was_on_floor = on_flr

	_update_crouch_height(delta)
	_update_spread(delta)
	_physics_process_target_info()

	# Наклон камеры (Camera Roll) при беге по стене
	var target_cam_roll: float = 0.0
	if is_wall_running:
		target_cam_roll = deg_to_rad(wall_camera_tilt_deg) if wall_run_side > 0 else deg_to_rad(-wall_camera_tilt_deg)
	camera.rotation.z = lerpf(camera.rotation.z, target_cam_roll, delta * 12.0)

	recoil_pitch = lerp(recoil_pitch, 0.0, delta * 10.0)
	head.rotation.x = clamp(head.rotation.x + recoil_pitch, deg_to_rad(-89), deg_to_rad(89))

	sync_position = global_position
	sync_rotation = Vector3(head.rotation.x, rotation.y, float(current_weapon))
	sync_flags = (int(is_crouching) << 0) | (int(is_sprinting) << 1) | (int(is_sliding) << 2) | (int(is_ads) << 3) | (int(is_on_floor()) << 4) | (int(is_wall_running) << 5) | (int(wall_run_side < 0) << 6) | (int(is_mantling) << 7)
	_send_rpc_transform_sync(delta)

var _net_sync_timer: float = 0.0

func _send_rpc_transform_sync(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	_net_sync_timer += delta
	if _net_sync_timer >= 0.05:
		_net_sync_timer = 0.0
		_rpc_sync_transform.rpc(global_position, sync_rotation, sync_flags)

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_sync_transform(pos: Vector3, rot: Vector3, flags: int) -> void:
	if is_local_player():
		return
	sync_position = pos
	sync_rotation = rot
	sync_flags = flags

func shoot() -> void:
	if is_instance_valid(current_view) and current_view.has_method("can_fire") and not current_view.can_fire():
		return
	if is_cycling_bolt:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < next_shot_time:
		return
	if current_ammo <= 0:
		reload()
		return

	var stats = weapon_stats[current_weapon]
	var cycle_delay: float = float(stats.get("fire_rate", 0.12))
	next_shot_time = now + cycle_delay

	current_ammo -= 1
	_view_call("play_fire")
	if multiplayer.has_multiplayer_peer():
		rpc_on_fired.rpc()
	else:
		rpc_on_fired()
	_add_fire_bloom()
	ammo_changed.emit(current_ammo, reserve_ammo)

	recoil_pitch += stats["recoil"]

	if muzzle_flash:
		muzzle_flash.visible = true
		get_tree().create_timer(0.05).timeout.connect(func(): if muzzle_flash: muzzle_flash.visible = false)

	# === ЦИКЛ ВЗВОДА ЗАТВОРА ДЛЯ СНАЙПЕРКИ (AWP) ===
	var is_sniper: bool = (current_weapon == WeaponType.SNIPER)
	var was_aiming_before_shot: bool = is_ads

	if is_sniper:
		is_cycling_bolt = true
		# Принудительно выбиваем из зума на момент взвода
		if is_mobile:
			touch_ads = false
		is_ads = false

		# Окончание цикла затвора
		get_tree().create_timer(cycle_delay).timeout.connect(func():
			if not is_instance_valid(self):
				return
			is_cycling_bolt = false

			# Если игрок всё ещё удерживает ПКМ — возвращаем зум
			if not is_reloading and Input.is_action_pressed("ads"):
				is_ads = true
		)

	var hit_any: bool = false
	var last_shot_headshot: bool = false
	if current_weapon == WeaponType.SHOTGUN:
		var pellets: int = stats.get("pellets", 8)
		var spread_rad: float = deg_to_rad(_get_shot_spread_deg())
		var range_m: float = float(stats.get("max_range", 30.0))
		var falloff_start: float = float(stats.get("falloff_start", 6.0))
		var min_factor: float = float(stats.get("min_damage_factor", 0.2))
		var damage_per_target: Dictionary = {}
		for i in range(pellets):
			var angle: float = randf() * TAU
			var radius: float = sqrt(randf()) * tan(spread_rad)
			var dir := Vector3(cos(angle) * radius, sin(angle) * radius, -1.0).normalized()
			weapon_ray.target_position = dir * range_m
			weapon_ray.force_raycast_update()
			_handle_ray_impact()
			if weapon_ray.is_colliding():
				var collider = weapon_ray.get_collider()
				if collider and collider != self and not is_ancestor_of(collider) and collider.has_method("take_damage"):
					var dist: float = weapon_ray.global_position.distance_to(weapon_ray.get_collision_point())
					var factor: float = 1.0
					if dist > falloff_start:
						var t: float = clampf((dist - falloff_start) / maxf(range_m - falloff_start, 0.01), 0.0, 1.0)
						factor = lerpf(1.0, min_factor, t)
					damage_per_target[collider] = damage_per_target.get(collider, 0.0) + float(stats["damage"]) * factor
		var sender_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		for target in damage_per_target.keys():
			var total: int = maxi(int(round(damage_per_target[target])), 1)
			var is_target_player: bool = target.is_in_group("players") or target.has_method("is_local_player")
			if multiplayer.has_multiplayer_peer() and is_target_player:
				target.take_damage.rpc_id(target.get_multiplayer_authority(), total, sender_id, str(stats.get("name", "Дробовик")), false)
			else:
				target.take_damage(total, sender_id, str(stats.get("name", "Дробовик")), false)
			hit_any = true
		weapon_ray.target_position = Vector3(0, 0, -50)
	else:
		var shot_dir: Vector3 = _random_cone_direction(_get_shot_spread_deg())
		weapon_ray.target_position = shot_dir * 100.0
		weapon_ray.force_raycast_update()
		_handle_ray_impact()
		if weapon_ray.is_colliding():
			var collider = weapon_ray.get_collider()
			if collider and collider != self and not is_ancestor_of(collider) and collider.has_method("take_damage"):
				var dmg: float = float(stats["damage"])
				var is_headshot: bool = false

				# Расчёт зон урона (Голова / Тело / Ноги)
				if collider is Node3D:
					var hit_point: Vector3 = weapon_ray.get_collision_point()
					var hit_height: float = hit_point.y - (collider as Node3D).global_position.y
					if hit_height >= 1.45:
						is_headshot = true
						if is_sniper:
							dmg *= 2.5 # Хедшот (ваншот)
						elif current_weapon == WeaponType.ASSAULT:
							dmg *= 1.8 # Хедшот автомата x1.8
						elif current_weapon == WeaponType.PISTOL:
							dmg *= 1.7 # Хедшот пистолета x1.7
					elif is_sniper and hit_height <= 0.65:
						dmg *= 0.75 # Ноги (86 урона — цель выживает)

				var w_name: String = str(stats.get("name", ""))
				var sender_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
				var is_target_player: bool = collider.is_in_group("players") or collider.has_method("is_local_player")
				if multiplayer.has_multiplayer_peer() and is_target_player:
					collider.take_damage.rpc_id(collider.get_multiplayer_authority(), int(round(dmg)), sender_id, w_name, is_headshot)
				else:
					collider.take_damage(int(round(dmg)), sender_id, w_name, is_headshot)
				hit_any = true
				last_shot_headshot = is_headshot
		weapon_ray.target_position = Vector3(0, 0, -50)

	if hit_any:
		hit_target.emit(last_shot_headshot)

func reload() -> void:
	if is_reloading or reserve_ammo <= 0 or current_ammo == max_ammo:
		reload_pending = false
		return

	# Пока играет другая анимация оружия (выстрел, доставание), перезарядка ждёт
	if is_instance_valid(current_view) and current_view.has_method("can_start_reload"):
		if not current_view.can_start_reload():
			reload_pending = true
			return

	reload_pending = false
	is_reloading = true
	reload_id += 1
	var my_reload_id: int = reload_id
	_view_call("play_reload")
	var ammo_needed = max_ammo - current_ammo
	var ammo_to_load = min(ammo_needed, reserve_ammo)

	# Длительность берём из анимации, если она есть
	var duration: float = float(weapon_stats[current_weapon].get("reload_time", 1.2))
	if is_instance_valid(current_view) and current_view.has_method("get_reload_duration"):
		var anim_len: float = current_view.get_reload_duration()
		if anim_len > 0.0:
			duration = anim_len

	await get_tree().create_timer(duration).timeout

	# Перезарядку отменила смерть или смена оружия
	if my_reload_id != reload_id:
		return

	reserve_ammo -= ammo_to_load
	current_ammo += ammo_to_load
	is_reloading = false
	ammo_changed.emit(current_ammo, reserve_ammo)

@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, attacker_id: int, weapon_name: String = "", is_headshot: bool = false) -> void:
	if not is_local_player():
		return

	if Time.get_ticks_msec() / 1000.0 < invulnerable_until:
		return

	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1

	# Защита от нанесения урона самому себе из своего оружия
	if attacker_id != 0 and attacker_id == my_id:
		return

	# Проверка огня по своим (Friendly Fire)
	var net_manager = get_node_or_null("/root/NetworkManager")
	var is_ff: bool = net_manager.friendly_fire if net_manager else false
	if not is_ff and attacker_id != 0 and attacker_id != my_id:
		if GameStats.are_allies(attacker_id, my_id):
			return # Союзник не получает урон

	var attacker_dir := Vector3.ZERO
	if attacker_id != 0:
		var arena = get_tree().current_scene
		var attacker_node = arena.find_child(str(attacker_id), true, false) if arena else null
		if attacker_node is Node3D:
			attacker_dir = (attacker_node.global_position - global_position).normalized()

	health -= amount
	health = clamp(health, 0, max_health)
	health_changed.emit(health)
	damage_taken.emit(amount, attacker_dir)

	if health <= 0:
		if multiplayer.has_multiplayer_peer():
			GameStats.report_death.rpc_id(1, attacker_id, weapon_name, is_headshot)
		die()

func die() -> void:
	# Отменяем незавершённую перезарядку, иначе патроны добавятся после возрождения
	reload_id += 1
	reload_pending = false
	is_reloading = false
	health = max_health
	_reset_all_ammo()
	velocity = Vector3.ZERO
	is_sliding = false
	is_wall_running = false
	is_mantling = false
	can_double_jump = false
	if camera:
		camera.rotation.z = 0.0
	invulnerable_until = Time.get_ticks_msec() / 1000.0 + spawn_protection_time
	health_changed.emit(health)
	ammo_changed.emit(current_ammo, reserve_ammo)
	var arena = get_tree().current_scene
	var my_team: int = GameStats.get_player_team(name.to_int())
	if arena and arena.has_method("get_spawn_position"):
		global_position = arena.get_spawn_position(my_team)
	else:
		global_position = Vector3(randf_range(-5, 5), 2.0, randf_range(-5, 5))

func _rotate_camera(relative: Vector2) -> void:
	rotate_y(-relative.x)
	var y_mult: float = 1.0 if invert_y else -1.0
	head.rotate_x(relative.y * y_mult)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _load_weapon_data() -> void:
	if weapon_data.is_empty():
		for path in DEFAULT_WEAPON_PATHS:
			if ResourceLoader.exists(path):
				var res := load(path) as WeaponData
				if res:
					weapon_data.append(res)
	for i in weapon_data.size():
		var d: WeaponData = weapon_data[i]
		if d != null:
			weapon_stats[i] = d.to_stats()

func _setup_weapon_holder() -> void:
	weapon_holder = camera.get_node_or_null("WeaponHolder") as Node3D
	if weapon_holder == null:
		weapon_holder = Node3D.new()
		weapon_holder.name = "WeaponHolder"
		camera.add_child(weapon_holder)

func _setup_audio_players() -> void:
	var sounds_node = get_node_or_null("Sounds")
	if sounds_node == null:
		sounds_node = Node3D.new()
		sounds_node.name = "Sounds"
		add_child(sounds_node)

	gunshot_sound_3d = sounds_node.get_node_or_null("GunshotSound3D") as AudioStreamPlayer3D
	if gunshot_sound_3d == null:
		gunshot_sound_3d = AudioStreamPlayer3D.new()
		gunshot_sound_3d.name = "GunshotSound3D"
		gunshot_sound_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		gunshot_sound_3d.max_distance = 70.0
		gunshot_sound_3d.unit_size = 2.5
		gunshot_sound_3d.bus = "Master"
		sounds_node.add_child(gunshot_sound_3d)

	footstep_sound_3d = sounds_node.get_node_or_null("FootstepSound3D") as AudioStreamPlayer3D
	if footstep_sound_3d == null:
		footstep_sound_3d = AudioStreamPlayer3D.new()
		footstep_sound_3d.name = "FootstepSound3D"
		footstep_sound_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		footstep_sound_3d.max_distance = 20.0
		footstep_sound_3d.unit_size = 1.2
		footstep_sound_3d.bus = "Master"
		sounds_node.add_child(footstep_sound_3d)

func _view_call(method: String) -> void:
	if multiplayer.has_multiplayer_peer():
		rpc_play_view_anim.rpc(method)
	else:
		rpc_play_view_anim(method)

@rpc("call_local", "reliable")
func rpc_play_view_anim(method: String) -> void:
	if is_instance_valid(current_view) and current_view.has_method(method):
		current_view.call(method)

@rpc("call_local", "unreliable")
func rpc_on_fired() -> void:
	if gunshot_sound_3d:
		gunshot_sound_3d.stream = SoundFX.get_gunshot(int(current_weapon))
		gunshot_sound_3d.pitch_scale = randf_range(0.96, 1.04)
		gunshot_sound_3d.play()

	if muzzle_flash:
		muzzle_flash.visible = true
		get_tree().create_timer(0.05).timeout.connect(func():
			if is_instance_valid(muzzle_flash):
				muzzle_flash.visible = false
		)
	# Процедурный толчок оружия/головы для удалённого наблюдателя
	if not is_local_player() and is_instance_valid(current_view):
		var recoil_offset := Vector3(0, 0.015, 0.04)
		current_view.position += recoil_offset
		var tw := create_tween()
		var base_pos: Vector3 = weapon_stats[current_weapon].get("hip_pos", Vector3(0.2, -0.2, -0.4))
		tw.tween_property(current_view, "position", base_pos, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _reset_all_ammo() -> void:
	for type in weapon_stats.keys():
		ammo_state[type] = {"mag": weapon_stats[type]["max_ammo"], "reserve": weapon_stats[type]["reserve"]}
	var s: Dictionary = ammo_state[current_weapon]
	max_ammo = weapon_stats[current_weapon]["max_ammo"]
	current_ammo = s["mag"]
	reserve_ammo = s["reserve"]

func get_weapon_data() -> WeaponData:
	var i: int = int(current_weapon)
	if i >= 0 and i < weapon_data.size() and weapon_data[i] != null:
		return weapon_data[i]
	return _fallback_weapon_data

# Полный угол разброса, который видит игрок и по которому летят пули
func _get_shot_spread_deg() -> float:
	var stats = weapon_stats[current_weapon]
	return current_spread_deg + float(stats.get("spread_degrees", 0.0))

func get_crosshair_spread_deg() -> float:
	return _get_shot_spread_deg()

# Случайное направление внутри конуса (в локальных координатах луча, вперёд = -Z)
func _random_cone_direction(spread_deg: float) -> Vector3:
	var angle: float = randf() * TAU
	var radius: float = sqrt(randf()) * tan(deg_to_rad(spread_deg))
	return Vector3(cos(angle) * radius, sin(angle) * radius, -1.0).normalized()

func _add_fire_bloom() -> void:
	var wd: WeaponData = get_weapon_data()
	fire_bloom = minf(fire_bloom + wd.fire_spread_deg, wd.fire_spread_max_deg)

func _update_spread(delta: float) -> void:
	if reload_pending:
		reload()
	var wd: WeaponData = get_weapon_data()
	var add: float = 0.0
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if not is_on_floor():
		add = wd.air_spread_deg
	elif is_sliding:
		add = wd.slide_spread_deg
	elif is_sprinting:
		add = wd.sprint_spread_deg
	elif horizontal_speed > 0.5:
		add = wd.move_spread_deg
	fire_bloom = maxf(fire_bloom - wd.fire_recovery_deg_per_sec * delta, 0.0)
	var target: float = wd.base_spread_deg + add + fire_bloom
	if is_ads:
		target *= wd.ads_multiplier
	if is_crouching:
		target *= wd.crouch_multiplier
	current_spread_deg = lerpf(current_spread_deg, target, clampf(delta * wd.spread_smoothing, 0.0, 1.0))

# Создаёт декаль, если луч попал в поверхность, а не в игрока
func _handle_ray_impact() -> void:
	if not weapon_ray.is_colliding():
		return
	var hit_collider = weapon_ray.get_collider()
	if hit_collider == self or is_ancestor_of(hit_collider) or (hit_collider and hit_collider.has_method("take_damage")):
		return
	BulletDecals.spawn_hit(weapon_ray.get_collision_point(), weapon_ray.get_collision_normal())

func _has_ceiling_above() -> bool:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.from = global_position + Vector3(0, crouch_height * 0.5, 0)
	query.to = global_position + Vector3(0, standing_height + 0.1, 0)
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	return not result.is_empty()

func _update_crouch_height(delta: float) -> void:
	var target_head_y: float = crouch_head_y if is_crouching else standing_head_y
	head.position.y = lerpf(head.position.y, target_head_y, delta * crouch_transition_speed)

	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		var target_height: float = crouch_height if is_crouching else default_capsule_height
		capsule.height = lerpf(capsule.height, target_height, delta * crouch_transition_speed)
		collision_shape.position.y = capsule.height * 0.5

func set_show_ammo_on_weapon(enabled: bool) -> void:
	show_ammo_on_weapon = enabled
	_sync_weapon_ammo_3d(current_ammo, reserve_ammo)

var target_info_label: Label3D = null

func _update_body_color() -> void:
	var peer_id: int = name.to_int()
	var col: Color = GameStats.get_player_color(peer_id)

	# 1. Красим 3D-модель бойца (бронежилет, полосы шлема, повязка)
	var soldier = get_node_or_null("SoldierModel")
	if soldier and soldier.has_method("set_team_color"):
		soldier.set_team_color(col)

	var body_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if body_mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.5
		body_mesh.material_override = mat

	# 2. Красим руки ВСЕМ игрокам (и себе, и чужим персонажам со стороны)
	_update_viewmodel_hands_color()

func _update_viewmodel_hands_color() -> void:
	var peer_id: int = name.to_int()
	var col: Color = GameStats.get_player_color(peer_id) if GameStats else Color(1.0, 0.55, 0.1)

	if is_instance_valid(current_view):
		for band in current_view.find_children("RobotArmBand*", "MeshInstance3D", true, false):
			var band_mesh := band as MeshInstance3D
			if band_mesh and band_mesh.material_override is StandardMaterial3D:
				(band_mesh.material_override as StandardMaterial3D).albedo_color = col

func _update_viewmodel_hands_visibility() -> void:
	if not is_instance_valid(current_view):
		return
	var is_local: bool = is_local_player()
	_apply_hands_visibility_recursive(current_view, is_local)

func _apply_hands_visibility_recursive(node: Node, hands_visible: bool) -> void:
	if node is Node3D:
		var n_name := node.name.to_lower()
		if "righthand" in n_name or "lefthand" in n_name or "arm_lower" in n_name or "robotpalm" in n_name or "robotforearm" in n_name or "robotfinger" in n_name:
			node.visible = hands_visible
	for child in node.get_children():
		_apply_hands_visibility_recursive(child, hands_visible)

func _setup_robot_viewmodel_hands(weapon_node: Node3D) -> void:
	if not is_instance_valid(weapon_node):
		return

	var peer_id: int = name.to_int()
	var team_col: Color = GameStats.get_player_color(peer_id) if GameStats else Color(1.0, 0.55, 0.1)

	# 1. Материалы, точно повторяющие стиль робота (SoldierModel)
	var camo_mat := StandardMaterial3D.new()
	camo_mat.albedo_color = Color(0.24, 0.26, 0.28, 1) # Тёмно-серая броня робота
	camo_mat.roughness = 0.65
	camo_mat.metallic = 0.25

	var gear_mat := StandardMaterial3D.new()
	gear_mat.albedo_color = Color(0.12, 0.13, 0.15, 1) # Тактическая перчатка / шарниры
	gear_mat.roughness = 0.55
	gear_mat.metallic = 0.5

	var team_mat := StandardMaterial3D.new()
	team_mat.albedo_color = team_col # Командная повязка
	team_mat.roughness = 0.45
	team_mat.metallic = 0.1

	for hname in ["RightHand", "LeftHand"]:
		var hand_node := weapon_node.find_child(hname, true, false) as Node3D
		if not hand_node:
			continue

		var hand_mesh := hand_node.get_node_or_null("hand") as MeshInstance3D
		if not hand_mesh:
			continue

		# Очищаем старую меш-форму кисти
		hand_mesh.mesh = null
		for old_c in hand_mesh.get_children():
			if old_c is MeshInstance3D and old_c.name.begins_with("Robot"):
				old_c.queue_free()

		# 1. Блочная ладонь робота
		var palm_mesh := BoxMesh.new()
		palm_mesh.size = Vector3(1.6, 0.7, 1.8)
		var palm_inst := MeshInstance3D.new()
		palm_inst.name = "RobotPalm"
		palm_inst.mesh = palm_mesh
		palm_inst.position = Vector3(0, 0, -0.9)
		palm_inst.material_override = gear_mat
		hand_mesh.add_child(palm_inst)

		# 2. Квадратное предплечье робота
		var arm_mesh_inst := hand_mesh.get_node_or_null("arm_lower") as MeshInstance3D
		if arm_mesh_inst:
			arm_mesh_inst.mesh = null
			for old_a in arm_mesh_inst.get_children():
				if old_a is MeshInstance3D and old_a.name.begins_with("Robot"):
					old_a.queue_free()

			var a_mesh := BoxMesh.new()
			a_mesh.size = Vector3(1.4, 1.3, 6.2)
			var a_inst := MeshInstance3D.new()
			a_inst.name = "RobotForearm"
			a_inst.mesh = a_mesh
			a_inst.position = Vector3(0, 0, 3.1)
			a_inst.material_override = camo_mat
			arm_mesh_inst.add_child(a_inst)

			# 3. Повязка с цветом команды
			var b_mesh := BoxMesh.new()
			b_mesh.size = Vector3(1.5, 1.4, 1.2)
			var b_inst := MeshInstance3D.new()
			b_inst.name = "RobotArmBand"
			b_inst.mesh = b_mesh
			b_inst.position = Vector3(0, 0, 2.0)
			b_inst.material_override = team_mat
			arm_mesh_inst.add_child(b_inst)

		# 4. Блочные суставы пальцев (следуют анимациям перезарядки)
		for finger_prefix in ["index", "middle", "ring", "pinky", "thumb"]:
			var j0 := hand_mesh.get_node_or_null(finger_prefix + "_0") as MeshInstance3D
			if j0:
				_build_robot_finger_chain(j0, gear_mat)

func _build_robot_finger_chain(joint: MeshInstance3D, mat: Material) -> void:
	joint.mesh = null
	for old_f in joint.get_children():
		if old_f is MeshInstance3D and old_f.name.begins_with("Robot"):
			old_f.queue_free()

	var child_joint: MeshInstance3D = null
	for c in joint.get_children():
		if c is MeshInstance3D and ("_" in c.name or "joint" in c.name.to_lower()) and not c.name.begins_with("Robot"):
			child_joint = c
			break

	if child_joint:
		var dist: float = child_joint.position.length()
		if dist > 0.05:
			var f_mesh := BoxMesh.new()
			f_mesh.size = Vector3(0.36, 0.32, dist)
			var f_inst := MeshInstance3D.new()
			f_inst.name = "RobotFingerSegment"
			f_inst.mesh = f_mesh
			f_inst.position = child_joint.position * 0.5
			f_inst.material_override = mat
			joint.add_child(f_inst)
		_build_robot_finger_chain(child_joint, mat)
	else:
		var tip_len: float = 0.45
		var f_mesh := BoxMesh.new()
		f_mesh.size = Vector3(0.34, 0.30, tip_len)
		var f_inst := MeshInstance3D.new()
		f_inst.name = "RobotFingertip"
		f_inst.mesh = f_mesh
		f_inst.position = Vector3(0, 0, -tip_len * 0.5)
		f_inst.material_override = mat
		joint.add_child(f_inst)
			
func _physics_process_target_info() -> void:
	if not is_local_player() or not weapon_ray:
		return
	if target_info_label == null and camera:
		target_info_label = Label3D.new()
		target_info_label.pixel_size = 0.0012
		target_info_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		target_info_label.no_depth_test = true
		target_info_label.font_size = 36
		target_info_label.position = Vector3(0, 0.12, -1.8)
		camera.add_child(target_info_label)

	if target_info_label:
		if weapon_ray.is_colliding():
			var collider = weapon_ray.get_collider()
			if collider is CharacterBody3D and collider != self:
				var target_peer_id: int = collider.name.to_int()
				if GameStats.players.has(target_peer_id):
					var p_data = GameStats.players[target_peer_id]
					var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
					var is_ally: bool = GameStats.are_allies(my_id, target_peer_id)
					target_info_label.text = p_data.get("name", "")
					target_info_label.modulate = Color(0.3, 1.0, 0.4) if is_ally else Color(1.0, 0.3, 0.3)
					target_info_label.visible = true
					return
		target_info_label.visible = false

func _make_click_through(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_make_click_through(child)

# ==============================================================================
#                      ПАРКУР (TITANFALL 2 STYLE MOVEMENT)
# ==============================================================================

func _check_mantle(input_dir: Vector2) -> bool:
	if not mantle_enabled or is_on_floor() or is_sliding or is_mantling:
		return false

	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return false

	# Движение вперед либо джойстиком/WASD, либо по горизонтальной инерции
	var is_forward: bool = input_dir.y < -0.1 or Vector2(velocity.x, velocity.z).length() > 1.2
	if not is_forward:
		return false

	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	if cam_fwd.length_squared() < 0.01:
		cam_fwd = -transform.basis.z

	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask

	# 1. Проверяем препятствие на уровне живота/груди (~0.85м)
	var chest_origin: Vector3 = global_position + Vector3(0, 0.85, 0)
	var forward_reach: float = 0.9
	query.from = chest_origin
	query.to = chest_origin + cam_fwd * forward_reach
	var chest_hit := space_state.intersect_ray(query)
	if chest_hit.is_empty() or (chest_hit.collider is CharacterBody3D):
		return false

	var wall_hit_pos: Vector3 = chest_hit.position
	var wall_normal: Vector3 = chest_hit.normal
	if absf(wall_normal.y) > 0.35:
		return false

	# 2. Проверяем, что выше головы (высота ~2.15м) путь свободен (это именно край/уступ, а не глухая стена)
	var high_origin: Vector3 = global_position + Vector3(0, 2.15, 0)
	query.from = high_origin
	query.to = high_origin + cam_fwd * (forward_reach + 0.1)
	var high_hit := space_state.intersect_ray(query)
	if not high_hit.is_empty():
		return false

	# 3. Пускаем луч сверху вниз прямо за край препятствия
	var probe_x: float = wall_hit_pos.x - wall_normal.x * 0.35
	var probe_z: float = wall_hit_pos.z - wall_normal.z * 0.35
	var probe_top_y: float = global_position.y + 2.2
	var probe_bottom_y: float = global_position.y + 0.35

	query.from = Vector3(probe_x, probe_top_y, probe_z)
	query.to = Vector3(probe_x, probe_bottom_y, probe_z)
	var down_hit := space_state.intersect_ray(query)
	if down_hit.is_empty() or (down_hit.collider is CharacterBody3D):
		return false

	var ledge_pos: Vector3 = down_hit.position
	var ledge_normal: Vector3 = down_hit.normal
	if ledge_normal.y < 0.65:
		return false

	var height_diff: float = ledge_pos.y - global_position.y
	if height_diff < 0.35 or height_diff > 2.15:
		return false

	# 4. Проверяем свободное место для капсулы игрока на уступе (нет ли низкого потолка)
	var target_pos := Vector3(ledge_pos.x, ledge_pos.y + 0.05, ledge_pos.z)
	query.from = target_pos + Vector3(0, 0.2, 0)
	query.to = target_pos + Vector3(0, 1.8, 0)
	var ceil_hit := space_state.intersect_ray(query)
	if not ceil_hit.is_empty():
		return false

	_start_mantle(target_pos)
	return true

func _start_mantle(target_pos: Vector3) -> void:
	is_mantling = true
	is_wall_running = false
	mantle_timer = 0.0
	mantle_start_pos = global_position
	mantle_target_pos = target_pos
	velocity = Vector3.ZERO
	can_double_jump = true

	if footstep_sound_3d:
		footstep_sound_3d.stream = SoundFX.get_mantle()
		footstep_sound_3d.pitch_scale = randf_range(0.95, 1.05)
		footstep_sound_3d.volume_db = 1.0
		footstep_sound_3d.play()

func _check_wall_run_start(delta: float, input_dir: Vector2) -> void:
	if velocity.y > 3.8:
		return

	var is_forward: bool = input_dir.y < -0.1 or Vector2(velocity.x, velocity.z).length() > 2.0
	if not is_forward:
		return

	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return

	var origin: Vector3 = global_position + Vector3(0, 0.9, 0)
	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	if cam_fwd.length_squared() < 0.01:
		cam_fwd = -transform.basis.z

	var cam_rgt: Vector3 = camera.global_transform.basis.x
	cam_rgt.y = 0.0
	cam_rgt = cam_rgt.normalized()

	var check_dist: float = 0.95
	var test_rays = [
		{"side": -1, "dir": -cam_rgt},
		{"side": -1, "dir": (-cam_rgt + cam_fwd * 0.55).normalized()},
		{"side": 1, "dir": cam_rgt},
		{"side": 1, "dir": (cam_rgt + cam_fwd * 0.55).normalized()}
	]

	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask

	for test in test_rays:
		query.from = origin
		query.to = origin + (test["dir"] as Vector3) * check_dist
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			if absf(normal.y) < 0.3 and not (hit.collider is CharacterBody3D):
				# Проверка кулдауна на повторный захват той же стены
				if wall_run_cooldown_timer > 0.0 and normal.dot(wall_run_cooldown_normal) > 0.75:
					continue

				# Не входим в бег по стене, если смотрим прямо в стену в упор
				if absf(cam_fwd.dot(normal)) > 0.9:
					continue

				var tangent: Vector3 = (cam_fwd - normal * cam_fwd.dot(normal)).normalized()
				if tangent.dot(cam_fwd) < 0.0:
					tangent = -tangent

				is_wall_running = true
				wall_run_side = test["side"]
				wall_run_normal = normal
				wall_run_dir = tangent
				wall_run_timer = wall_run_max_duration
				can_double_jump = true

				# При прилипании к стене даем легкий импульс поддержки
				velocity.y = maxf(velocity.y * 0.35, 0.4)

				if footstep_sound_3d:
					footstep_sound_3d.stream = SoundFX.get_footstep()
					footstep_sound_3d.pitch_scale = randf_range(1.15, 1.25)
					footstep_sound_3d.volume_db = 0.0
					footstep_sound_3d.play()
				return

func _update_active_wall_run(delta: float, input_dir: Vector2, crouch_hold: bool) -> void:
	if crouch_hold or input_dir.y > 0.5:
		_end_wall_run(0.25)
		return

	wall_run_timer -= delta
	if wall_run_timer <= 0.0:
		_end_wall_run(0.35)
		return

	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		_end_wall_run(0.2)
		return

	var origin: Vector3 = global_position + Vector3(0, 0.9, 0)
	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	if cam_fwd.length_squared() < 0.01:
		cam_fwd = -transform.basis.z

	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	query.from = origin
	query.to = origin - wall_run_normal * 1.25

	var result := space_state.intersect_ray(query)
	if result.is_empty() or absf(result.normal.y) > 0.35 or result.collider is CharacterBody3D:
		_end_wall_run(0.25)
		return

	wall_run_normal = result.normal
	var tangent: Vector3 = (cam_fwd - wall_run_normal * cam_fwd.dot(wall_run_normal)).normalized()
	if tangent.dot(cam_fwd) < 0.0:
		tangent = -tangent
	wall_run_dir = tangent

	# Если игрок развернулся более чем на 80 градусов от направления стены — сход со стены
	if cam_fwd.dot(wall_run_dir) < 0.15:
		_end_wall_run(0.25)
		return

func _end_wall_run(cooldown: float = 0.3) -> void:
	if is_wall_running:
		wall_run_cooldown_normal = wall_run_normal
		wall_run_cooldown_timer = cooldown
	is_wall_running = false
	wall_run_timer = 0.0

func _perform_wall_jump() -> void:
	var push: Vector3 = wall_run_normal * wall_jump_push_force
	var fwd: Vector3 = wall_run_dir * wall_jump_forward_force
	var up: Vector3 = Vector3.UP * wall_jump_up_velocity
	velocity = push + fwd + up

	_end_wall_run(0.35)
	can_double_jump = true

	if footstep_sound_3d:
		footstep_sound_3d.stream = SoundFX.get_jump_land()
		footstep_sound_3d.pitch_scale = randf_range(1.25, 1.4)
		footstep_sound_3d.volume_db = 2.0
		footstep_sound_3d.play()

func _perform_double_jump(dir: Vector3) -> void:
	can_double_jump = false
	velocity.y = double_jump_velocity
	if dir.length_squared() > 0.01:
		velocity.x = dir.x * sprint_speed
		velocity.z = dir.z * sprint_speed

	if footstep_sound_3d:
		footstep_sound_3d.stream = SoundFX.get_double_jump()
		footstep_sound_3d.pitch_scale = randf_range(0.95, 1.05)
		footstep_sound_3d.volume_db = 2.5
		footstep_sound_3d.play()
		
