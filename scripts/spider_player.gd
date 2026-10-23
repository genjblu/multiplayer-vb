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
@export var swing_speed_max: float = 48.0
@export var zip_speed: float = 40.0
@export var wall_run_speed: float = 18.0
@export var gravity: float = 24.0

var state: State = State.NORMAL
var current_peer_id: int = 1

# --- Web Swing (Spider-Man 2 2004 Physics) ---
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
var wall_move_dir: Vector3 = Vector3.UP

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
var web_meter: float = 0.0
var cocoon_timer: float = 0.0

# --- Combat Cooldowns & 4-Hit Limb Combo ---
var web_shoot_cooldown: float = 0.18
var next_web_shoot_time: float = 0.0
var web_shot_hand_toggle: bool = false
var melee_combo_index: int = 0
var last_melee_time: float = 0.0
const MELEE_COMBO_TIMEOUT: float = 1.1

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
var hud_state_label: Label = null

func is_local_player() -> bool:
	if not is_inside_tree() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return true
	return get_multiplayer_authority() == multiplayer.get_unique_id()

func _ready() -> void:
	current_peer_id = name.to_int() if name.is_valid_int() else 1
	health = max_health

	# Персонаж спавнится спиной к камере (смотрит вперед по -Z)
	if model:
		model.rotation.y = PI

	if is_local_player():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		cam_pivot.top_level = true
		cam_pivot.global_position = global_position + Vector3(0, 1.45, 0)
		cam_rot_h = 0.0
		cam_rot_v = deg_to_rad(10.0)
		cam_pivot.global_rotation = Vector3(0.0, cam_rot_h, 0.0)
		spring_arm.rotation = Vector3(cam_rot_v, 0.0, 0.0)
		camera.make_current()
		_build_spider_hud()
	else:
		camera.current = false

	sync_pos = global_position
	sync_rot = rotation

# Использование _input для гарантированного приема мыши (никакой UI не заблокирует обзор)
func _input(event: InputEvent) -> void:
	if not is_local_player() or state == State.COCOONED:
		return

	# Захват мыши по клику ЛКМ в окно
	if event is InputEventMouseButton and event.pressed:
		var is_mobile: bool = OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]
		if not is_mobile and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Вращение камеры мышью
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = 0.003
		if GameSettings:
			sens = GameSettings.mouse_sensitivity
		var inv_y: float = -1.0 if (GameSettings and GameSettings.invert_y) else 1.0

		cam_rot_h -= event.relative.x * sens
		cam_rot_v = clampf(cam_rot_v - event.relative.y * sens * inv_y, deg_to_rad(-75.0), deg_to_rad(70.0))

func _physics_process(delta: float) -> void:
	if is_local_player():
		_process_local_player(delta)
		_sync_network_state()
	else:
		_process_remote_interpolation(delta)

	_update_web_visuals()
	_update_camera_fov(delta)

func _process_local_player(delta: float) -> void:
	# 1. Если связан в коконе
	if state == State.COCOONED:
		_process_cocoon(delta)
		move_and_slide()
		return

	# Рассеивание паутины
	if web_meter > 0.0:
		web_meter = maxf(0.0, web_meter - delta * 12.0)
		web_entrapment_changed.emit(web_meter, 100.0)

	if swing_cooldown > 0.0:
		swing_cooldown -= delta

	# ========================================================
	# КАМЕРА: независимое следование и вращение пивота
	# ========================================================
	cam_pivot.global_position = global_position + Vector3(0, 1.45, 0)
	cam_pivot.global_rotation = Vector3(0.0, cam_rot_h, 0.0)
	spring_arm.rotation = Vector3(cam_rot_v, 0.0, 0.0)

	# 2. Обработка супер-прыжка
	_process_super_jump(delta)

	# 3. Бой и паучьи приёмы
	_process_combat(delta)

	# 4. Состояния перемещения
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

	# 5. Процедурная анимация
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

	_update_hud_reticle()

