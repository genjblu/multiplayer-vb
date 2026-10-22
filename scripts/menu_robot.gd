class_name MenuRobot
extends CharacterBody3D

@export var bot_name: String = "Robot"
@export var team_color: Color = Color(1.0, 0.55, 0.1)
@export var team_id: int = 0

var soldier_model: SoldierModel = null
var health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false
var respawn_timer: float = 0.0

var all_bots: Array[MenuRobot] = []
var waypoints: Array[Vector3] = []
var current_dest: Vector3 = Vector3.ZERO
var move_speed: float = 4.5
var shoot_timer: float = 0.0
var burst_left: int = 0
var burst_interval: float = 0.0

var gun_root: Node3D = null
var muzzle_point: Node3D = null
var muzzle_light: OmniLight3D = null

enum State { PATROL, COMBAT, DEAD }
var state: State = State.PATROL
var target_enemy: MenuRobot = null
var combat_strafe_dir: float = 1.0
var combat_timer: float = 0.0

func _ready() -> void:
	_build_collision()
	_build_soldier()
	_build_weapon()
	_pick_random_destination()

func _build_collision() -> void:
	var col_shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.8
	col_shape.shape = cap
	col_shape.position = Vector3(0, 0.9, 0)
	add_child(col_shape)

func _build_soldier() -> void:
	var soldier_scene := load("res://scenes/characters/soldier_model.tscn") as PackedScene
	if soldier_scene:
		soldier_model = soldier_scene.instantiate() as SoldierModel
		soldier_model.name = "SoldierModel"
		add_child(soldier_model)
		soldier_model.set_team_color(team_color)

func _build_weapon() -> void:
	# Находим правую руку бойца
	var hand_node: Node3D = null
	if soldier_model:
		hand_node = soldier_model.get_node_or_null("Pelvis/Torso/ArmR/ForearmR") as Node3D

	gun_root = Node3D.new()
	gun_root.name = "Weapon"
	gun_root.position = Vector3(0.04, -0.22, -0.15)
	gun_root.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(90.0), 0)

	# Стилизованная low-poly винтовка
	var body_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.12, 0.07)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.16, 0.18)
	mat.metallic = 0.7
	mat.roughness = 0.4
	body_mesh.mesh = box
	body_mesh.material_override = mat
	body_mesh.position = Vector3(0.12, 0, 0)
	gun_root.add_child(body_mesh)

	# Ствол
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = 0.25
	barrel.mesh = cyl
	barrel.rotation.z = deg_to_rad(90)
	barrel.position = Vector3(0.48, 0.02, 0)
	gun_root.add_child(barrel)

	# Точка дула
	muzzle_point = Node3D.new()
	muzzle_point.position = Vector3(0.62, 0.02, 0)
	gun_root.add_child(muzzle_point)

	# Вспышка выстрела
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.85, 0.4)
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 4.0
	muzzle_point.add_child(muzzle_light)

	if hand_node:
		hand_node.add_child(gun_root)
	else:
		add_child(gun_root)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 18.0 * delta

	match state:
		State.DEAD:
			_process_dead(delta)
		State.COMBAT:
			_process_combat(delta)
		State.PATROL:
			_process_patrol(delta)

	move_and_slide()

func _process_patrol(delta: float) -> void:
	# Ищем ближайшего живого врага
	target_enemy = _find_nearest_enemy()
	if target_enemy and is_instance_valid(target_enemy):
		var dist := global_position.distance_to(target_enemy.global_position)
		if dist < 22.0:
			state = State.COMBAT
			combat_timer = randf_range(3.0, 6.0)
			combat_strafe_dir = 1.0 if randf() > 0.5 else -1.0
			return

	# Перемещение к текущей точке патруля
	var diff := current_dest - global_position
	diff.y = 0.0
	var dist_dest := diff.length()

	if dist_dest < 1.2:
		_pick_random_destination()
		return

	var move_dir := diff.normalized()
	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed

	# Плавный поворот в сторону движения
	var target_yaw := atan2(-move_dir.x, -move_dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * 8.0)

	if soldier_model:
		soldier_model.update_animation(delta, move_speed, is_on_floor(), false, false, false, 0.0)

