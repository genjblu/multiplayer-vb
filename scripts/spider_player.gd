class_name SpiderPlayer
extends CharacterBody3D

const SpiderModelClass = preload("res://scripts/spider_model.gd")
const WebProjectileClass = preload("res://scripts/web_projectile.gd")

signal health_changed(new_hp: int, max_hp: int)
signal died(attacker_id: int)
signal web_entrapment_changed(cur: float, max_val: float)

enum State {
	NORMAL,
	SWINGING,
	ZIPPING,
	WALL_RUNNING,
	WEB_STRIKING,
	THROWING,
	COCOONED
}

@export var max_health: int = 150
@export var health: int = 150
@export var base_speed: float = 12.0
@export var sprint_speed: float = 18.0
@export var swing_speed_max: float = 46.0
@export var zip_speed: float = 42.0
@export var wall_run_speed: float = 20.0
@export var gravity: float = 24.0

var state: State = State.NORMAL
var current_peer_id: int = 1

# --- Web Swing ---
var web_anchor_pos: Vector3 = Vector3.ZERO
var web_rope_length: float = 0.0
var is_swing_active: bool = false
var swing_hand_is_right: bool = true
var swing_cooldown: float = 0.0

# --- Web Zip ---
var zip_target_pos: Vector3 = Vector3.ZERO
var zip_timer: float = 0.0

# --- Wall Run / Climb ---
var wall_normal: Vector3 = Vector3.ZERO
var wall_run_timer: float = 0.0

# --- Super Jump ---
var is_charging_jump: bool = false
var jump_charge: float = 0.0

# --- Web Strike ---
var strike_target: Node3D = null
var strike_timer: float = 0.0

# --- Web Throw ---
var held_throw_object: Node3D = null
var throw_spin_timer: float = 0.0
var throw_target_pos: Vector3 = Vector3.ZERO

# --- Web Entrapment (Cocoon) ---
var web_meter: float = 0.0 # 0..100
var cocoon_timer: float = 0.0

# --- Combat Cooldowns ---
var web_shoot_cooldown: float = 0.16
var next_web_shoot_time: float = 0.0
var web_shot_hand_toggle: bool = false
var melee_combo_index: int = 0
var last_melee_time: float = 0.0

# --- Camera & Look ---
var cam_rot_h: float = 0.0
var cam_rot_v: float = 0.0
var target_fov: float = 78.0

# --- Network Sync ---
var sync_pos: Vector3 = Vector3.ZERO
var sync_rot: Vector3 = Vector3.ZERO
var sync_vel: Vector3 = Vector3.ZERO
var sync_state: int = 0
var sync_anchor: Vector3 = Vector3.ZERO
var sync_web_active: bool = false

# --- Nodes ---
@onready var model: Node3D = $SpiderModel
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var cam_pivot: Node3D = $CameraPivot
@onready var web_line_mesh: MeshInstance3D = $WebLineVisual
@onready var web_ray: RayCast3D = $CameraPivot/SpringArm3D/Camera3D/WebRay
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var audio_web: AudioStreamPlayer3D = $Audio/WebAudio
@onready var audio_fx: AudioStreamPlayer3D = $Audio/FXAudio

var web_proj_scene: PackedScene = preload("res://scenes/weapons/web_projectile.tscn")

# HUD
var hud_layer: CanvasLayer = null
var hud_hp_bar: ProgressBar = null
var hud_web_bar: ProgressBar = null
var hud_jump_bar: ProgressBar = null
var hud_reticle_label: Label = null
var hud_crosshair: Control = null
var hud_target_label: Label = null

func is_local_player() -> bool:
	if not is_inside_tree() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return true
	return get_multiplayer_authority() == multiplayer.get_unique_id()

func _ready() -> void:
	current_peer_id = name.to_int() if name.is_valid_int() else 1
	health = max_health

	if is_local_player():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		cam_pivot.top_level = true
		cam_pivot.global_position = global_position + Vector3(0, 1.45, 0)
		cam_rot_h = 0.0
		cam_rot_v = deg_to_rad(10.0)
		camera.make_current()
		_build_spider_hud()
	else:
		camera.current = false

	sync_pos = global_position
	sync_rot = rotation