# ========================================================
# ПЕРЕМЕЩЕНИЕ: ОБЫЧНЫЙ БЕГ И ПРЫЖКИ
# ========================================================
func _process_normal_movement(delta: float) -> void:
	# Гравитация
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Ввод направления W/S/A/D относительно камеры
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	var cam_basis: Basis = cam_pivot.global_transform.basis
	var cam_forward: Vector3 = -cam_basis.z
	var cam_right: Vector3 = cam_basis.x
	cam_forward.y = 0.0
	cam_right.y = 0.0
	if cam_forward.length_squared() > 0.001:
		cam_forward = cam_forward.normalized()
	if cam_right.length_squared() > 0.001:
		cam_right = cam_right.normalized()

	var move_dir: Vector3 = (cam_forward * -input_dir.y + cam_right * input_dir.x).normalized()

	var is_sprint: bool = Input.is_key_pressed(KEY_SHIFT)
	var speed: float = sprint_speed if is_sprint else base_speed

	if move_dir.length_squared() > 0.01:
		velocity.x = lerpf(velocity.x, move_dir.x * speed, delta * 14.0)
		velocity.z = lerpf(velocity.z, move_dir.z * speed, delta * 14.0)
		# Персонаж смотрит в сторону движения
		var target_angle: float = atan2(move_dir.x, move_dir.z)
		if model:
			model.rotation.y = lerp_angle(model.rotation.y, target_angle, delta * 14.0)
	else:
		velocity.x = lerpf(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 10.0)

	# Прыжок
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_charging_jump:
		velocity.y = 11.5

	# Зацеп за стену (карабкание)
	if is_on_wall() and (Input.is_action_pressed("move_forward") or move_dir.length() > 0.4):
		var n: Vector3 = get_wall_normal()
		if n.dot(Vector3.UP) < 0.2: # Вертикальная стена
			wall_normal = n
			_start_wall_run()
			return

	# Запуск раскачивания на паутине (ПКМ в воздухе)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not is_on_floor() and swing_cooldown <= 0.0:
		_try_start_web_swing()

	# Web-Zip (F или СКМ)
	if Input.is_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_try_start_web_zip()

# ========================================================
# ПЕРЕМЕЩЕНИЕ: WEB-SWING (Spider-Man 2 2004 Physics)
# ========================================================
func _try_start_web_swing() -> void:
	var anchor := _find_swing_anchor()
	if anchor == Vector3.ZERO:
		return

	web_anchor_pos = anchor
	web_rope_length = maxf(12.0, global_position.distance_to(web_anchor_pos))
	is_swing_active = true
	state = State.SWINGING
	swing_hand_is_right = not swing_hand_is_right

	if audio_web:
		audio_web.stream = SoundFX.get_web_shoot()
		audio_web.play()

	# Начальный импульс по дуге маятника
	var to_anchor := (web_anchor_pos - global_position).normalized()
	var cam_fwd: Vector3 = -cam_pivot.global_transform.basis.z
	var swing_tangent := cam_fwd - to_anchor * cam_fwd.dot(to_anchor)
	if swing_tangent.length_squared() > 0.01:
		velocity += swing_tangent.normalized() * 6.5 + Vector3.UP * 2.0

func _find_swing_anchor() -> Vector3:
	var space := get_world_3d().direct_space_state
	var origin: Vector3 = global_position + Vector3.UP * 1.5

	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	var cam_up: Vector3 = Vector3.UP
	var side_mult: float = 1.0 if swing_hand_is_right else -1.0
	var cam_side: Vector3 = cam_pivot.global_transform.basis.x * side_mult

	# 1. Веер лучей для предпочитаемой руки (вперед, вверх, вбок)
	var ray_dirs := [
		(cam_fwd * 0.45 + cam_side * 0.6 + cam_up * 0.65).normalized(),
		(cam_fwd * 0.2 + cam_side * 0.8 + cam_up * 0.55).normalized(),
		(cam_fwd * 0.7 + cam_side * 0.35 + cam_up * 0.6).normalized(),
		(cam_side * 0.85 + cam_up * 0.5).normalized(),
		(cam_fwd * 0.85 + cam_up * 0.45).normalized(),
		(cam_fwd * 0.35 + cam_up * 0.92).normalized(),
		# 2. Запасной веер для противоположной стороны (если с предпочитаемой стороны нет небоскрёба)
		(cam_fwd * 0.45 - cam_side * 0.6 + cam_up * 0.65).normalized(),
		(cam_fwd * 0.2 - cam_side * 0.8 + cam_up * 0.55).normalized(),
		(-cam_side * 0.85 + cam_up * 0.5).normalized()
	]

	for r_dir in ray_dirs:
		var query := PhysicsRayQueryParameters3D.new()
		query.from = origin
		query.to = origin + r_dir * 95.0
		query.exclude = [get_rid()]
		var res := space.intersect_ray(query)
		if res and not res.collider.is_in_group("players"):
			if res.position.y > global_position.y - 2.0:
				# Если зацепились за противоположную сторону — переключаем руку
				if r_dir.dot(cam_side) < 0.0:
					swing_hand_is_right = not swing_hand_is_right
				return res.position

	return Vector3.ZERO

