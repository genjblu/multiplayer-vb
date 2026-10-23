class_name CombatCar
extends VehicleBody3D

const SoundFX = preload("res://scripts/sound_effects.gd")

signal health_changed(new_hp: int, max_hp: int)
signal destroyed(attacker_id: int)
signal nitro_changed(current: float, maximum: float)

@export var max_health: int = 400
@export var health: int = 400
@export var max_engine_force: float = 2200.0
@export var max_brake_force: float = 85.0
@export var max_steer_angle: float = 0.38
@export var nitro_thrust: float = 3200.0
@export var max_nitro: float = 100.0
@export var nitro_burn_rate: float = 28.0
@export var nitro_regen_rate: float = 14.0

var team_id: int = 0
var car_color: Color = Color(1.0, 0.55, 0.1)
var driver_peer_id: int = 0
var passengers: Array[int] = [0, 0, 0, 0] # 0 = свободно, иначе peer_id. [0]=водитель, [1..3]=пассажиры

var nitro_fuel: float = 100.0
var current_throttle: float = 0.0
var is_nitro_active: bool = false
var is_destroyed: bool = false

# Сетевая синхронизация
var sync_pos: Vector3 = Vector3.ZERO
var sync_rot: Vector3 = Vector3.ZERO
var sync_lin_vel: Vector3 = Vector3.ZERO
var sync_steer: float = 0.0
var sync_engine: float = 0.0
var sync_brake: float = 0.0

# Ввод
var input_steer: float = 0.0
var input_throttle: float = 0.0
var input_brake: float = 0.0
var input_handbrake: bool = false
var touch_steering: float = 0.0 # для мобильного руля (-1.0..1.0)
var touch_gas: float = 0.0
var touch_brake: float = 0.0
var touch_fire_active: bool = false
var touch_nitro: bool = false

# Оружие водителя (автопушки)
var cannon_cooldown: float = 0.12
var next_cannon_fire_time: float = 0.0
var cannon_side_toggle: bool = false

# Камера
var camera_mode: int = 0 # 0 = Chase, 1 = Cockpit
var cam_rot_h: float = 0.0
var cam_rot_v: float = 0.0

# Узлы
@onready var wheel_fl: VehicleWheel3D = $Wheel_FL
@onready var wheel_fr: VehicleWheel3D = $Wheel_FR
@onready var wheel_rl: VehicleWheel3D = $Wheel_RL
@onready var wheel_rr: VehicleWheel3D = $Wheel_RR

@onready var chase_pivot: Node3D = $ChasePivot
@onready var chase_cam: Camera3D = $ChasePivot/SpringArm3D/ChaseCamera
@onready var cockpit_cam: Camera3D = $CockpitCamera
@onready var interior_wheel: Node3D = get_node_or_null("CockpitInterior/SteeringColumn/SteeringWheelPivot")
@onready var cockpit_interior: Node3D = get_node_or_null("CockpitInterior")
@onready var speedo_pivot: Node3D = get_node_or_null("CockpitInterior/SpeedoPivot")
@onready var tacho_pivot: Node3D = get_node_or_null("CockpitInterior/TachoPivot")
@onready var gps_phone_body: Node3D = get_node_or_null("CockpitInterior/GPSPhoneBody")
@onready var gps_phone_screen: MeshInstance3D = get_node_or_null("CockpitInterior/GPSPhoneBody/GPSPhoneScreen")

var gps_viewport: SubViewport = null
var gps_speed_label: Label = null
var gps_arrow_label: Label = null
var gps_status_label: Label = null
var gps_substatus_label: Label = null
var gps_hp_bar: ProgressBar = null
var gps_nitro_bar: ProgressBar = null
var gps_panel_bg: StyleBoxFlat = null

@onready var engine_sound: AudioStreamPlayer3D = $Audio/EngineSound
@onready var crash_sound: AudioStreamPlayer3D = $Audio/CrashSound
@onready var skid_sound: AudioStreamPlayer3D = $Audio/SkidSound
@onready var nitro_sound: AudioStreamPlayer3D = $Audio/NitroSound
@onready var cannon_sound: AudioStreamPlayer3D = $Audio/CannonSound

@onready var smoke_particles: CPUParticles3D = $FX/SmokeParticles
@onready var fire_particles: CPUParticles3D = $FX/FireParticles
@onready var nitro_left: CPUParticles3D = $FX/NitroLeft
@onready var nitro_right: CPUParticles3D = $FX/NitroRight
@onready var flash_left: Node3D = $FX/FlashLeft
@onready var flash_right: Node3D = $FX/FlashRight