func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player() or state == State.COCOONED:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = GameSettings.mouse_sensitivity if GameSettings else 0.003
		var inv_y: float = -1.0 if (GameSettings and GameSettings.invert_y) else 1.0
		cam_rot_h -= event.relative.x * sens
		cam_rot_v = clampf(cam_rot_v - event.relative.y * sens * inv_y, deg_to_rad(-75.0), deg_to_rad(70.0))

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			var is_mob: bool = OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]
			if not is_mob:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if is_local_player():
		_process_local_player(delta)
		_sync_network_state()
	else:
		_process_remote_interpolation(delta)

	_update_web_visuals()
	_update_camera_fov(delta)

func _process_local_player(delta: float) -> void:
	# 1. Проверка кокона (связан)
	if state == State.COCOONED:
		_process_cocoon(delta)
		move_and_slide()
		return

	# Постепенное рассеивание паутины, если не в коконе
	if web_meter > 0.0:
		web_meter = maxf(0.0, web_meter - delta * 12.0)
		web_entrapment_changed.emit(web_meter, 100.0)

	if swing_cooldown > 0.0:
		swing_cooldown -= delta

	# Вращение и слежение независимой камеры
	cam_pivot.global_position = global_position + Vector3(0, 1.45, 0)
	cam_pivot.rotation = Vector3(0, cam_rot_h, 0)
	spring_arm.rotation = Vector3(cam_rot_v, 0, 0)

	# 2. Обработка супер-прыжка
	_process_super_jump(delta)

	# 3. Обработка боя и атак
	_process_combat(delta)

	# 4. Обработка состояний перемещения
	match state:
		State.NORMAL:
			_process_normal_movement(delta)
		State.SWINGING:
			_process_web_swing(delta)
		State.ZIPPING:
			_process_web_zip(delta)
		State.WALL_RUNNING:
			_process_wall_run(delta)
		State.WEB_STRIKING:
			_process_web_strike(delta)
		State.THROWING:
			_process_web_throw(delta)

	move_and_slide()

	# Обновление процедурной анимации модели
	if model:
		model.is_right_arm_swinging = swing_hand_is_right
		model.update_animation(
			delta,
			velocity,
			is_on_floor(),
			state == State.SWINGING,
			state == State.ZIPPING,
			state == State.WALL_RUNNING,
			state == State.WEB_STRIKING,
			is_charging_jump,
			cam_rot_v
		)

	# Обновление HUD
	_update_hud_reticle()

# ========================================================
# ПЕРЕМЕЩЕНИЕ: ОБЫЧНЫЙ БЕГ И ПРЫЖКИ
# ========================================================
func _process_normal_movement(delta: float) -> void:
	# Гравитация
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Ввод направления
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var cam_forward: Vector3 = -cam_pivot.global_transform.basis.z
	var cam_right: Vector3 = cam_pivot.global_transform.basis.x
	cam_forward.y = 0.0
	cam_right.y = 0.0
	cam_forward = cam_forward.normalized()
	cam_right = cam_right.normalized()

	var move_dir: Vector3 = (cam_forward * -input_dir.y + cam_right * input_dir.x).normalized()

	var is_sprint: bool = Input.is_key_pressed(KEY_SHIFT)
	var speed: float = sprint_speed if is_sprint else base_speed

	if move_dir.length_squared() > 0.01:
		velocity.x = lerpf(velocity.x, move_dir.x * speed, delta * 14.0)
		velocity.z = lerpf(velocity.z, move_dir.z * speed, delta * 14.0)
		# Поворот модели персонажа в сторону движения
		var target_angle: float = atan2(move_dir.x, move_dir.z) + PI
		if model:
			model.rotation.y = lerp_angle(model.rotation.y, target_angle, delta * 14.0)
	else:
		velocity.x = lerpf(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 10.0)

	# Обычный прыжок (если не заряжается супер-прыжок)
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_charging_jump:
		velocity.y = 11.0

	# Проверка карабкания по стене
	if is_on_wall() and (Input.is_action_pressed("move_forward") or move_dir.length() > 0.5):
		wall_normal = get_wall_normal()
		if wall_normal.dot(Vector3.UP) < 0.2: # Вертикальная стена
			_start_wall_run()
			return

	# Запуск раскачивания на паутине (RMB)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not is_on_floor() and swing_cooldown <= 0.0:
		_try_start_web_swing()

	# Запуск притягивания паутиной (Web-Zip на F или СКМ)
	if Input.is_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_try_start_web_zip()