func _process_web_swing(delta: float) -> void:
	# Отпускание ПКМ или прыжок
	var release_with_jump := Input.is_action_just_pressed("jump")
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or release_with_jump:
		_release_web_swing(release_with_jump)
		return

	# 1. Гравитация маятника
	velocity.y -= gravity * delta

	# 2. Вектор к точке крепления верёвки
	var to_anchor: Vector3 = web_anchor_pos - global_position
	var cur_dist: float = to_anchor.length()

	if cur_dist > 0.01:
		var rope_dir: Vector3 = to_anchor / cur_dist

		# 3. Физическое ограничение верёвки
		if cur_dist >= web_rope_length:
			var vel_radial: float = velocity.dot(rope_dir)
			if vel_radial < 0.0:
				# Устраняем радиальную скорость от якоря
				velocity -= rope_dir * vel_radial

			# Центростремительная сила дуги
			var speed_sq: float = velocity.length_squared()
			var centripetal: float = speed_sq / maxf(web_rope_length, 6.0)
			velocity += rope_dir * centripetal * delta * 0.45

			# Мягкая фиксация длины нити
			global_position = web_anchor_pos - rope_dir * web_rope_length

		# 4. Раскачка и подтягивание (Spider-Man 2 Pumping)
		# Зажатый W или Shift разгоняет по касательной и укорачивает нить для набора высоты
		if Input.is_action_pressed("move_forward"):
			var spd := velocity.length()
			if spd > 1.0:
				velocity += velocity.normalized() * (20.0 * delta)
			# Укорачивание верёвки при движении вверх по дуге
			if velocity.y > -2.0:
				web_rope_length = maxf(8.0, web_rope_length - delta * 6.5)

		# 5. Боковое маневрирование вокруг зданий (Banking)
		var cam_side: Vector3 = cam_pivot.global_transform.basis.x
		cam_side.y = 0.0
		if cam_side.length_squared() > 0.001:
			cam_side = cam_side.normalized()
		var strafe: float = Input.get_axis("move_left", "move_right")
		velocity += cam_side * strafe * (16.0 * delta)

	# Ограничение максимальной скорости
	if velocity.length() > swing_speed_max:
		velocity = velocity.normalized() * swing_speed_max

	# Поворот персонажа по вектору полета
	var horiz_vel := Vector3(velocity.x, 0, velocity.z)
	if horiz_vel.length_squared() > 1.5 and model:
		var look_dir := horiz_vel.normalized()
		model.rotation.y = lerp_angle(model.rotation.y, atan2(look_dir.x, look_dir.z), delta * 12.0)

	# Касание земли
	if is_on_floor():
		_release_web_swing(false)

func _release_web_swing(jump_boost: bool = false) -> void:
	is_swing_active = false
	state = State.NORMAL
	swing_cooldown = 0.12
	web_rope_length = 0.0

	# Сохранение честной физической инерции маятника
	if jump_boost:
		# Акробатический прыжок на вершине дуги
		if velocity.y > 1.5:
			velocity *= 1.15
			velocity.y += 4.5
		if audio_fx:
			audio_fx.stream = SoundFX.get_dodge()
			audio_fx.play()

