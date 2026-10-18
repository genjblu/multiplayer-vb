extends CharacterBody3D

signal health_changed(new_health: int)
signal ammo_changed(current: int, reserve: int)
signal hit_target()
signal weapon_changed(weapon_name: String)

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
@export var mouse_sensitivity: float = 0.003
@export var ads_mouse_multiplier: float = 0.6
@export var touch_sensitivity: float = 0.005
## Доля ширины экрана слева, где касания НЕ вращают камеру (зона джойстика)
@export var look_zone_start: float = 0.4

const DEFAULT_WEAPON_PATHS: Array[String] = ["res://weapons/pistol.tres", "res://weapons/assault.tres", "res://weapons/shotgun.tres", "res://weapons/sniper.tres"]
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
	for i in range(4):
		var act = "weapon_%d" % (i + 1)
		if not InputMap.has_action(act):
			InputMap.add_action(act)
			var ev = InputEventKey.new()
			ev.keycode = KEY_1 + i
			InputMap.action_add_event(act, ev)

func _enter_tree() -> void:
	var peer_id: int = name.to_int()
	set_multiplayer_authority(peer_id)
	$MultiplayerSynchronizer.set_multiplayer_authority(peer_id)

func _ready() -> void:
	if not ammo_changed.is_connected(_sync_weapon_ammo_3d):
		ammo_changed.connect(_sync_weapon_ammo_3d)
	_load_weapon_data()
	_setup_weapon_holder()
	_reset_all_ammo()
	_switch_weapon(WeaponType.ASSAULT)
	health = max_health
	collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		default_capsule_height = (collision_shape.shape as CapsuleShape3D).height
	else:
		default_capsule_height = standing_height

	if not is_multiplayer_authority():
		camera.clear_current()
		touch_ui.hide()
		return

	camera.make_current()
	GameStats.register_name.rpc_id(1, GameStats.local_nick)
	# Своё тело не должно затенять свою же камеру и руки
	var body_mesh = get_node_or_null("MeshInstance3D")
	if body_mesh:
		body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body_mesh.set_layer_mask_value(1, false)
		body_mesh.set_layer_mask_value(3, true)

	GameSettings.apply_to_player(self)
	health_changed.emit(health)
	ammo_changed.emit(current_ammo, reserve_ammo)

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
	if view_scene != null and weapon_holder != null:
		# Новый способ: сцена оружия с анимациями
		current_view = view_scene.instantiate() as Node3D
		weapon_holder.add_child(current_view)
		current_view.position = stats.get("hip_pos", Vector3(0.2, -0.2, -0.4))
		current_weapon_node = current_view
		if current_view.has_method("setup_ammo_3d_params"):
			var a_off: Vector3 = stats.get("ammo_3d_offset", Vector3(-0.06, 0.05, -0.18))
			var a_rot: Vector3 = stats.get("ammo_3d_rotation_deg", Vector3.ZERO)
			var a_font: int = stats.get("ammo_3d_font_size", 96)
			var a_scale: float = stats.get("ammo_3d_scale", 0.0005)
			current_view.call("setup_ammo_3d_params", a_off, a_rot, a_font, a_scale)
		_sync_weapon_ammo_3d(current_ammo, reserve_ammo)
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