@onready var seat_nodes: Array[Node3D] = [
	$Seats/Seat_0,
	$Seats/Seat_1,
	$Seats/Seat_2,
	$Seats/Seat_3
]

@onready var body_mesh: MeshInstance3D = $BodyMesh/Chassis

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_body_entered)

	# Настройка звуков из генератора SoundEffects
	if SoundFX:
		if engine_sound:
			engine_sound.stream = SoundFX.get_car_engine_loop()
			engine_sound.play()
		if crash_sound:
			crash_sound.stream = SoundFX.get_car_crash()
		if skid_sound:
			skid_sound.stream = SoundFX.get_car_skid()
		if nitro_sound:
			nitro_sound.stream = SoundFX.get_car_boost()
		if cannon_sound:
			cannon_sound.stream = SoundFX.get_car_cannon()

	sync_pos = global_position
	sync_rot = rotation

	# Проверяем цвет команды
	_update_car_color()

	# Инициализация экрана смартфона на торпеде
	_setup_gps_screen()

func _process(delta: float) -> void:
	if not is_destroyed:
		_update_gauges(delta)
		_update_gps_screen(delta)

func _update_car_color() -> void:
	if not is_instance_valid(body_mesh):
		return
	var mat = body_mesh.get_surface_override_material(0)
	if mat == null:
		mat = StandardMaterial3D.new()
		body_mesh.set_surface_override_material(0, mat)
	if mat is StandardMaterial3D:
		mat.albedo_color = car_color
		mat.metallic = 0.5
		mat.roughness = 0.4

func is_local_driver() -> bool:
	if not is_inside_tree() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return driver_peer_id <= 1
	return driver_peer_id == multiplayer.get_unique_id()

func is_local_passenger() -> bool:
	if not is_inside_tree() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	var my_id := multiplayer.get_unique_id()
	for i in range(1, 4):
		if passengers[i] == my_id:
			return true
	return false

func is_in_car(peer_id: int) -> bool:
	for p in passengers:
		if p == peer_id:
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if is_destroyed or not is_local_driver():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			toggle_camera_mode()

	# Вращение свободной камеры мышью
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_rot_h -= event.relative.x * 0.003
		cam_rot_v = clampf(cam_rot_v - event.relative.y * 0.003, -0.6, 0.4)

	# Вращение камеры пальцем на экране (свайп по экрану для обзора)
	if event is InputEventScreenDrag:
		cam_rot_h -= event.relative.x * 0.004
		cam_rot_v = clampf(cam_rot_v - event.relative.y * 0.004, -0.6, 0.4)

func toggle_camera_mode() -> void:
	camera_mode = (camera_mode + 1) % 2
	if chase_cam and cockpit_cam:
		chase_cam.current = (camera_mode == 0)
		cockpit_cam.current = (camera_mode == 1)

func _physics_process(delta: float) -> void:
	if is_destroyed:
		engine_force = 0.0
		steering = 0.0
		brake = 25.0
		return

	if is_local_driver():
		_process_driver_input(delta)
		_process_nitro(delta)
		_process_weapons(delta)
		_send_network_sync()
	else:
		_apply_network_sync(delta)

	_update_fx(delta)
	_update_audio(delta)
	_update_camera(delta)