# ========================================================
# ПЕРЕМЕЩЕНИЕ: WEB-ZIP (ТОЧЕЧНЫЙ РЫВОК)
# ========================================================
func _try_start_web_zip() -> void:
	var space := get_world_3d().direct_space_state
	var origin: Vector3 = camera.global_position
	var dir: Vector3 = -camera.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin + dir * 85.0
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

	if dist < 2.5 or zip_timer > 1.2:
		state = State.NORMAL
		velocity = -camera.global_transform.basis.z * 16.0 + Vector3.UP * 8.5
		return

	velocity = to_target.normalized() * zip_speed
	var look_dir := Vector3(velocity.x, 0, velocity.z).normalized()
	if look_dir.length_squared() > 0.01 and model:
		model.rotation.y = atan2(look_dir.x, look_dir.z)

# ========================================================
# ПЕРЕМЕЩЕНИЕ: КАРАБКАНİЕ И БЕГ ПО СТЕНАМ (WALL RUN)
# Управление ориентировано относительно камеры (A = влево по экрану, D = вправо)
# ========================================================
func _start_wall_run() -> void:
	state = State.WALL_RUNNING
	wall_run_timer = 0.0
	velocity.y = maxf(velocity.y, 4.0)

func _process_wall_run(delta: float) -> void:
	wall_run_timer += delta

	# Прыжок со стены
	if Input.is_action_just_pressed("jump"):
		state = State.NORMAL
		velocity = wall_normal * 14.0 + Vector3.UP * 11.0 + (-cam_pivot.global_transform.basis.z * 6.0)
		return

	# ========================================================
	# КАМЕРО-ОРИЕНТИРОВАННОЕ УПРАВЛЕНИЕ НА СТЕНЕ:
	# wall_right = проекция вектора экрана вправо на стену
	# wall_up = вектор вверх по стене
	# ========================================================
	var cam_right: Vector3 = cam_pivot.global_transform.basis.x
	# Проекция на плоскость стены:
	var wall_right: Vector3 = (cam_right - wall_normal * cam_right.dot(wall_normal)).normalized()
	if wall_right.length_squared() < 0.01:
		wall_right = Vector3.UP.cross(wall_normal).normalized()

	var wall_up: Vector3 = wall_normal.cross(wall_right).normalized()
	if wall_up.dot(Vector3.UP) < 0.0:
		wall_up = -wall_up
		wall_right = -wall_right

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	# W (-input_dir.y) -> wall_up (вверх по стене)
	# S (+input_dir.y) -> -wall_up (вниз по стене)
	# D (+input_dir.x) -> wall_right (вправо по экрану)
	# A (-input_dir.x) -> -wall_right (влево по экрану)
	var move_vec: Vector3 = wall_up * -input_dir.y + wall_right * input_dir.x

	if move_vec.length_squared() > 0.01:
		wall_move_dir = move_vec.normalized()
		velocity = wall_move_dir * wall_run_speed - wall_normal * 3.0
	else:
		velocity = -wall_normal * 3.0

	# Прижимание к стене
	if not is_on_floor():
		velocity.y -= gravity * delta * 0.12

	# Ориентация модели на стене:
	# Грудь (+Z) направлена к стене (-wall_normal)
	# Вверх (+Y) направлен по вектору движения wall_move_dir
	if model:
		var target_fwd := -wall_normal
		var target_up := wall_move_dir if move_vec.length_squared() > 0.01 else wall_up
		var target_side := target_up.cross(target_fwd).normalized()
		target_up = target_fwd.cross(target_side).normalized()
		var wall_basis := Basis(target_side, target_up, target_fwd)
		model.global_transform.basis = model.global_transform.basis.slerp(wall_basis, delta * 12.0)

	# Сход со стены
	if not is_on_wall() and wall_run_timer > 0.25:
		state = State.NORMAL
	if is_on_floor():
		state = State.NORMAL