# ========================================================
# ПЕРЕМЕЩЕНИЕ: WEB-SWING (РАСКАЧИВАНИЕ НА ПАУТИНЕ)
# ========================================================
func _try_start_web_swing() -> void:
	# Ищем здание над головой / впереди слева/справа
	var anchor := _find_swing_anchor()
	if anchor == Vector3.ZERO:
		return

	web_anchor_pos = anchor
	web_rope_length = maxf(12.0, global_position.distance_to(web_anchor_pos))
	is_swing_active = true
	state = State.SWINGING
	swing_hand_is_right = not swing_hand_is_right

	# Звук THWIP!
	if audio_web:
		audio_web.stream = SoundFX.get_web_shoot()
		audio_web.play()

	# Начальный импульс вперед при зацепе
	var forward: Vector3 = -cam_pivot.global_transform.basis.z
	velocity += forward * 6.0 + Vector3.UP * 2.0

func _find_swing_anchor() -> Vector3:
	var space := get_world_3d().direct_space_state
	var origin: Vector3 = global_position + Vector3.UP * 1.5

	# Пускаем веер лучей вперед и вверх по направлению взгляда
	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	var cam_up: Vector3 = camera.global_transform.basis.y
	var cam_side: Vector3 = camera.global_transform.basis.x * (1.0 if swing_hand_is_right else -1.0)

	var ray_dirs := [
		(cam_fwd * 0.7 + cam_up * 0.7 + cam_side * 0.25).normalized(),
		(cam_fwd * 0.5 + cam_up * 0.85).normalized(),
		(cam_fwd * 0.85 + cam_up * 0.5 + cam_side * 0.35).normalized(),
		(Vector3.UP * 0.85 + cam_side * 0.4).normalized(),
		(cam_fwd * 0.95 + cam_up * 0.3).normalized()
	]

	for r_dir in ray_dirs:
		var query := PhysicsRayQueryParameters3D.new()
		query.from = origin
		query.to = origin + r_dir * 65.0
		query.exclude = [get_rid()]
		var res := space.intersect_ray(query)
		if res and not res.collider.is_in_group("players"):
			return res.position

	return Vector3.ZERO

func _process_web_swing(delta: float) -> void:
	# Если отпустили ПКМ или нажали Пробел — отцепляемся со взрывным бустом
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_action_just_pressed("jump"):
		_release_web_swing()
		return

	# Гравитация тянет вниз
	velocity.y -= gravity * delta

	# Вектор от игрока к точке крепления паутины
	var to_anchor: Vector3 = web_anchor_pos - global_position
	var cur_dist: float = to_anchor.length()

	# Физический маятник: если веревка натянута, убираем компоненту скорости от центра
	if cur_dist >= web_rope_length:
		var rope_dir: Vector3 = to_anchor.normalized()
		var vel_along_rope: float = velocity.dot(rope_dir)

		# Если удаляемся от якоря — гасим движение наружу и преобразуем в центростремительную силу
		if vel_along_rope < 0.0:
			velocity -= rope_dir * vel_along_rope
			# Сокращаем длину веревки для динамичного подтягивания к вершине дуги
			web_rope_length = maxf(8.0, web_rope_length - delta * 4.0)

		# Корректируем позицию чтобы не растягивать паутину
		global_position = web_anchor_pos - rope_dir * web_rope_length

	# Дополнительный разгон в сторону взгляда (W)
	if Input.is_action_pressed("move_forward"):
		var fwd: Vector3 = -camera.global_transform.basis.z
		velocity += fwd * (delta * 22.0)

	# Ограничение максимальной скорости полета
	if velocity.length() > swing_speed_max:
		velocity = velocity.normalized() * swing_speed_max

	# Поворот персонажа по вектору полета
	if velocity.length() > 3.0:
		var look_dir := Vector3(velocity.x, 0, velocity.z).normalized()
		if look_dir.length_squared() > 0.01 and model:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(look_dir.x, look_dir.z) + PI, delta * 12.0)

	# Если коснулись земли во время полета — мягкий переход в бег
	if is_on_floor():
		_release_web_swing(false)