func _process_driver_input(delta: float) -> void:
	var forward := 0.0
	var steer := 0.0
	var do_brake := false
	var do_handbrake := false

	# Клавиатура
	if Input.is_action_pressed("move_forward"):
		forward += 1.0
	if Input.is_action_pressed("move_backward"):
		forward -= 1.0
	if Input.is_action_pressed("move_left"):
		steer += 1.0
	if Input.is_action_pressed("move_right"):
		steer -= 1.0
	if Input.is_action_pressed("jump"):
		do_handbrake = true

	# Мобильный ввод
	if touch_gas > 0.0:
		forward += touch_gas
	if touch_brake > 0.0:
		forward -= touch_brake
	if absf(touch_steering) > 0.01:
		steer -= touch_steering

	steer = clampf(steer, -1.0, 1.0)
	forward = clampf(forward, -1.0, 1.0)

	# Плавная акселерация (троттл) вместо резкого удара с пробуксовкой
	current_throttle = move_toward(current_throttle, forward, delta * 3.5)

	# Текущая скорость в км/ч
	var speed_kmh := linear_velocity.length() * 3.6

	# Защита от разворота на 360: динамическое ограничение угла поворота на скорости
	# На низкой скорости (< 25 км/ч) — полный угол 0.38 рад (~22 град)
	# На высокой скорости (> 110 км/ч) — угол плавно сужается до 0.08 рад (~4.5 град)
	var dynamic_max_steer := lerpf(max_steer_angle, 0.08, clampf(speed_kmh / 110.0, 0.0, 1.0))
	var target_steering: float = steer * dynamic_max_steer
	steering = lerpf(steering, target_steering, delta * 12.0)

	# Вращение руля в салоне (передаточное число 3.2)
	if interior_wheel:
		interior_wheel.rotation.z = steering * 3.2

	# Анти-спин: демпфирование избыточного рыскания при боковом скольжении на скорости
	var lateral_vel: float = transform.basis.x.dot(linear_velocity)
	if not do_handbrake and not input_handbrake and absf(lateral_vel) > 1.8 and speed_kmh > 25.0:
		angular_velocity.y = move_toward(angular_velocity.y, 0.0, delta * 4.5)

	# Скорость вдоль локальной оси Z (вперед -Z)
	var forward_speed: float = -transform.basis.z.dot(linear_velocity)

	# Плавный срез максимальной тяги на околопредельных скоростях
	var speed_ratio := clampf(absf(forward_speed) / 48.0, 0.0, 1.0)
	var dynamic_force := max_engine_force * (1.0 - speed_ratio * 0.35)

	if current_throttle > 0.05:
		if forward_speed < -1.0:
			# Тормозим при движении назад
			brake = max_brake_force * current_throttle
			engine_force = 0.0
		else:
			brake = 0.0
			engine_force = -current_throttle * dynamic_force
	elif current_throttle < -0.05:
		if forward_speed > 1.0:
			# Тормозим при движении вперед
			brake = max_brake_force * absf(current_throttle)
			engine_force = 0.0
		else:
			brake = 0.0
			engine_force = -current_throttle * (dynamic_force * 0.6)
	else:
		engine_force = 0.0
		brake = 3.5 # естественное сопротивление качению

	if do_handbrake or input_handbrake:
		brake = max_brake_force * 2.5

func _process_nitro(delta: float) -> void:
	var wants_nitro := touch_nitro
	if (InputMap.has_action("sprint") and Input.is_action_pressed("sprint")) or Input.is_key_pressed(KEY_SHIFT):
		wants_nitro = true

	if wants_nitro and nitro_fuel > 0.0 and -transform.basis.z.dot(linear_velocity) > 0.5:
		is_nitro_active = true
		nitro_fuel = maxf(0.0, nitro_fuel - nitro_burn_rate * delta)
		apply_central_force(-transform.basis.z * nitro_thrust)
	else:
		is_nitro_active = false
		nitro_fuel = minf(max_nitro, nitro_fuel + nitro_regen_rate * delta)

	nitro_changed.emit(nitro_fuel, max_nitro)

func _process_weapons(delta: float) -> void:
	var is_mobile := (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or OS.get_name() in ["Android", "iOS"]) and not (OS.get_name() in ["Windows", "Linux", "macOS"])
	var wants_fire := false
	if is_mobile:
		wants_fire = touch_fire_active
	else:
		wants_fire = Input.is_action_pressed("fire") or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)

	if not wants_fire:
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now < next_cannon_fire_time:
		return

	next_cannon_fire_time = now + cannon_cooldown
	cannon_side_toggle = not cannon_side_toggle

	_fire_autocannon(cannon_side_toggle)
	if multiplayer.has_multiplayer_peer():
		_rpc_fire_autocannon.rpc(cannon_side_toggle)