func _process_combat(delta: float) -> void:
	combat_timer -= delta
	if not target_enemy or not is_instance_valid(target_enemy) or target_enemy.is_dead or combat_timer <= 0.0:
		state = State.PATROL
		_pick_random_destination()
		return

	var to_enemy := target_enemy.global_position - global_position
	var dist := to_enemy.length()
	var enemy_flat := Vector3(to_enemy.x, 0.0, to_enemy.z)

	if enemy_flat.length() > 0.1:
		var target_yaw := atan2(-enemy_flat.x, -enemy_flat.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 10.0)

	# Боковое тактическое перемещение (стрейф)
	var right_dir := transform.basis.x * combat_strafe_dir
	if dist > 14.0:
		# Сближение
		velocity.x = (enemy_flat.normalized().x * 2.0 + right_dir.x * 1.5)
		velocity.z = (enemy_flat.normalized().z * 2.0 + right_dir.z * 1.5)
	elif dist < 5.0:
		# Отход назад
		velocity.x = (-enemy_flat.normalized().x * 2.0 + right_dir.x * 1.5)
		velocity.z = (-enemy_flat.normalized().z * 2.0 + right_dir.z * 1.5)
	else:
		velocity.x = right_dir.x * 2.2
		velocity.z = right_dir.z * 2.2

	var pitch := -asin(clampf(to_enemy.normalized().y, -0.85, 0.85))
	if soldier_model:
		soldier_model.update_animation(delta, velocity.length(), is_on_floor(), false, false, false, pitch)

	# Стрельба очередями
	shoot_timer -= delta
	if burst_left > 0:
		burst_interval -= delta
		if burst_interval <= 0.0:
			burst_left -= 1
			burst_interval = 0.11
			_fire_shot_at(target_enemy)
	elif shoot_timer <= 0.0:
		burst_left = randi_range(2, 4)
		burst_interval = 0.0
		shoot_timer = randf_range(1.0, 2.2)

func _fire_shot_at(enemy: MenuRobot) -> void:
	if not is_instance_valid(enemy) or enemy.is_dead:
		return

	# Вспышка дула
	if muzzle_light:
		muzzle_light.light_energy = 2.5
		var tw := create_tween()
		tw.tween_property(muzzle_light, "light_energy", 0.0, 0.07)

	var start_pos: Vector3 = muzzle_point.global_position if muzzle_point else global_position + Vector3(0, 1.4, 0)
	var end_pos: Vector3 = enemy.global_position + Vector3(0, 1.2, 0)
	# Небольшой разброс
	end_pos += Vector3(randf_range(-0.35, 0.35), randf_range(-0.25, 0.25), randf_range(-0.35, 0.35))

	_spawn_tracer(start_pos, end_pos)

	# Урон цели
	if randf() > 0.25:
		enemy.take_hit(randf_range(25.0, 38.0), self)

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var mesh_inst := MeshInstance3D.new()
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES)
	imm.surface_add_vertex(from)
	imm.surface_add_vertex(to)
	imm.surface_end()
	mesh_inst.mesh = imm

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.4, 0.9)
	mesh_inst.material_override = mat

	get_parent().add_child(mesh_inst)

	var tw := mesh_inst.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(mesh_inst.queue_free)

func take_hit(amount: float, attacker: MenuRobot) -> void:
	if is_dead:
		return
	health -= amount

	# Вспышка попадания
	if soldier_model:
		soldier_model.set_team_color(Color.WHITE)
		var tw := soldier_model.create_tween()
		tw.tween_interval(0.08)
		tw.tween_callback(func():
			if is_instance_valid(soldier_model):
				soldier_model.set_team_color(team_color)
		)

	if health <= 0:
		die()

func die() -> void:
	is_dead = true
	state = State.DEAD
	respawn_timer = randf_range(2.0, 3.5)
	velocity = Vector3.ZERO

	# Анимация падения
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", deg_to_rad(-80.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "position:y", position.y - 0.5, 0.35)

func _process_dead(delta: float) -> void:
	respawn_timer -= delta
	if respawn_timer <= 0.0:
		respawn()

func respawn() -> void:
	is_dead = false
	health = max_health
	rotation.x = 0.0
	rotation.z = 0.0
	state = State.PATROL

	# Выбираем случайную стартовую точку
	if waypoints.size() > 0:
		global_position = waypoints.pick_random() + Vector3(0, 0.8, 0)
	velocity = Vector3.ZERO
	_pick_random_destination()

	if soldier_model:
		soldier_model.set_team_color(team_color)

func _pick_random_destination() -> void:
	if waypoints.size() > 0:
		current_dest = waypoints.pick_random()
	else:
		current_dest = Vector3(randf_range(-10, 10), 1.0, randf_range(-10, 10))

func _find_nearest_enemy() -> MenuRobot:
	var best_dist: float = 9999.0
	var best_enemy: MenuRobot = null
	for bot in all_bots:
		if bot != self and is_instance_valid(bot) and not bot.is_dead and bot.team_id != team_id:
			var d := global_position.distance_to(bot.global_position)
			if d < best_dist:
				best_dist = d
				best_enemy = bot
	return best_enemy