func _release_web_swing(apply_boost: bool = true) -> void:
	is_swing_active = false
	state = State.NORMAL
	swing_cooldown = 0.12

	if apply_boost:
		var fwd: Vector3 = -camera.global_transform.basis.z
		velocity += fwd * 8.0 + Vector3.UP * 4.5
		# Звук свиста воздуха
		if audio_fx:
			audio_fx.stream = SoundFX.get_dodge()
			audio_fx.play()

# ========================================================
# ПЕРЕМЕЩЕНИЕ: WEB-ZIP (ТОЧЕЧНОЕ ПРИТЯГИВАНИЕ)
# ========================================================
func _try_start_web_zip() -> void:
	var space := get_world_3d().direct_space_state
	var origin: Vector3 = camera.global_position
	var dir: Vector3 = -camera.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin + dir * 75.0
	query.exclude = [get_rid()]
	var res := space.intersect_ray(query)

	if res and not res.collider.is_in_group("players"):
		zip_target_pos = res.position
		state = State.ZIPPING
		zip_timer = 0.0

		if audio_web:
			audio_web.stream = SoundFX.get_web_zip()
			audio_web.play()

func _process_web_zip(delta: float) -> void:
	zip_timer += delta
	var to_target: Vector3 = zip_target_pos - global_position
	var dist: float = to_target.length()

	# Прилетели к цели или вышло время
	if dist < 2.5 or zip_timer > 1.2:
		state = State.NORMAL
		# Катапультирующий прыжок на уступ
		velocity = -camera.global_transform.basis.z * 16.0 + Vector3.UP * 9.0
		return

	# Стремительный полет на натянутой нити
	velocity = to_target.normalized() * zip_speed
	var look_dir := Vector3(velocity.x, 0, velocity.z).normalized()
	if look_dir.length_squared() > 0.01 and model:
		model.rotation.y = atan2(look_dir.x, look_dir.z) + PI

# ========================================================
# ПЕРЕМЕЩЕНИЕ: WALL-RUN / WALL-CLIMB (БЕГ ПО СТЕНАМ)
# ========================================================
func _start_wall_run() -> void:
	state = State.WALL_RUNNING
	wall_run_timer = 0.0
	velocity.y = maxf(velocity.y, 4.0)

func _process_wall_run(delta: float) -> void:
	wall_run_timer += delta

	# Если нажали прыжок — мощный отскок от стены
	if Input.is_action_just_pressed("jump"):
		state = State.NORMAL
		velocity = wall_normal * 14.0 + Vector3.UP * 11.0 + (-cam_pivot.global_transform.basis.z * 6.0)
		return

	# Направление бега: вверх по стене
	var up_dir: Vector3 = Vector3.UP
	var side_dir: Vector3 = wall_normal.cross(Vector3.UP).normalized()
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	var wall_move: Vector3 = (up_dir * -input_dir.y + side_dir * input_dir.x).normalized()
	if wall_move.length_squared() > 0.01:
		velocity = wall_move * wall_run_speed - wall_normal * 2.0
	else:
		velocity = -wall_normal * 2.0

	# Если оторвались от стены или упали
	if not is_on_wall() and wall_run_timer > 0.2:
		state = State.NORMAL
	if is_on_floor():
		state = State.NORMAL

# ========================================================
# СПОСОБНОСТИ: СУПЕР-ПРЫЖОК
# ========================================================
func _process_super_jump(delta: float) -> void:
	if is_on_floor() and Input.is_action_pressed("jump"):
		is_charging_jump = true
		jump_charge = minf(1.0, jump_charge + delta * 2.0)
	elif is_charging_jump:
		# Отпустили пробел — запуск супер-прыжка!
		if jump_charge > 0.25:
			var force: float = lerpf(12.0, 28.0, jump_charge)
			var fwd: Vector3 = -cam_pivot.global_transform.basis.z
			velocity = fwd * (force * 0.45) + Vector3.UP * force

			if audio_fx:
				audio_fx.stream = SoundFX.get_super_jump()
				audio_fx.play()

		is_charging_jump = false
		jump_charge = 0.0

	if hud_jump_bar:
		hud_jump_bar.visible = is_charging_jump
		hud_jump_bar.value = jump_charge * 100.0