func _fire_autocannon(side_toggle: bool) -> void:
	var flash_node := flash_right if side_toggle else flash_left
	if flash_node:
		flash_node.visible = true
		var tw := flash_node.create_tween()
		tw.tween_interval(0.05)
		tw.tween_callback(func():
			if is_instance_valid(flash_node):
				flash_node.visible = false
		)

	if cannon_sound:
		if cannon_sound.stream == null:
			cannon_sound.stream = SoundFX.get_car_cannon()
		cannon_sound.pitch_scale = randf_range(0.94, 1.06)
		cannon_sound.play()

	var space := get_world_3d().direct_space_state
	var muzzle_pos := (flash_node.global_position if flash_node else global_position)

	# Направление выстрела: в точку, куда смотрит камера/прицел
	var aim_target: Vector3
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam and is_local_driver():
		var cam_forward := -cam.global_transform.basis.z
		var cam_ray_end := cam.global_position + cam_forward * 160.0
		var cam_query := PhysicsRayQueryParameters3D.create(cam.global_position, cam_ray_end)
		var cam_excludes: Array[RID] = [self.get_rid()]
		for c in find_children("*", "CollisionObject3D", true, false):
			if c is CollisionObject3D:
				cam_excludes.append(c.get_rid())
		cam_query.exclude = cam_excludes
		var cam_res := space.intersect_ray(cam_query)
		aim_target = cam_res.position if cam_res else cam_ray_end
	else:
		aim_target = muzzle_pos - global_transform.basis.z * 120.0

	var shot_dir := (aim_target - muzzle_pos).normalized()
	var ray_end := muzzle_pos + shot_dir * 140.0

	var query := PhysicsRayQueryParameters3D.create(muzzle_pos, ray_end)
	var excludes: Array[RID] = [self.get_rid()]
	for c in find_children("*", "CollisionObject3D", true, false):
		if c is CollisionObject3D:
			excludes.append(c.get_rid())
	for p_node in get_tree().get_nodes_in_group("players"):
		if is_ancestor_of(p_node) and (p_node is CollisionObject3D):
			excludes.append(p_node.get_rid())
	query.exclude = excludes

	var result := space.intersect_ray(query)
	var impact_pos: Vector3 = ray_end
	if not result.is_empty():
		impact_pos = result.position

	# 1. Трассер пули
	_spawn_bullet_tracer(muzzle_pos, impact_pos)

	# 2. Обработка попадания и урона
	if result:
		var collider = result.collider
		var hit_norm: Vector3 = result.normal
		var decals = get_node_or_null("/root/BulletDecals")
		if decals:
			decals.spawn_hit(impact_pos, hit_norm)

		if collider and collider != self and not is_ancestor_of(collider) and collider.has_method("take_damage"):
			var dmg: int = 28
			var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
			if collider.has_method("destroy_car"):
				collider.take_damage(dmg, my_id, "Автопушка")
			elif collider.is_in_group("players"):
				if multiplayer.has_multiplayer_peer():
					collider.take_damage.rpc_id(collider.get_multiplayer_authority(), dmg, my_id, "Автопушка", false)
				else:
					collider.take_damage(dmg, my_id, "Автопушка", false)

func _spawn_bullet_tracer(from_pos: Vector3, to_pos: Vector3) -> void:
	var mesh_inst := MeshInstance3D.new()
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES)
	imm.surface_add_vertex(from_pos)
	imm.surface_add_vertex(to_pos)
	imm.surface_end()
	mesh_inst.mesh = imm

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.82, 0.25, 0.95)
	mesh_inst.material_override = mat

	var scene_root := get_parent() if get_parent() else self
	scene_root.add_child(mesh_inst)

	var tw := mesh_inst.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(mesh_inst.queue_free)

@rpc("unreliable")
func _rpc_fire_autocannon(side_toggle: bool) -> void:
	if not is_local_driver():
		_fire_autocannon(side_toggle)

func _send_network_sync() -> void:
	if not is_inside_tree() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	_sync_state.rpc(global_position, rotation, linear_velocity, steering, engine_force, brake, is_nitro_active)

@rpc("unreliable_ordered")
func _sync_state(pos: Vector3, rot: Vector3, lin_vel: Vector3, st: float, eng: float, brk: float, nitro: bool) -> void:
	if is_local_driver():
		return
	sync_pos = pos
	sync_rot = rot
	sync_lin_vel = lin_vel
	sync_steer = st
	sync_engine = eng
	sync_brake = brk
	is_nitro_active = nitro

func _apply_network_sync(delta: float) -> void:
	global_position = global_position.lerp(sync_pos, delta * 15.0)
	rotation.x = lerp_angle(rotation.x, sync_rot.x, delta * 15.0)
	rotation.y = lerp_angle(rotation.y, sync_rot.y, delta * 15.0)
	rotation.z = lerp_angle(rotation.z, sync_rot.z, delta * 15.0)
	linear_velocity = sync_lin_vel
	steering = sync_steer
	engine_force = sync_engine
	brake = sync_brake

func _update_fx(delta: float) -> void:
	# Дым при HP < 50%
	if smoke_particles:
		smoke_particles.emitting = (health <= max_health * 0.5 and not is_destroyed)
	# Огонь при HP < 25%
	if fire_particles:
		fire_particles.emitting = (health <= max_health * 0.25 and not is_destroyed)

	# Нитро факелы
	if nitro_left and nitro_right:
		nitro_left.emitting = is_nitro_active
		nitro_right.emitting = is_nitro_active

