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
@export var mouse_sensitivity: float = 0.003
@export var touch_sensitivity: float = 0.005
## Доля ширины экрана слева, где касания НЕ вращают камеру (зона джойстика)
@export var look_zone_start: float = 0.4

var current_weapon: WeaponType = WeaponType.ASSAULT
var weapon_stats = {
	WeaponType.PISTOL: {
		"name": "Пистолет",
		"damage": 22,
		"max_ammo": 15,
		"reserve": 60,
		"recoil": 0.02,
		"ads_fov": 55.0,
		"mesh_size": Vector3(0.08, 0.08, 0.4)
	},
	WeaponType.ASSAULT: {
		"name": "Автомат",
		"damage": 25,
		"max_ammo": 30,
		"reserve": 90,
		"recoil": 0.035,
		"ads_fov": 45.0,
		"mesh_size": Vector3(0.1, 0.1, 0.7)
	},
	WeaponType.SHOTGUN: {
		"name": "Дробовик",
		"damage": 15,
		"pellets": 6,
		"max_ammo": 8,
		"reserve": 32,
		"recoil": 0.09,
		"ads_fov": 60.0,
		"mesh_size": Vector3(0.12, 0.12, 0.8)
	},
	WeaponType.SNIPER: {
		"name": "Снайперская винтовка",
		"damage": 95,
		"max_ammo": 5,
		"reserve": 20,
		"recoil": 0.16,
		"ads_fov": 20.0,
		"mesh_size": Vector3(0.08, 0.08, 1.1)
	}
}

var max_ammo: int = 30
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
	_switch_weapon(WeaponType.ASSAULT)
	health = max_health
	if not is_multiplayer_authority():
		camera.clear_current()
		touch_ui.hide()
		return

	camera.make_current()

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

var current_weapon_node: MeshInstance3D = null

func _switch_weapon(type: WeaponType) -> void:
	current_weapon = type
	var stats = weapon_stats[current_weapon]
	max_ammo = stats["max_ammo"]
	current_ammo = max_ammo
	reserve_ammo = stats["reserve"]

	if weapon_pistol: weapon_pistol.visible = false
	if weapon_assault: weapon_assault.visible = false
	if weapon_shotgun: weapon_shotgun.visible = false
	if weapon_sniper: weapon_sniper.visible = false

	match current_weapon:
		WeaponType.PISTOL:
			current_weapon_node = weapon_pistol
		WeaponType.ASSAULT:
			current_weapon_node = weapon_assault
		WeaponType.SHOTGUN:
			current_weapon_node = weapon_shotgun
		WeaponType.SNIPER:
			current_weapon_node = weapon_sniper

	if current_weapon_node:
		current_weapon_node.visible = true
		if current_weapon_node.mesh is BoxMesh:
			var box: BoxMesh = current_weapon_node.mesh as BoxMesh
			box.size = stats["mesh_size"]

	ammo_changed.emit(current_ammo, reserve_ammo)
	weapon_changed.emit(stats["name"])

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

	if event.is_action_pressed("fire") and not is_reloading:
		shoot()

	if event.is_action_pressed("reload") and not is_reloading and current_ammo < max_ammo and reserve_ammo > 0:
		reload()

	if event.is_action_pressed("weapon_1"): _switch_weapon(WeaponType.PISTOL)
	if event.is_action_pressed("weapon_2"): _switch_weapon(WeaponType.ASSAULT)
	if event.is_action_pressed("weapon_3"): _switch_weapon(WeaponType.SHOTGUN)
	if event.is_action_pressed("weapon_4"): _switch_weapon(WeaponType.SNIPER)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(event.relative * mouse_sensitivity)
		
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
			if pressed:
				touch_crouch_req = true
		"sprint":
			touch_sprint = pressed
		"ads":
			touch_ads = pressed
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
		return

	if global_position.y < -10.0:
		die()
		return

	if is_mobile:
		# На телефоне игнорируем мышь, эмулируемую из касаний
		is_ads = touch_ads
		is_firing = touch_fire
	else:
		is_ads = Input.is_action_pressed("ads") or touch_ads
		is_firing = Input.is_action_pressed("fire") or touch_fire
	if current_weapon == WeaponType.ASSAULT and is_firing and not is_reloading:
		fire_timer -= delta
		if fire_timer <= 0.0:
			shoot()
			fire_timer = assault_fire_rate
	else:
		fire_timer = 0.0

	var stats = weapon_stats[current_weapon]
	var target_fov = stats["ads_fov"] if is_ads else 75.0
	camera.fov = lerp(camera.fov, target_fov, delta * 15.0)

	var target_weapon_pos = Vector3(0, -0.12, -0.35) if is_ads else Vector3(0.2, -0.2, -0.4)
	if current_weapon_node:
		current_weapon_node.position = current_weapon_node.position.lerp(target_weapon_pos, delta * 15.0)

	if not is_on_floor():
		velocity.y -= gravity * delta

	var jump_pressed: bool = Input.is_action_just_pressed("ui_accept") or touch_jump_req
	touch_jump_req = false
	if jump_pressed and is_on_floor() and not is_sliding:
		velocity.y = jump_velocity

	is_sprinting = (Input.is_action_pressed("sprint") or touch_sprint) \
		and is_on_floor() and not is_ads and not is_sliding

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input_dir = (input_dir + touch_move).limit_length(1.0)
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var crouch_pressed: bool = Input.is_action_just_pressed("crouch") or touch_crouch_req
	touch_crouch_req = false
	if crouch_pressed and is_on_floor() and not is_sliding and input_dir.length() > 0:
		is_sliding = true
		slide_timer = 0.5
		slide_vector = input_dir.normalized()

	var current_speed = sprint_speed if is_sprinting else base_speed

	if is_sliding:
		slide_timer -= delta
		var slide_speed = base_speed * 2.2 * (slide_timer / 0.5)
		var forward = (transform.basis * Vector3(slide_vector.x, 0, slide_vector.y)).normalized()
		velocity.x = forward.x * slide_speed
		velocity.z = forward.z * slide_speed
		if slide_timer <= 0.0 or not is_on_floor():
			is_sliding = false
	elif direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	recoil_pitch = lerp(recoil_pitch, 0.0, delta * 10.0)
	head.rotation.x = clamp(head.rotation.x + recoil_pitch, deg_to_rad(-89), deg_to_rad(89))

	sync_position = global_position
	sync_rotation = rotation