# ========================================================
# БОЕВАЯ СИСТЕМА (БЕЗ ОРУЖИЯ, ПАУЧЬИ СИЛЫ)
# ========================================================
func _process_combat(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0

	# 1. Выстрелы паутиной на ЛКМ (или ближний бой в упор)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_action_pressed("fire"):
		# Проверяем, есть ли враг в упор (< 2.5м)
		var melee_target := _get_melee_target(2.5)
		if melee_target and now > next_web_shoot_time:
			_perform_melee_attack(melee_target)
			next_web_shoot_time = now + 0.28
		elif now > next_web_shoot_time:
			_fire_web_shot()
			next_web_shoot_time = now + web_shoot_cooldown

	# 2. Web-Strike на Q (Акробатический рывок-удар по врагу)
	if Input.is_key_pressed(KEY_Q) and state != State.WEB_STRIKING:
		var strike_enemy := _find_targeted_enemy(45.0)
		if strike_enemy:
			_start_web_strike(strike_enemy)

	# 3. Web-Throw на E (Захват и бросок бочки/врага)
	if Input.is_key_pressed(KEY_E) and state != State.THROWING:
		_try_start_web_throw()

func _fire_web_shot() -> void:
	web_shot_hand_toggle = not web_shot_hand_toggle
	var wrist_pos: Vector3 = model.get_wrist_global_pos(web_shot_hand_toggle) if model else global_position + Vector3.UP * 1.2

	# Направление к точке прицела
	var space := get_world_3d().direct_space_state
	var cam_pos := camera.global_position
	var cam_fwd := -camera.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.new()
	query.from = cam_pos
	query.to = cam_pos + cam_fwd * 90.0
	query.exclude = [get_rid()]
	var res := space.intersect_ray(query)

	var target_pos: Vector3 = res.position if res else cam_pos + cam_fwd * 70.0
	var fire_dir: Vector3 = (target_pos - wrist_pos).normalized()

	# Спавн снаряда
	var proj = web_proj_scene.instantiate()
	get_parent().add_child(proj)
	proj.init_projectile(wrist_pos, fire_dir, current_peer_id)

	if audio_web:
		audio_web.stream = SoundFX.get_web_shoot()
		audio_web.play()

	if multiplayer.has_multiplayer_peer():
		_rpc_fire_web_shot.rpc(wrist_pos, fire_dir)

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_fire_web_shot(pos: Vector3, dir: Vector3) -> void:
	var proj = web_proj_scene.instantiate()
	get_parent().add_child(proj)
	proj.init_projectile(pos, dir, get_multiplayer_authority())

func _get_melee_target(max_dist: float) -> Node3D:
	var space := get_world_3d().direct_space_state
	var origin := camera.global_position
	var fwd := -camera.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin + fwd * max_dist
	query.exclude = [get_rid()]
	var res := space.intersect_ray(query)
	if res and res.collider != self and (res.collider.is_in_group("players") or res.collider.has_method("take_damage")):
		return res.collider
	return null

func _perform_melee_attack(target: Node3D) -> void:
	melee_combo_index = (melee_combo_index + 1) % 3
	if model:
		model.play_punch(melee_combo_index + 1)

	var dmg: int = [18, 24, 38][melee_combo_index]
	var knock: float = [10.0, 14.0, 26.0][melee_combo_index]

	if target.has_method("take_damage"):
		target.take_damage(dmg, current_peer_id, "Паучий удар")

	if "velocity" in target:
		var push := (target.global_position - global_position).normalized()
		target.velocity += push * knock + Vector3.UP * 4.0

	if audio_fx:
		audio_fx.stream = SoundFX.get_hitmarker(false)
		audio_fx.play()

# Web-Strike
func _find_targeted_enemy(max_dist: float) -> Node3D:
	var space := get_world_3d().direct_space_state
	var origin := camera.global_position
	var fwd := -camera.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin + fwd * max_dist
	query.exclude = [get_rid()]
	var res := space.intersect_ray(query)
	if res and res.collider != self and res.collider.is_in_group("players"):
		return res.collider
	return null

func _start_web_strike(enemy: Node3D) -> void:
	strike_target = enemy
	state = State.WEB_STRIKING
	strike_timer = 0.0

	if audio_web:
		audio_web.stream = SoundFX.get_web_zip()
		audio_web.play()

func _process_web_strike(delta: float) -> void:
	strike_timer += delta
	if not is_instance_valid(strike_target) or strike_timer > 1.2:
		state = State.NORMAL
		return

	var to_enemy: Vector3 = strike_target.global_position - global_position
	var dist: float = to_enemy.length()

	if dist < 2.0:
		# Наносим мощный дропкик с отбрасыванием
		if strike_target.has_method("take_damage"):
			strike_target.take_damage(40, current_peer_id, "Web-Strike")

		if "velocity" in strike_target:
			strike_target.velocity += velocity.normalized() * 32.0 + Vector3.UP * 6.0

		if audio_fx:
			audio_fx.stream = SoundFX.get_car_crash()
			audio_fx.play()

		# Отскок назад после удара
		velocity = -to_enemy.normalized() * 12.0 + Vector3.UP * 8.0
		state = State.NORMAL
		return

	velocity = to_enemy.normalized() * 45.0

# Web-Throw
func _try_start_web_throw() -> void:
	var space := get_world_3d().direct_space_state
	var origin := camera.global_position
	var fwd := -camera.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin + fwd * 30.0
	query.exclude = [get_rid()]
	var res := space.intersect_ray(query)

	if res and res.collider and (res.collider.is_in_group("throwable_objects") or res.collider.is_in_group("explosives")):
		held_throw_object = res.collider
		state = State.THROWING
		throw_spin_timer = 0.0
		throw_target_pos = origin + fwd * 45.0

		if held_throw_object is RigidBody3D:
			(held_throw_object as RigidBody3D).freeze = true

		if audio_fx:
			audio_fx.stream = SoundFX.get_web_throw()
			audio_fx.play()

func _process_web_throw(delta: float) -> void:
	throw_spin_timer += delta
	if not is_instance_valid(held_throw_object):
		state = State.NORMAL
		return

	# Раскручиваем предмет вокруг себя
	var angle := throw_spin_timer * TAU * 2.5
	var orbit_radius := 3.2
	var offset := Vector3(cos(angle) * orbit_radius, sin(angle) * 1.5 + 2.0, sin(angle) * orbit_radius)
	held_throw_object.global_position = global_position + offset

	# Запуск вперед через 0.35 секунды
	if throw_spin_timer >= 0.35:
		var throw_dir := -camera.global_transform.basis.z
		if held_throw_object.has_method("launch"):
			held_throw_object.launch(throw_dir, 38.0, current_peer_id)
		elif held_throw_object is RigidBody3D:
			var rb := held_throw_object as RigidBody3D
			rb.freeze = false
			rb.linear_velocity = throw_dir * 38.0

		state = State.NORMAL
		held_throw_object = null

# ========================================================
# КОКОН И СВЯЗЫВАНИЕ ПАУТИНОЙ
# ========================================================
func apply_web_shot(potency: float, dmg: int, shooter: int) -> void:
	take_damage(dmg, shooter, "Паутина")
	if health <= 0:
		return

	web_meter += potency
	web_entrapment_changed.emit(web_meter, 100.0)

	# Спайдер-чутье мигает при атаке
	if model:
		model.set_spider_sense(true)
		get_tree().create_timer(0.4).timeout.connect(func(): if is_instance_valid(model): model.set_spider_sense(false))

	if web_meter >= 100.0 and state != State.COCOONED:
		_enter_cocoon()

func _enter_cocoon() -> void:
	state = State.COCOONED
	cocoon_timer = 3.5
	is_swing_active = false
	if model:
		model.set_cocooned(true)

	# Оповещение в чат
	var stats = get_node_or_null("/root/GameStats")
	if stats:
		stats.emit_signal("kill_feed_message", "🕸️ %s полностью связан в кокон!" % name)

func _process_cocoon(delta: float) -> void:
	cocoon_timer -= delta
	velocity.x = lerpf(velocity.x, 0.0, delta * 10.0)
	velocity.z = lerpf(velocity.z, 0.0, delta * 10.0)
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Вырывание из кокона нажатиями клавиш
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("fire"):
		cocoon_timer -= 0.35

	if cocoon_timer <= 0.0:
		state = State.NORMAL
		web_meter = 0.0
		web_entrapment_changed.emit(0.0, 100.0)
		if model:
			model.set_cocooned(false)

func take_damage(dmg: int, attacker_id: int = 0, weapon: String = "Удар") -> void:
	if health <= 0:
		return
	health = maxi(0, health - dmg)
	health_changed.emit(health, max_health)

	if health <= 0:
		_die(attacker_id, weapon)

func _die(attacker_id: int, weapon: String) -> void:
	died.emit(attacker_id)
	var stats = get_node_or_null("/root/GameStats")
	if stats and stats.has_method("record_kill"):
		stats.record_kill(attacker_id, current_peer_id, weapon)

	# Респавн
	visible = false
	collision_shape.set_deferred("disabled", true)
	await get_tree().create_timer(2.0).timeout
	_respawn()

func _respawn() -> void:
	health = max_health
	web_meter = 0.0
	state = State.NORMAL
	if model: model.set_cocooned(false)
	visible = true
	collision_shape.set_deferred("disabled", false)
	health_changed.emit(health, max_health)

	# Находим случайную точку спавна
	var spawn_points := get_tree().get_nodes_in_group("spawn_points")
	if not spawn_points.is_empty():
		var sp = spawn_points.pick_random() as Node3D
		global_position = sp.global_position + Vector3.UP * 1.5
	else:
		global_position = Vector3(0, 10, 0)
	velocity = Vector3.ZERO

# ========================================================
# ОТРИСОВКА ЛИНИИ ПАУТИНЫ
# ========================================================
func _update_web_visuals() -> void:
	if not web_line_mesh:
		return

	var draw_web := (state == State.SWINGING or state == State.ZIPPING or is_swing_active)
	if not draw_web:
		web_line_mesh.visible = false
		return

	web_line_mesh.visible = true
	var wrist_pos: Vector3 = model.get_wrist_global_pos(swing_hand_is_right) if model else global_position + Vector3.UP * 1.2
	var target_pos: Vector3 = web_anchor_pos if (state == State.SWINGING or is_swing_active) else zip_target_pos

	var imm := web_line_mesh.mesh as ImmediateMesh
	if imm == null:
		imm = ImmediateMesh.new()
		web_line_mesh.mesh = imm

	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_LINES)
	imm.surface_set_color(Color(0.96, 0.98, 1.0, 0.95))
	imm.surface_add_vertex(wrist_pos - global_position)
	imm.surface_add_vertex(target_pos - global_position)
	imm.surface_end()