func _update_audio(delta: float) -> void:
	if engine_sound and engine_sound.playing:
		var spd := linear_velocity.length()
		var target_pitch: float = clampf(0.7 + (spd / 45.0) * 1.5, 0.7, 2.4)
		if is_nitro_active:
			target_pitch += 0.3
		engine_sound.pitch_scale = lerpf(engine_sound.pitch_scale, target_pitch, delta * 8.0)

	if nitro_sound:
		if is_nitro_active and not nitro_sound.playing:
			nitro_sound.play()
		elif not is_nitro_active and nitro_sound.playing:
			nitro_sound.stop()

	if skid_sound:
		# Скрип при заносе
		var lateral_vel := transform.basis.x.dot(linear_velocity)
		var is_skidding := (absf(lateral_vel) > 8.0 and linear_velocity.length() > 6.0) or (brake > 40.0 and linear_velocity.length() > 10.0)
		if is_skidding and not skid_sound.playing:
			skid_sound.play()
		elif not is_skidding and skid_sound.playing:
			skid_sound.stop()

func _update_camera(delta: float) -> void:
	if not is_local_driver() and not is_local_passenger():
		return

	if chase_pivot and chase_cam and chase_cam.current:
		# Плавная следящая камера позади машины
		var target_y := rotation.y + cam_rot_h
		chase_pivot.rotation.y = lerp_angle(chase_pivot.rotation.y, target_y, delta * 10.0)
		chase_pivot.rotation.x = lerpf(chase_pivot.rotation.x, cam_rot_v, delta * 10.0)

		# FOV эффект от скорости и нитро
		var spd := linear_velocity.length()
		var target_fov: float = 75.0 + clampf((spd / 50.0) * 20.0, 0.0, 20.0)
		if is_nitro_active:
			target_fov += 12.0
		chase_cam.fov = lerpf(chase_cam.fov, target_fov, delta * 6.0)

	elif cockpit_cam and cockpit_cam.current:
		cockpit_cam.rotation.y = lerp_angle(cockpit_cam.rotation.y, cam_rot_h, delta * 12.0)
		cockpit_cam.rotation.x = lerpf(cockpit_cam.rotation.x, -0.06 + cam_rot_v, delta * 12.0)
		var spd := linear_velocity.length()
		var target_fov: float = 80.0 + clampf((spd / 50.0) * 15.0, 0.0, 15.0)
		if is_nitro_active:
			target_fov += 8.0
		cockpit_cam.fov = lerpf(cockpit_cam.fov, target_fov, delta * 6.0)

	# Плавное возвращение взгляда в центр
	cam_rot_h = lerpf(cam_rot_h, 0.0, delta * 2.0)
	cam_rot_v = lerpf(cam_rot_v, 0.0, delta * 2.0)

func _on_body_entered(body: Node) -> void:
	if is_destroyed:
		return

	# Столкновение с другой боевой машиной (Таран!)
	if (body is VehicleBody3D) and body != self and body.has_method("destroy_car"):
		var other_car := body as VehicleBody3D
		var rel_vel: Vector3 = linear_velocity - other_car.linear_velocity
		var impact_speed: float = rel_vel.length()

		if impact_speed > 7.0:
			_play_crash_sound()
			# Проверяем, ударили ли мы передом (кенгурятником)
			var to_other: Vector3 = (other_car.global_position - global_position).normalized()
			var hit_with_front: bool = (-transform.basis.z).dot(to_other) > 0.55

			var base_dmg := int(impact_speed * 4.5)
			var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
			var other_driver_id: int = int(other_car.get("driver_peer_id"))

			if hit_with_front:
				# Удар таранным бампером: враг получает огромный урон, мы защищены!
				var dealt := int(base_dmg * 2.2)
				var received := int(base_dmg * 0.25)
				other_car.call("take_damage", dealt, my_id, "Таранный бампер")
				take_damage(received, other_driver_id, "Контрудар")
			else:
				# Боковой или задний контакт
				var dealt := int(base_dmg * 0.8)
				other_car.call("take_damage", dealt, my_id, "Таран")
				take_damage(dealt, other_driver_id, "Таран")

	elif body is StaticBody3D or body is CSGShape3D or body is GridMap:
		# Удар об ограждение или препятствие
		var spd := linear_velocity.length()
		if spd > 12.0:
			_play_crash_sound()
			var obstacle_dmg := int((spd - 10.0) * 1.5)
			take_damage(obstacle_dmg, 0, "Препятствие")