# ========================================================
# СПОСОБНОСТИ: СУПЕР-ПРЫЖОК
# ========================================================
func _process_super_jump(delta: float) -> void:
	if is_on_floor() and Input.is_action_pressed("jump"):
		is_charging_jump = true
		jump_charge = minf(1.0, jump_charge + delta * 2.2)
	elif is_charging_jump:
		if jump_charge > 0.2:
			var force: float = lerpf(12.0, 30.0, jump_charge)
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
# БОЕВАЯ СИСТЕМА: 4-ХИТОВОЕ КОМБО КОНЕЧНОСТЯМИ
# ========================================================
func _process_combat(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0

	# Сброс серии ударов по таймауту
	if now - last_melee_time > MELEE_COMBO_TIMEOUT:
		melee_combo_index = 0

	# 1. ЛКМ: ближний бой в упор (< 2.8м) или выстрел паутиной
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_action_pressed("fire"):
		var melee_target := _get_melee_target(2.8)
		if melee_target and now > next_web_shoot_time:
			_perform_melee_attack(melee_target)
			next_web_shoot_time = now + 0.32
		elif now > next_web_shoot_time:
			_fire_web_shot()
			next_web_shoot_time = now + web_shoot_cooldown

	# 2. Q: Web-Strike (Акробатический налёт-дропкик)
	if Input.is_key_pressed(KEY_Q) and state != State.WEB_STRIKING:
		var strike_enemy := _find_targeted_enemy(45.0)
		if strike_enemy:
			_start_web_strike(strike_enemy)

	# 3. E: Web-Throw (Захват и бросок бочки)
	if Input.is_key_pressed(KEY_E) and state != State.THROWING:
		_try_start_web_throw()

func _fire_web_shot() -> void:
	web_shot_hand_toggle = not web_shot_hand_toggle
	var wrist_pos: Vector3 = model.get_wrist_global_pos(web_shot_hand_toggle) if model else global_position + Vector3.UP * 1.2

	var space := get_world_3d().direct_space_state
	var cam_pos := camera.global_position
	var cam_fwd := -camera.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.new()
	query.from = cam_pos
	query.to = cam_pos + cam_fwd * 90.0
	query.exclude = [get_rid()]
	var res := space.intersect_ray(query)

	var target_pos: Vector3 = res.position if res else cam_pos + cam_fwd * 75.0
	var fire_dir: Vector3 = (target_pos - wrist_pos).normalized()

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
	if res and res.collider != self and (res.collider.is_in_group("players") or res.collider.has_method("take_damage") or res.collider.is_in_group("throwable_objects")):
		return res.collider
	return null

func _perform_melee_attack(target: Node3D) -> void:
	last_melee_time = Time.get_ticks_msec() / 1000.0
	melee_combo_index = (melee_combo_index % 4) + 1

	if model and model.has_method("play_punch"):
		model.play_punch(melee_combo_index)

	# Урон и импульс растут с каждым ударом серии
	var dmg: int = [18, 26, 36, 50][melee_combo_index - 1]
	var knock: float = [8.0, 14.0, 22.0, 32.0][melee_combo_index - 1]

	var attack_names := ["Джеб", "Кросс", "Удар ногой с разворота", "Паучий flip-kick"]
	var attack_name: String = attack_names[melee_combo_index - 1]

	if target.has_method("take_damage"):
		target.take_damage(dmg, current_peer_id, attack_name)

	if "velocity" in target:
		var push := (target.global_position - global_position).normalized()
		target.velocity += push * knock + Vector3.UP * (3.0 + float(melee_combo_index) * 1.5)
	elif target is RigidBody3D:
		var push := (target.global_position - global_position).normalized()
		(target as RigidBody3D).apply_central_impulse(push * knock * 2.0 + Vector3.UP * 8.0)

	if audio_fx:
		audio_fx.stream = SoundFX.get_hitmarker(melee_combo_index == 4)
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

	if dist < 2.2:
		if strike_target.has_method("take_damage"):
			strike_target.take_damage(45, current_peer_id, "Web-Strike Dropkick")

		if "velocity" in strike_target:
			strike_target.velocity += velocity.normalized() * 34.0 + Vector3.UP * 7.0

		if audio_fx:
			audio_fx.stream = SoundFX.get_car_crash()
			audio_fx.play()

		velocity = -to_enemy.normalized() * 14.0 + Vector3.UP * 9.0
		state = State.NORMAL
		return

	velocity = to_enemy.normalized() * 48.0

# Web-Throw
func _try_start_web_throw() -> void:
	var space := get_world_3d().direct_space_state
	var origin := camera.global_position
	var fwd := -camera.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin + fwd * 35.0
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

	var angle := throw_spin_timer * TAU * 2.5
	var orbit_radius := 3.2
	var offset := Vector3(cos(angle) * orbit_radius, sin(angle) * 1.5 + 2.0, sin(angle) * orbit_radius)
	held_throw_object.global_position = global_position + offset

	if throw_spin_timer >= 0.35:
		var throw_dir := -camera.global_transform.basis.z
		if held_throw_object.has_method("launch"):
			held_throw_object.launch(throw_dir, 40.0, current_peer_id)
		elif held_throw_object is RigidBody3D:
			var rb := held_throw_object as RigidBody3D
			rb.freeze = false
			rb.linear_velocity = throw_dir * 40.0

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

	if model and model.has_method("set_spider_sense"):
		model.set_spider_sense(true)
		get_tree().create_timer(0.4).timeout.connect(func(): if is_instance_valid(model): model.set_spider_sense(false))

	if web_meter >= 100.0 and state != State.COCOONED:
		_enter_cocoon()

func _enter_cocoon() -> void:
	state = State.COCOONED
	cocoon_timer = 3.5
	is_swing_active = false
	if model and model.has_method("set_cocooned"):
		model.set_cocooned(true)

	var stats = get_node_or_null("/root/GameStats")
	if stats:
		stats.emit_signal("kill_feed_message", "🕸️ %s полностью связан в кокон!" % name)

func _process_cocoon(delta: float) -> void:
	cocoon_timer -= delta
	velocity.x = lerpf(velocity.x, 0.0, delta * 10.0)
	velocity.z = lerpf(velocity.z, 0.0, delta * 10.0)
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("fire"):
		cocoon_timer -= 0.35

	if cocoon_timer <= 0.0:
		state = State.NORMAL
		web_meter = 0.0
		web_entrapment_changed.emit(0.0, 100.0)
		if model and model.has_method("set_cocooned"):
			model.set_cocooned(false)

func take_damage(dmg: int, attacker_id: int = 0, weapon: String = "Паучий удар") -> void:
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

	visible = false
	collision_shape.set_deferred("disabled", true)
	await get_tree().create_timer(2.0).timeout
	_respawn()

func _respawn() -> void:
	health = max_health
	web_meter = 0.0
	state = State.NORMAL
	if model and model.has_method("set_cocooned"):
		model.set_cocooned(false)
	visible = true
	collision_shape.set_deferred("disabled", false)
	health_changed.emit(health, max_health)

	var spawn_points := get_tree().get_nodes_in_group("spawn_points")
	if not spawn_points.is_empty():
		var sp = spawn_points.pick_random() as Node3D
		global_position = sp.global_position + Vector3.UP * 1.5
	else:
		global_position = Vector3(-235.2, 88.7, -215.6)
	velocity = Vector3.ZERO

# ========================================================
# ОТРИСОВКА ПАУТИНЫ И FOV
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
	target_fov = lerpf(75.0, 96.0, clampf(speed / swing_speed_max, 0.0, 1.0))
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
# HUD СПАЙДЕРМЕНА (БЕЗ БЛОКИРОВКИ МЫШИ)
# ========================================================
func _build_spider_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 95
	add_child(hud_layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(root)

	# 1. Прицел
	hud_crosshair = Control.new()
	hud_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hud_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_crosshair)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(6, 6)
	dot.position = Vector2(-3, -3)
	dot.color = Color(1.0, 1.0, 1.0, 0.9)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_crosshair.add_child(dot)

	hud_reticle_label = Label.new()
	hud_reticle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_reticle_label.position = Vector2(-80, 12)
	hud_reticle_label.custom_minimum_size = Vector2(160, 24)
	hud_reticle_label.add_theme_font_size_override("font_size", 12)
	hud_reticle_label.modulate = Color(0.2, 0.9, 1.0)
	hud_reticle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_crosshair.add_child(hud_reticle_label)

	# 2. HP и кокон
	var bottom_left := VBoxContainer.new()
	bottom_left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_left.offset_left = 30
	bottom_left.offset_bottom = -30
	bottom_left.custom_minimum_size = Vector2(240, 60)
	bottom_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom_left)

	var hp_lbl := Label.new()
	hp_lbl.text = "❤️ ЗДОРОВЬЕ:"
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left.add_child(hp_lbl)

	hud_hp_bar = ProgressBar.new()
	hud_hp_bar.max_value = max_health
	hud_hp_bar.value = health
	hud_hp_bar.custom_minimum_size = Vector2(240, 18)
	hud_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.85, 0.15, 0.2)
	sb.set_corner_radius_all(4)
	hud_hp_bar.add_theme_stylebox_override("fill", sb)
	bottom_left.add_child(hud_hp_bar)

	var web_lbl := Label.new()
	web_lbl.text = "🕸️ КОКОН:"
	web_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left.add_child(web_lbl)

	hud_web_bar = ProgressBar.new()
	hud_web_bar.max_value = 100
	hud_web_bar.value = 0
	hud_web_bar.custom_minimum_size = Vector2(240, 14)
	hud_web_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb_w := StyleBoxFlat.new()
	sb_w.bg_color = Color(0.9, 0.92, 1.0)
	sb_w.set_corner_radius_all(4)
	hud_web_bar.add_theme_stylebox_override("fill", sb_w)
	bottom_left.add_child(hud_web_bar)

	# 3. Индикатор состояния
	hud_state_label = Label.new()
	hud_state_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_state_label.offset_left = -150
	hud_state_label.offset_right = 150
	hud_state_label.offset_top = 12
	hud_state_label.offset_bottom = 40
	hud_state_label.add_theme_font_size_override("font_size", 16)
	hud_state_label.modulate = Color(0.4, 0.9, 1.0, 0.9)
	hud_state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_state_label)

	# 4. Зарядка прыжка
	hud_jump_bar = ProgressBar.new()
	hud_jump_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hud_jump_bar.offset_left = -100
	hud_jump_bar.offset_top = -120
	hud_jump_bar.offset_right = 100
	hud_jump_bar.offset_bottom = -104
	hud_jump_bar.max_value = 100
	hud_jump_bar.visible = false
	hud_jump_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb_j := StyleBoxFlat.new()
	sb_j.bg_color = Color(1.0, 0.85, 0.1)
	sb_j.set_corner_radius_all(4)
	hud_jump_bar.add_theme_stylebox_override("fill", sb_j)
	root.add_child(hud_jump_bar)

	# 5. Подсказки управления
	var hints := Label.new()
	hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hints.offset_left = -330
	hints.offset_bottom = -25
	hints.text = "ЛКМ: Паутина / Серия ударов\nПКМ (Зажать): Полёт (маятник)\nShift / W в полёте: Раскачка\nПробел на взлёте: Сальто-ускорение\nF / СКМ: Web-Zip (Рывок)\nQ: Web-Strike (Налёт)\nE: Бросок предмета паутиной\nСтена + W: Карабкание (A/D = экран)"
	hints.add_theme_font_size_override("font_size", 13)
	hints.modulate = Color(0.85, 0.9, 1.0, 0.85)
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hints)

func _update_hud_reticle() -> void:
	if not hud_reticle_label or not camera:
		return

	if hud_hp_bar: hud_hp_bar.value = health
	if hud_web_bar: hud_web_bar.value = web_meter

	if hud_state_label:
		match state:
			State.SWINGING: hud_state_label.text = "🕸️ ПОЛЁТ НА ПАУТИНЕ (W: Раскачка)"
			State.ZIPPING: hud_state_label.text = "⚡ WEB-ZIP"
			State.WALL_RUNNING: hud_state_label.text = "🧗 КАРАБКАНИЕ"
			State.WEB_STRIKING: hud_state_label.text = "💥 WEB-STRIKE"
			State.THROWING: hud_state_label.text = "🌀 БРОСОК ПАУТИНОЙ"
			State.COCOONED: hud_state_label.text = "🕸️ В КОКОНЕ! (Жми Пробел/ЛКМ)"
			_: hud_state_label.text = ""

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