func _update_camera_fov(delta: float) -> void:
	if not is_local_player() or not camera:
		return
	var speed := velocity.length()
	target_fov = lerpf(75.0, 95.0, clampf(speed / swing_speed_max, 0.0, 1.0))
	camera.fov = lerpf(camera.fov, target_fov, delta * 8.0)

# ========================================================
# СЕТЕВАЯ СИНХРОНИЗАЦИЯ
# ========================================================
func _sync_network_state() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var now_anchor := web_anchor_pos if state == State.SWINGING else zip_target_pos
	_rpc_sync_state.rpc(global_position, rotation, velocity, int(state), now_anchor, is_swing_active, health, web_meter)

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_sync_state(pos: Vector3, rot: Vector3, vel: Vector3, st: int, anchor: Vector3, swing_act: bool, hp: int, w_meter: float) -> void:
	sync_pos = pos
	sync_rot = rot
	sync_vel = vel
	sync_state = st
	sync_anchor = anchor
	sync_web_active = swing_act
	health = hp
	web_meter = w_meter

func _process_remote_interpolation(delta: float) -> void:
	global_position = global_position.lerp(sync_pos, delta * 16.0)
	rotation.y = lerp_angle(rotation.y, sync_rot.y, delta * 16.0)
	velocity = sync_vel
	state = sync_state as State
	web_anchor_pos = sync_anchor
	is_swing_active = sync_web_active

	if model:
		model.set_cocooned(state == State.COCOONED)
		model.update_animation(delta, velocity, is_on_floor(), state == State.SWINGING, state == State.ZIPPING, state == State.WALL_RUNNING, state == State.WEB_STRIKING, false, 0.0)