func _play_crash_sound() -> void:
	if crash_sound:
		crash_sound.pitch_scale = randf_range(0.85, 1.15)
		crash_sound.play()

func take_damage(amount: int, attacker_id: int, weapon_name: String = "", is_headshot: bool = false) -> void:
	if is_destroyed:
		return

	# Игрок и пассажиры машины никогда не наносят урон своей же машине!
	if is_in_car(attacker_id) or attacker_id == driver_peer_id:
		return

	# Если атаковал союзник и дружественный огонь выключен
	var net_manager = get_node_or_null("/root/NetworkManager")
	var is_ff: bool = bool(net_manager.get("friendly_fire")) if net_manager else false
	var my_id: int = driver_peer_id
	var stats_node = get_node_or_null("/root/GameStats")
	if not is_ff and attacker_id != 0 and attacker_id != my_id and stats_node:
		if stats_node.are_allies(attacker_id, my_id):
			return

	health = clampi(health - amount, 0, max_health)
	health_changed.emit(health, max_health)

	if health <= 0:
		destroy_car(attacker_id, weapon_name)

func destroy_car(killer_id: int = 0, weapon_name: String = "Взрыв") -> void:
	if is_destroyed:
		return
	is_destroyed = true
	health = 0
	health_changed.emit(0, max_health)

	if SoundFX and crash_sound:
		crash_sound.stream = SoundFX.get_car_explosion()
		crash_sound.play()

	# Обугливание кузова
	if is_instance_valid(body_mesh):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.1, 0.1)
		mat.roughness = 0.9
		body_mesh.set_surface_override_material(0, mat)

	# Взрывные частицы
	if fire_particles:
		fire_particles.amount = 120
		fire_particles.emitting = true
	if smoke_particles:
		smoke_particles.amount = 120
		smoke_particles.emitting = true

	# Уничтожаем всех пассажиров и водителя
	for i in range(4):
		var pid := passengers[i]
		if pid > 0:
			var arena := get_tree().current_scene
			var p_node = arena.find_child(str(pid), true, false) if arena else null
			if p_node and p_node.has_method("die"):
				if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
					var stats_srv = get_node_or_null("/root/GameStats")
					if stats_srv:
						stats_srv.report_death.rpc_id(1, killer_id, weapon_name, false)
				p_node.die()

	destroyed.emit(killer_id)

func assign_player_to_seat(peer_id: int, seat_index: int, player_node: Node3D) -> void:
	if seat_index < 0 or seat_index >= 4:
		return
	passengers[seat_index] = peer_id
	if seat_index == 0:
		driver_peer_id = peer_id
		set_multiplayer_authority(peer_id)

	if player_node:
		var seat_marker := seat_nodes[seat_index]
		player_node.reparent(seat_marker)
		# Сажаем игрока на сиденье, чтобы тело было внутри машины
		player_node.position = Vector3(0, -0.45, 0)
		player_node.set("is_in_vehicle", true)

		# Отключаем коллизии игрока внутри машины, чтобы не расталкивать кузов
		for c in player_node.find_children("*", "CollisionShape3D", true, false):
			(c as CollisionShape3D).disabled = true

		var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		var is_me := (peer_id == my_id)

		if is_me and seat_index == 0:
			# Для себя за рулем полностью скрываем модель пешего персонажа (включая виевмодель и оружие)
			player_node.visible = false
		else:
			var soldier_model = player_node.get_node_or_null("SoldierModel")
			if soldier_model:
				soldier_model.visible = true
			var head_node = player_node.get_node_or_null("Head")
			if head_node:
				head_node.visible = false

		# Водителю даем камеру машины
		if is_me:
			if seat_index == 0:
				if camera_mode == 1 and cockpit_cam:
					cockpit_cam.make_current()
				elif chase_cam:
					chase_cam.make_current()
			else:
				# Пассажир использует свою камеру с видом от первого лица из сиденья
				var p_cam = player_node.find_child("Camera3D", true, false) as Camera3D
				if p_cam:
					p_cam.make_current()

func remove_player(peer_id: int) -> void:
	for i in range(4):
		if passengers[i] == peer_id:
			passengers[i] = 0
			if i == 0:
				# Водитель вышел — если есть пассажир, делаем его водителем
				_promote_next_passenger()