func shoot() -> void:
	if current_ammo <= 0:
		reload()
		return

	current_ammo -= 1
	ammo_changed.emit(current_ammo, reserve_ammo)

	var stats = weapon_stats[current_weapon]
	recoil_pitch += stats["recoil"]

	if muzzle_flash:
		muzzle_flash.visible = true
		get_tree().create_timer(0.05).timeout.connect(func(): if muzzle_flash: muzzle_flash.visible = false)

	var hit_any = false
	if current_weapon == WeaponType.SHOTGUN:
		var pellets = stats.get("pellets", 6)
		for i in range(pellets):
			# Небольшой разброс для дробовика
			weapon_ray.target_position = Vector3(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5), -50)
			weapon_ray.force_raycast_update()
			if weapon_ray.is_colliding():
				var collider = weapon_ray.get_collider()
				if collider and collider.has_method("take_damage"):
					collider.take_damage.rpc_id(collider.get_multiplayer_authority(), stats["damage"])
					hit_any = true
		weapon_ray.target_position = Vector3(0, 0, -50) # сброс
	else:
		weapon_ray.force_raycast_update()
		if weapon_ray.is_colliding():
			var collider = weapon_ray.get_collider()
			if collider and collider.has_method("take_damage"):
				collider.take_damage.rpc_id(collider.get_multiplayer_authority(), stats["damage"])
				hit_any = true

	if hit_any:
		hit_target.emit()

func reload() -> void:
	if is_reloading or reserve_ammo <= 0 or current_ammo == max_ammo:
		return

	is_reloading = true
	var ammo_needed = max_ammo - current_ammo
	var ammo_to_load = min(ammo_needed, reserve_ammo)

	await get_tree().create_timer(1.2).timeout

	reserve_ammo -= ammo_to_load
	current_ammo += ammo_to_load
	is_reloading = false
	ammo_changed.emit(current_ammo, reserve_ammo)

@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int) -> void:
	if not is_multiplayer_authority():
		return

	health -= amount
	health = clamp(health, 0, max_health)
	health_changed.emit(health)

	if health <= 0:
		die()

func die() -> void:
	health = max_health
	current_ammo = weapon_stats[current_weapon]["max_ammo"]
	is_reloading = false
	health_changed.emit(health)
	ammo_changed.emit(current_ammo, reserve_ammo)
	global_position = Vector3(randf_range(-5, 5), 2.0, randf_range(-5, 5))

func _rotate_camera(relative: Vector2) -> void:
	rotate_y(-relative.x)
	head.rotate_x(-relative.y)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