# ========================================================
# HUD СПАЙДЕРМЕНА
# ========================================================
func _build_spider_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 95
	add_child(hud_layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(root)

	# 1. Прицел паука по центру
	hud_crosshair = Control.new()
	hud_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_child(hud_crosshair)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(6, 6)
	dot.position = Vector2(-3, -3)
	dot.color = Color(1.0, 1.0, 1.0, 0.9)
	hud_crosshair.add_child(dot)

	# Индикатор дальности / готовности паутины
	hud_reticle_label = Label.new()
	hud_reticle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_reticle_label.position = Vector2(-80, 12)
	hud_reticle_label.custom_minimum_size = Vector2(160, 24)
	hud_reticle_label.add_theme_font_size_override("font_size", 12)
	hud_reticle_label.modulate = Color(0.2, 0.9, 1.0)
	hud_crosshair.add_child(hud_reticle_label)

	# 2. HP и статус внизу слева
	var bottom_left := VBoxContainer.new()
	bottom_left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_left.offset_left = 30
	bottom_left.offset_bottom = -30
	bottom_left.custom_minimum_size = Vector2(240, 60)
	root.add_child(bottom_left)

	var hp_lbl := Label.new()
	hp_lbl.text = "❤️ ЗДОРОВЬЕ:"
	bottom_left.add_child(hp_lbl)

	hud_hp_bar = ProgressBar.new()
	hud_hp_bar.max_value = max_health
	hud_hp_bar.value = health
	hud_hp_bar.custom_minimum_size = Vector2(240, 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.85, 0.15, 0.2)
	sb.set_corner_radius_all(4)
	hud_hp_bar.add_theme_stylebox_override("fill", sb)
	bottom_left.add_child(hud_hp_bar)

	var web_lbl := Label.new()
	web_lbl.text = "🕸️ ЗАХВАТ В ПАУТИНУ:"
	bottom_left.add_child(web_lbl)

	hud_web_bar = ProgressBar.new()
	hud_web_bar.max_value = 100
	hud_web_bar.value = 0
	hud_web_bar.custom_minimum_size = Vector2(240, 14)
	var sb_w := StyleBoxFlat.new()
	sb_w.bg_color = Color(0.9, 0.92, 1.0)
	sb_w.set_corner_radius_all(4)
	hud_web_bar.add_theme_stylebox_override("fill", sb_w)
	bottom_left.add_child(hud_web_bar)

	# 3. Индикатор зарядки супер-прыжка по центру снизу
	hud_jump_bar = ProgressBar.new()
	hud_jump_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hud_jump_bar.offset_left = -100
	hud_jump_bar.offset_top = -120
	hud_jump_bar.offset_right = 100
	hud_jump_bar.offset_bottom = -104
	hud_jump_bar.max_value = 100
	hud_jump_bar.visible = false
	var sb_j := StyleBoxFlat.new()
	sb_j.bg_color = Color(1.0, 0.85, 0.1)
	sb_j.set_corner_radius_all(4)
	hud_jump_bar.add_theme_stylebox_override("fill", sb_j)
	root.add_child(hud_jump_bar)

	# 4. Подсказки управления справа внизу
	var hints := Label.new()
	hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hints.offset_left = -320
	hints.offset_bottom = -25
	hints.text = "ЛКМ: Выстрел паутиной / Удар\nПКМ (Зажать): Полет на паутине\nF / СКМ: Web-Zip (Рывок)\nQ: Web-Strike (Удар в полете)\nE: Паутинный бросок предмета\nПробел (Зажать): Супер-прыжок\nСтена + W: Бег по стене"
	hints.add_theme_font_size_override("font_size", 13)
	hints.modulate = Color(0.85, 0.9, 1.0, 0.85)
	root.add_child(hints)

func _update_hud_reticle() -> void:
	if not hud_reticle_label or not camera:
		return

	if hud_hp_bar: hud_hp_bar.value = health
	if hud_web_bar: hud_web_bar.value = web_meter

	var space := get_world_3d().direct_space_state
	var origin := camera.global_position
	var fwd := -camera.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin + fwd * 75.0
	query.exclude = [get_rid()]
	var res := space.intersect_ray(query)

	if res:
		var dist := int(origin.distance_to(res.position))
		if res.collider.is_in_group("players"):
			hud_reticle_label.text = "[ Q: Web-Strike | %dm ]" % dist
			hud_reticle_label.modulate = Color(1.0, 0.2, 0.2)
		elif res.collider.is_in_group("throwable_objects"):
			hud_reticle_label.text = "[ E: Захват паутиной | %dm ]" % dist
			hud_reticle_label.modulate = Color(1.0, 0.85, 0.1)
		else:
			hud_reticle_label.text = "[ F: Web-Zip | %dm ]" % dist
			hud_reticle_label.modulate = Color(0.2, 0.95, 0.45)
	else:
		hud_reticle_label.text = ""