func _promote_next_passenger() -> void:
	for i in range(1, 4):
		if passengers[i] > 0:
			var new_driver := passengers[i]
			passengers[i] = 0
			passengers[0] = new_driver
			driver_peer_id = new_driver
			set_multiplayer_authority(new_driver)
			return
	driver_peer_id = 0

func _setup_gps_screen() -> void:
	if not gps_phone_body or not gps_phone_screen:
		return

	gps_viewport = SubViewport.new()
	gps_viewport.size = Vector2i(240, 420)
	gps_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(gps_viewport)

	var root_ctrl := Control.new()
	root_ctrl.custom_minimum_size = Vector2(240, 420)
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gps_viewport.add_child(root_ctrl)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gps_panel_bg = StyleBoxFlat.new()
	gps_panel_bg.bg_color = Color(0.04, 0.07, 0.12, 1.0)
	gps_panel_bg.border_width_left = 5
	gps_panel_bg.border_width_top = 5
	gps_panel_bg.border_width_right = 5
	gps_panel_bg.border_width_bottom = 5
	gps_panel_bg.border_color = Color(0.12, 0.85, 0.45, 1.0)
	gps_panel_bg.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", gps_panel_bg)
	root_ctrl.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var header := Label.new()
	header.text = "GPS / НАВИГАЦИЯ"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	header.modulate = Color(0.4, 0.8, 1.0)
	vbox.add_child(header)

	gps_speed_label = Label.new()
	gps_speed_label.text = "0 KM/H"
	gps_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gps_speed_label.add_theme_font_size_override("font_size", 34)
	gps_speed_label.modulate = Color(1.0, 1.0, 1.0)
	vbox.add_child(gps_speed_label)

	vbox.add_child(HSeparator.new())

	# Навигация (Стрелка + Направление)
	var nav_box := VBoxContainer.new()
	nav_box.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(nav_box)

	gps_arrow_label = Label.new()
	gps_arrow_label.text = "⬆"
	gps_arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gps_arrow_label.add_theme_font_size_override("font_size", 68)
	gps_arrow_label.modulate = Color(0.12, 0.95, 0.45)
	nav_box.add_child(gps_arrow_label)

	gps_status_label = Label.new()
	gps_status_label.text = "КУРС ВЕРНЫЙ"
	gps_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gps_status_label.add_theme_font_size_override("font_size", 20)
	gps_status_label.modulate = Color(0.12, 0.95, 0.45)
	nav_box.add_child(gps_status_label)

	gps_substatus_label = Label.new()
	gps_substatus_label.text = "ВПЕРЕД ПО ТРАССЕ"
	gps_substatus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gps_substatus_label.add_theme_font_size_override("font_size", 14)
	gps_substatus_label.modulate = Color(0.7, 0.75, 0.85)
	nav_box.add_child(gps_substatus_label)

	vbox.add_child(HSeparator.new())

	# Статус машины (HP и Нитро)
	var hp_lbl := Label.new()
	hp_lbl.text = "🚗 СОСТОЯНИЕ АВТО:"
	hp_lbl.add_theme_font_size_override("font_size", 13)
	hp_lbl.modulate = Color(0.85, 0.85, 0.85)
	vbox.add_child(hp_lbl)

	gps_hp_bar = ProgressBar.new()
	gps_hp_bar.min_value = 0
	gps_hp_bar.max_value = max_health
	gps_hp_bar.value = health
	gps_hp_bar.custom_minimum_size = Vector2(0, 16)
	gps_hp_bar.show_percentage = true
	var sb_hp := StyleBoxFlat.new()
	sb_hp.bg_color = Color(0.15, 0.85, 0.3)
	sb_hp.set_corner_radius_all(4)
	gps_hp_bar.add_theme_stylebox_override("fill", sb_hp)
	vbox.add_child(gps_hp_bar)

	var nitro_lbl := Label.new()
	nitro_lbl.text = "⚡ ЗАКИСЬ АЗОТА:"
	nitro_lbl.add_theme_font_size_override("font_size", 13)
	nitro_lbl.modulate = Color(0.85, 0.85, 0.85)
	vbox.add_child(nitro_lbl)

	gps_nitro_bar = ProgressBar.new()
	gps_nitro_bar.min_value = 0
	gps_nitro_bar.max_value = max_nitro
	gps_nitro_bar.value = nitro_fuel
	gps_nitro_bar.custom_minimum_size = Vector2(0, 16)
	gps_nitro_bar.show_percentage = true
	var sb_nitro := StyleBoxFlat.new()
	sb_nitro.bg_color = Color(0.1, 0.75, 1.0)
	sb_nitro.set_corner_radius_all(4)
	gps_nitro_bar.add_theme_stylebox_override("fill", sb_nitro)
	vbox.add_child(gps_nitro_bar)

	# Накладываем текстуру SubViewport на экран телефона
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = gps_viewport.get_texture()
	gps_phone_screen.set_surface_override_material(0, mat)