func _sync_weapon_ammo_3d(current: int, reserve: int) -> void:
	if is_instance_valid(current_view):
		if current_view.has_method("set_ammo_display"):
			current_view.call("set_ammo_display", current, reserve)
		if current_view.has_method("set_ammo_3d_visible"):
			current_view.call("set_ammo_3d_visible", show_ammo_on_weapon and is_multiplayer_authority())
	elif is_instance_valid(current_weapon_node):
		var lbl: Label3D = current_weapon_node.get_node_or_null("BoxAmmoLabel3D") as Label3D
		if show_ammo_on_weapon and is_multiplayer_authority():
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
	if not is_multiplayer_authority():
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
		
	if not is_multiplayer_authority() or not is_mobile:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			var act: String = _button_action_at(event.position)
			if act != "":
				button_touches[event.index] = act
				touch_action(act, true)
				return
			var screen_w: float = get_viewport().get_visible_rect().size.x
			if touch_look_index == -1 \
					and event.position.x > screen_w * look_zone_start \
					and not _is_over_joystick(event.position):
				touch_look_index = event.index
		else:
			if button_touches.has(event.index):
				touch_action(button_touches[event.index], false)
				button_touches.erase(event.index)
			elif event.index == touch_look_index:
				touch_look_index = -1

	elif event is InputEventScreenDrag:
		if event.index == touch_look_index:
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
func touch_action(action: String, pressed: bool) -> void:
	if not is_multiplayer_authority():
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
			if pressed:
				touch_ads = not touch_ads
		"cycle_weapon":
			if pressed:
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
	if not is_multiplayer_authority():
		global_position = global_position.lerp(sync_position, delta * 20.0)
		rotation.y = lerp_angle(rotation.y, sync_rotation.y, delta * 20.0)
		# sync_rotation: x = наклон головы, y = поворот тела, z = номер оружия
		head.rotation.x = lerp_angle(head.rotation.x, sync_rotation.x, delta * 20.0)
		var remote_weapon: int = int(round(sync_rotation.z))
		if remote_weapon != int(current_weapon) and weapon_stats.has(remote_weapon):
			_switch_weapon(remote_weapon as WeaponType)
		return

	if global_position.y < -10.0:
		GameStats.report_death.rpc_id(1, 0)
		die()
		return

	if is_mobile:
		# На телефоне игнорируем мышь, эмулируемую из касаний
		is_ads = touch_ads
		is_firing = touch_fire
	else:
		var can_mouse_act: bool = (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
		is_ads = (Input.is_action_pressed("ads") and can_mouse_act) or touch_ads
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

	var target_weapon_pos: Vector3 = stats.get("ads_pos", Vector3(0, -0.12, -0.35)) if is_ads else stats.get("hip_pos", Vector3(0.2, -0.2, -0.4))
	if current_weapon_node:
		current_weapon_node.position = current_weapon_node.position.lerp(target_weapon_pos, delta * 15.0)

	if not is_on_floor():
		velocity.y -= gravity * delta

	var jump_pressed: bool = Input.is_action_just_pressed("ui_accept") or touch_jump_req
	touch_jump_req = false
	if jump_pressed and is_on_floor():
		if is_sliding:
			is_sliding = false
			slide_timer = 0.0
		velocity.y = jump_velocity

	var crouch_just_pressed: bool = Input.is_action_just_pressed("crouch") or touch_crouch_req
	touch_crouch_req = false

	if not is_mobile and crouch_toggle_mode and Input.is_action_just_pressed("crouch"):
		_crouch_toggled = not _crouch_toggled

	var crouch_hold: bool = false
	if crouch_toggle_mode:
		crouch_hold = _crouch_toggled
	else:
		crouch_hold = Input.is_action_pressed("crouch") or touch_crouch

	# На телефоне авто-спринт при наклоне джойстика вперёд до упора
	var auto_mobile_sprint: bool = is_mobile and touch_move.y < -0.82
	# Спринт возможен только если мы не приседаем
	is_sprinting = (Input.is_action_pressed("sprint") or touch_sprint or auto_mobile_sprint) \
		and is_on_floor() and not is_ads and not is_sliding and not is_crouching

	if is_sprinting and crouch_toggle_mode:
		_crouch_toggled = false

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input_dir = (input_dir + touch_move).limit_length(1.0)
	var move_strength: float = input_dir.length()
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# Подкат начинается только если игрок нажал приседание ВО ВРЕМЯ спринта на полу
	if crouch_just_pressed and is_on_floor() and not is_sliding and is_sprinting and input_dir.length() > 0:
		is_sliding = true
		slide_timer = slide_duration
		slide_vector = input_dir.normalized()

	# Проверка препятствия над головой для вставания
	var ceiling_blocked: bool = _has_ceiling_above()

	if is_sliding:
		is_crouching = true
	elif crouch_hold or ceiling_blocked:
		is_crouching = is_on_floor() or is_crouching
	else:
		is_crouching = false

	var current_speed = base_speed
	if is_sprinting:
		current_speed = sprint_speed
	elif is_crouching:
		current_speed = crouch_speed

	if is_sliding:
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
	_update_crouch_height(delta)
	_update_spread(delta)

	recoil_pitch = lerp(recoil_pitch, 0.0, delta * 10.0)
	head.rotation.x = clamp(head.rotation.x + recoil_pitch, deg_to_rad(-89), deg_to_rad(89))

	sync_position = global_position
	sync_rotation = Vector3(head.rotation.x, rotation.y, float(current_weapon))

func shoot() -> void:
	if is_instance_valid(current_view) and current_view.has_method("can_fire") and not current_view.can_fire():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < next_shot_time:
		return
	if current_ammo <= 0:
		reload()
		return
	next_shot_time = now + float(weapon_stats[current_weapon].get("fire_rate", 0.12))

	current_ammo -= 1
	_view_call("play_fire")
	_add_fire_bloom()
	ammo_changed.emit(current_ammo, reserve_ammo)

	var stats = weapon_stats[current_weapon]
	recoil_pitch += stats["recoil"]

	if muzzle_flash:
		muzzle_flash.visible = true
		get_tree().create_timer(0.05).timeout.connect(func(): if muzzle_flash: muzzle_flash.visible = false)

	var hit_any = false
	if current_weapon == WeaponType.SHOTGUN:
		var pellets: int = stats.get("pellets", 8)
		var spread_rad: float = deg_to_rad(_get_shot_spread_deg())
		var range_m: float = float(stats.get("max_range", 30.0))
		var falloff_start: float = float(stats.get("falloff_start", 6.0))
		var min_factor: float = float(stats.get("min_damage_factor", 0.2))
		var damage_per_target: Dictionary = {}
		for i in range(pellets):
			# Случайное отклонение внутри конуса (корень даёт равномерное распределение по кругу)
			var angle: float = randf() * TAU
			var radius: float = sqrt(randf()) * tan(spread_rad)
			var dir := Vector3(cos(angle) * radius, sin(angle) * radius, -1.0).normalized()
			weapon_ray.target_position = dir * range_m
			weapon_ray.force_raycast_update()
			_handle_ray_impact()
			if weapon_ray.is_colliding():
				var collider = weapon_ray.get_collider()
				if collider and collider.has_method("take_damage"):
					var dist: float = weapon_ray.global_position.distance_to(weapon_ray.get_collision_point())
					var factor: float = 1.0
					if dist > falloff_start:
						var t: float = clampf((dist - falloff_start) / maxf(range_m - falloff_start, 0.01), 0.0, 1.0)
						factor = lerpf(1.0, min_factor, t)
					damage_per_target[collider] = damage_per_target.get(collider, 0.0) + float(stats["damage"]) * factor
		for target in damage_per_target.keys():
			var total: int = maxi(int(round(damage_per_target[target])), 1)
			target.take_damage.rpc_id(target.get_multiplayer_authority(), total, multiplayer.get_unique_id())
			hit_any = true
		weapon_ray.target_position = Vector3(0, 0, -50)
	else:
		var shot_dir: Vector3 = _random_cone_direction(_get_shot_spread_deg())
		weapon_ray.target_position = shot_dir * 50.0
		weapon_ray.force_raycast_update()
		_handle_ray_impact()
		if weapon_ray.is_colliding():
			var collider = weapon_ray.get_collider()
			if collider and collider.has_method("take_damage"):
				collider.take_damage.rpc_id(collider.get_multiplayer_authority(), stats["damage"], multiplayer.get_unique_id())
				hit_any = true
		weapon_ray.target_position = Vector3(0, 0, -50)

	if hit_any:
		hit_target.emit()

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
func take_damage(amount: int, attacker_id: int) -> void:
	if not is_multiplayer_authority():
		return

	if Time.get_ticks_msec() / 1000.0 < invulnerable_until:
		return
	health -= amount
	health = clamp(health, 0, max_health)
	health_changed.emit(health)

	if health <= 0:
		GameStats.report_death.rpc_id(1, attacker_id)
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
	invulnerable_until = Time.get_ticks_msec() / 1000.0 + spawn_protection_time
	health_changed.emit(health)
	ammo_changed.emit(current_ammo, reserve_ammo)
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

func _view_call(method: String) -> void:
	if is_instance_valid(current_view) and current_view.has_method(method):
		current_view.call(method)

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
	if hit_collider and hit_collider.has_method("take_damage"):
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