func _update_gauges(delta: float) -> void:
	var speed_kmh := linear_velocity.length() * 3.6

	# Спидометр: 0 км/ч = 135 град (+2.356 рад), 220 км/ч = -135 град (-2.356 рад)
	if speedo_pivot:
		var speed_frac := clampf(speed_kmh / 220.0, 0.0, 1.0)
		var target_speed_rad := lerpf(deg_to_rad(135.0), deg_to_rad(-135.0), speed_frac)
		speedo_pivot.rotation.z = lerp_angle(speedo_pivot.rotation.z, target_speed_rad, delta * 12.0)

	# Тахометр (обороты двигателя)
	if tacho_pivot:
		var engine_rpm := 900.0
		if absf(engine_force) > 10.0 or is_nitro_active:
			var gear_speed := fmod(speed_kmh, 45.0)
			var gear_rpm := (gear_speed / 45.0) * 5500.0
			engine_rpm = clampf(1200.0 + gear_rpm + (1200.0 if is_nitro_active else 0.0), 900.0, 7500.0)
		else:
			engine_rpm = lerpf(900.0, 2400.0, clampf(speed_kmh / 140.0, 0.0, 1.0))
		var rpm_frac := clampf((engine_rpm - 900.0) / 6600.0, 0.0, 1.0)
		var target_tacho_rad := lerpf(deg_to_rad(135.0), deg_to_rad(-135.0), rpm_frac)
		tacho_pivot.rotation.z = lerp_angle(tacho_pivot.rotation.z, target_tacho_rad, delta * 14.0)

func _update_gps_screen(delta: float) -> void:
	if not is_instance_valid(gps_viewport) or not gps_speed_label:
		return

	var speed_kmh := linear_velocity.length() * 3.6
	gps_speed_label.text = "%d KM/H" % int(speed_kmh)

	if gps_hp_bar:
		gps_hp_bar.value = health
	if gps_nitro_bar:
		gps_nitro_bar.value = nitro_fuel

	# Курс по отношению к трассе (трасса идет вдоль -Z в мировых координатах)
	var car_fwd := -global_transform.basis.z
	var highway_dir := Vector3(0, 0, -1)
	var forward_dot := car_fwd.dot(highway_dir)
	var cross_y := car_fwd.cross(highway_dir).y

	if forward_dot > 0.6:
		gps_arrow_label.text = "⬆"
		gps_status_label.text = "КУРС ВЕРНЫЙ"
		gps_substatus_label.text = "ВПЕРЕД ПО ТРАССЕ"
		var ok_col := Color(0.12, 0.95, 0.45)
		gps_arrow_label.modulate = ok_col
		gps_status_label.modulate = ok_col
		if gps_panel_bg: gps_panel_bg.border_color = ok_col
	elif forward_dot < -0.25:
		gps_arrow_label.text = "↺"
		gps_status_label.text = "РАЗВОРОТ!"
		gps_substatus_label.text = "ВЫ ЕДЕТЕ НАЗАД!"
		var warn_col := Color(1.0, 0.15, 0.15) if fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0 else Color(1.0, 0.6, 0.1)
		gps_arrow_label.modulate = warn_col
		gps_status_label.modulate = warn_col
		if gps_panel_bg: gps_panel_bg.border_color = warn_col
	elif cross_y > 0.2:
		gps_arrow_label.text = "➡"
		gps_status_label.text = "ДОВОРОТ ВПРАВО"
		gps_substatus_label.text = "ВЫРАВНЯЙТЕ КУРС"
		var steer_col := Color(1.0, 0.85, 0.1)
		gps_arrow_label.modulate = steer_col
		gps_status_label.modulate = steer_col
		if gps_panel_bg: gps_panel_bg.border_color = steer_col
	else:
		gps_arrow_label.text = "⬅"
		gps_status_label.text = "ДОВОРОТ ВЛЕВО"
		gps_substatus_label.text = "ВЫРАВНЯЙТЕ КУРС"
		var steer_col := Color(1.0, 0.85, 0.1)
		gps_arrow_label.modulate = steer_col
		gps_status_label.modulate = steer_col
		if gps_panel_bg: gps_panel_bg.border_color = steer_col
