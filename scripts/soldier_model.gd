class_name SoldierModel
extends Node3D

@onready var pelvis: Node3D = $Pelvis
@onready var torso: Node3D = $Pelvis/Torso
@onready var head_node: Node3D = $Pelvis/Torso/Head
@onready var leg_left_root: Node3D = $Pelvis/LegL
@onready var shin_left: Node3D = $Pelvis/LegL/ShinL
@onready var leg_right_root: Node3D = $Pelvis/LegR
@onready var shin_right: Node3D = $Pelvis/LegR/ShinR
@onready var arm_left_root: Node3D = $Pelvis/Torso/ArmL
@onready var forearm_left: Node3D = $Pelvis/Torso/ArmL/ForearmL
@onready var arm_right_root: Node3D = $Pelvis/Torso/ArmR
@onready var forearm_right: Node3D = $Pelvis/Torso/ArmR/ForearmR

var team_material: StandardMaterial3D = null
var walk_phase: float = 0.0
var current_crouch_blend: float = 0.0

# Режим кулачного боя
var is_fist_mode: bool = false
var is_blocking: bool = false
var punch_timer: float = 0.0
var punch_is_right: bool = false
var punch_is_heavy: bool = false

func play_punch(is_right: bool, is_heavy: bool) -> void:
	punch_is_right = is_right
	punch_is_heavy = is_heavy
	punch_timer = 0.32 if is_heavy else 0.20


func _enter_tree() -> void:
	_setup_nodes()

func _ready() -> void:
	_setup_nodes()
	if team_material == null:
		team_material = StandardMaterial3D.new()
		team_material.roughness = 0.45
		team_material.albedo_color = Color(1.0, 0.55, 0.1) # Оранжевый по умолчанию

	_apply_team_material_recursive(self)

func _setup_nodes() -> void:
	if pelvis == null: pelvis = get_node_or_null("Pelvis") as Node3D
	if torso == null and pelvis: torso = pelvis.get_node_or_null("Torso") as Node3D
	if head_node == null and torso: head_node = torso.get_node_or_null("Head") as Node3D
	if leg_left_root == null and pelvis: leg_left_root = pelvis.get_node_or_null("LegL") as Node3D
	if shin_left == null and leg_left_root: shin_left = leg_left_root.get_node_or_null("ShinL") as Node3D
	if leg_right_root == null and pelvis: leg_right_root = pelvis.get_node_or_null("LegR") as Node3D
	if shin_right == null and leg_right_root: shin_right = leg_right_root.get_node_or_null("ShinR") as Node3D
	if arm_left_root == null and torso: arm_left_root = torso.get_node_or_null("ArmL") as Node3D
	if forearm_left == null and arm_left_root: forearm_left = arm_left_root.get_node_or_null("ForearmL") as Node3D
	if arm_right_root == null and torso: arm_right_root = torso.get_node_or_null("ArmR") as Node3D
	if forearm_right == null and arm_right_root: forearm_right = arm_right_root.get_node_or_null("ForearmR") as Node3D

func set_team_color(color: Color) -> void:
	if team_material == null:
		team_material = StandardMaterial3D.new()
		team_material.roughness = 0.45
	team_material.albedo_color = color

func _apply_team_material_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var n_name: String = node.name.to_lower()
		if "team" in n_name or "vest" in n_name or "stripe" in n_name or "armband" in n_name:
			node.material_override = team_material
	for child in node.get_children():
		_apply_team_material_recursive(child)

func update_animation(delta: float, speed: float, on_floor: bool, sprinting: bool, crouching: bool, sliding: bool, aim_pitch: float = 0.0, wall_running: bool = false, wall_side: int = 0, mantling: bool = false, is_fists: bool = false, blocking: bool = false) -> void:
	_setup_nodes()

	var target_crouch: float = 1.0 if (crouching or sliding) else 0.0
	current_crouch_blend = lerpf(current_crouch_blend, target_crouch, delta * 12.0)

	# Наклон торса вверх/вниз при прицеливании
	if torso:
		torso.rotation.x = lerp_angle(torso.rotation.x, aim_pitch * 0.7, delta * 15.0)

	# Положение рук: хват оружия либо боксерская стойка / удары
	if is_fists:
		_animate_fist_arms(delta, sprinting, speed, blocking)
	else:
		_animate_weapon_arms(delta, sprinting, speed)

	# Возврат крена таза в нормальное положение
	if not wall_running and pelvis:
		pelvis.rotation.z = lerp_angle(pelvis.rotation.z, 0.0, delta * 12.0)

	# 1. Анимация карабкания на уступ (Mantle)
	if mantling:
		walk_phase = 0.0
		if pelvis:
			pelvis.position.y = lerpf(pelvis.position.y, 1.05, delta * 14.0)
			pelvis.rotation.x = lerp_angle(pelvis.rotation.x, deg_to_rad(15.0), delta * 14.0)
		if leg_left_root and leg_right_root:
			leg_left_root.rotation.x = lerp_angle(leg_left_root.rotation.x, deg_to_rad(45.0), delta * 14.0)
			leg_right_root.rotation.x = lerp_angle(leg_right_root.rotation.x, deg_to_rad(30.0), delta * 14.0)
			if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, deg_to_rad(-60.0), delta * 14.0)
			if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, deg_to_rad(-45.0), delta * 14.0)
		if arm_left_root: arm_left_root.rotation.x = lerp_angle(arm_left_root.rotation.x, deg_to_rad(105.0), delta * 14.0)
		if arm_right_root: arm_right_root.rotation.x = lerp_angle(arm_right_root.rotation.x, deg_to_rad(105.0), delta * 14.0)
		return

	# 2. Анимация бега по стене (Wall Run в стиле Titanfall)
	if wall_running:
		walk_phase += delta * 15.0
		if pelvis:
			pelvis.position.y = lerpf(pelvis.position.y, 0.95, delta * 12.0)
			# Наклон таза и тела к стене
			pelvis.rotation.z = lerp_angle(pelvis.rotation.z, deg_to_rad(-16.0 * float(wall_side)), delta * 14.0)
			pelvis.rotation.x = lerp_angle(pelvis.rotation.x, deg_to_rad(-6.0), delta * 12.0)

		var stride: float = deg_to_rad(36.0)
		var step_l: float = sin(walk_phase) * stride
		var step_r: float = -sin(walk_phase) * stride

		if leg_left_root: leg_left_root.rotation.x = step_l
		if leg_right_root: leg_right_root.rotation.x = step_r
		if shin_left: shin_left.rotation.x = -clampf(-step_l * 1.5, 0.0, deg_to_rad(50.0))
		if shin_right: shin_right.rotation.x = -clampf(-step_r * 1.5, 0.0, deg_to_rad(50.0))
		return

	# 3. Анимация подката (Slide)
	if sliding:
		if pelvis:
			pelvis.position.y = lerpf(pelvis.position.y, 0.42, delta * 14.0)
			pelvis.rotation.x = lerp_angle(pelvis.rotation.x, deg_to_rad(-28.0), delta * 14.0)
		if leg_left_root and leg_right_root:
			# Ноги вытягиваются вперед (положительный угол вокруг X)
			leg_left_root.rotation.x = lerp_angle(leg_left_root.rotation.x, deg_to_rad(65.0), delta * 14.0)
			leg_right_root.rotation.x = lerp_angle(leg_right_root.rotation.x, deg_to_rad(45.0), delta * 14.0)
			# Колени слегка согнуты назад (отрицательный угол вокруг X)
			if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, deg_to_rad(-20.0), delta * 14.0)
			if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, deg_to_rad(-35.0), delta * 14.0)
		return

	# 4. Анимация в воздухе (Jump / Fall)
	if not on_floor:
		walk_phase = 0.0
		if pelvis:
			pelvis.position.y = lerpf(pelvis.position.y, 0.95, delta * 10.0)
			pelvis.rotation.x = lerp_angle(pelvis.rotation.x, 0.0, delta * 10.0)
		if leg_left_root:
			# Бедро слегка вперед (+20)
			leg_left_root.rotation.x = lerp_angle(leg_left_root.rotation.x, deg_to_rad(20.0), delta * 8.0)
			leg_left_root.rotation.z = lerp_angle(leg_left_root.rotation.z, deg_to_rad(-6.0), delta * 8.0)
		if leg_right_root:
			leg_right_root.rotation.x = lerp_angle(leg_right_root.rotation.x, deg_to_rad(10.0), delta * 8.0)
			leg_right_root.rotation.z = lerp_angle(leg_right_root.rotation.z, deg_to_rad(6.0), delta * 8.0)
		# Голень согнута назад (-30)
		if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, deg_to_rad(-30.0), delta * 8.0)
		if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, deg_to_rad(-20.0), delta * 8.0)
		return

	# 3. Анимация шагов / бега / приседания на полу
	var base_pelvis_y: float = lerpf(0.95, 0.52, current_crouch_blend)

	if speed > 0.4:
		var step_freq: float = 14.0 if sprinting else (8.0 if crouching else 10.0)
		walk_phase += delta * step_freq

		var swing: float = deg_to_rad(32.0 if sprinting else (18.0 if crouching else 24.0))
		var l_ang: float = sin(walk_phase) * swing
		var r_ang: float = -sin(walk_phase) * swing

		# Подпрыгивание таза в такт шагам
		var bob: float = absf(sin(walk_phase)) * (0.04 if sprinting else 0.02)
		if pelvis:
			pelvis.position.y = base_pelvis_y + bob
			pelvis.rotation.x = lerp_angle(pelvis.rotation.x, deg_to_rad(4.0 if sprinting else 0.0), delta * 10.0)
			pelvis.rotation.y = sin(walk_phase) * deg_to_rad(3.0)

		# Вращение бедер (положительный угол = шаг вперед, отрицательный = шаг назад)
		if leg_left_root:
			leg_left_root.rotation.x = l_ang
			leg_left_root.rotation.z = 0.0
		if leg_right_root:
			leg_right_root.rotation.x = r_ang
			leg_right_root.rotation.z = 0.0

		# Анатомический изгиб колена назад при отрыве ноги назад
		# В Godot отрицательный угол вокруг X отгибает голень назад
		if shin_left:
			var knee_flex_l: float = -clampf(-l_ang * 1.6, 0.0, deg_to_rad(55.0))
			shin_left.rotation.x = knee_flex_l
		if shin_right:
			var knee_flex_r: float = -clampf(-r_ang * 1.6, 0.0, deg_to_rad(55.0))
			shin_right.rotation.x = knee_flex_r
	else:
		walk_phase = 0.0
		if pelvis:
			pelvis.position.y = lerpf(pelvis.position.y, base_pelvis_y, delta * 12.0)
			pelvis.rotation.x = lerp_angle(pelvis.rotation.x, 0.0, delta * 10.0)
			pelvis.rotation.y = lerp_angle(pelvis.rotation.y, 0.0, delta * 10.0)

		# В покое или приседе
		if crouching:
			# Бедра согнуты вперед (+50 deg), колени согнуты назад (-85 deg)
			if leg_left_root: leg_left_root.rotation.x = lerp_angle(leg_left_root.rotation.x, deg_to_rad(50.0), delta * 12.0)
			if leg_right_root: leg_right_root.rotation.x = lerp_angle(leg_right_root.rotation.x, deg_to_rad(50.0), delta * 12.0)
			if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, deg_to_rad(-85.0), delta * 12.0)
			if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, deg_to_rad(-85.0), delta * 12.0)
		else:
			if leg_left_root: leg_left_root.rotation.x = lerp_angle(leg_left_root.rotation.x, 0.0, delta * 10.0)
			if leg_right_root: leg_right_root.rotation.x = lerp_angle(leg_right_root.rotation.x, 0.0, delta * 10.0)
			if shin_left: shin_left.rotation.x = lerp_angle(shin_left.rotation.x, 0.0, delta * 10.0)
			if shin_right: shin_right.rotation.x = lerp_angle(shin_right.rotation.x, 0.0, delta * 10.0)

func _animate_weapon_arms(delta: float, sprinting: bool, speed: float) -> void:
	# Тактическая стойка удержания оружия двумя руками
	# Правая рука на рукояти/спуске
	var target_r_arm := Vector3(deg_to_rad(70.0), deg_to_rad(15.0), deg_to_rad(-25.0))
	var target_r_forearm := Vector3(deg_to_rad(20.0), deg_to_rad(20.0), deg_to_rad(-10.0))

	# Левая рука поддерживает цевье/ствол
	var target_l_arm := Vector3(deg_to_rad(65.0), deg_to_rad(-20.0), deg_to_rad(30.0))
	var target_l_forearm := Vector3(deg_to_rad(25.0), deg_to_rad(-25.0), deg_to_rad(15.0))

	if sprinting and speed > 2.0:
		# При спринте оружие слегка опускается/покачивается
		target_r_arm.x = deg_to_rad(45.0)
		target_l_arm.x = deg_to_rad(40.0)

	if arm_right_root:
		arm_right_root.rotation.x = lerp_angle(arm_right_root.rotation.x, target_r_arm.x, delta * 12.0)
		arm_right_root.rotation.y = lerp_angle(arm_right_root.rotation.y, target_r_arm.y, delta * 12.0)
		arm_right_root.rotation.z = lerp_angle(arm_right_root.rotation.z, target_r_arm.z, delta * 12.0)
	if forearm_right:
		forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, target_r_forearm.x, delta * 12.0)
		forearm_right.rotation.y = lerp_angle(forearm_right.rotation.y, target_r_forearm.y, delta * 12.0)
		forearm_right.rotation.z = lerp_angle(forearm_right.rotation.z, target_r_forearm.z, delta * 12.0)

	if arm_left_root:
		arm_left_root.rotation.x = lerp_angle(arm_left_root.rotation.x, target_l_arm.x, delta * 12.0)
		arm_left_root.rotation.y = lerp_angle(arm_left_root.rotation.y, target_l_arm.y, delta * 12.0)
		arm_left_root.rotation.z = lerp_angle(arm_left_root.rotation.z, target_l_arm.z, delta * 12.0)
	if forearm_left:
		forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, target_l_forearm.x, delta * 12.0)
		forearm_left.rotation.y = lerp_angle(forearm_left.rotation.y, target_l_forearm.y, delta * 12.0)
		forearm_left.rotation.z = lerp_angle(forearm_left.rotation.z, target_l_forearm.z, delta * 12.0)

func _animate_fist_arms(delta: float, sprinting: bool, speed: float, blocking: bool) -> void:
	if punch_timer > 0.0:
		punch_timer -= delta
		if punch_is_heavy:
			var target_r_arm := Vector3(deg_to_rad(95.0), deg_to_rad(-10.0), deg_to_rad(-15.0))
			var target_r_forearm := Vector3(deg_to_rad(10.0), deg_to_rad(5.0), deg_to_rad(0.0))
			var target_l_arm := Vector3(deg_to_rad(55.0), deg_to_rad(-30.0), deg_to_rad(30.0))
			var target_l_forearm := Vector3(deg_to_rad(70.0), deg_to_rad(15.0), deg_to_rad(-15.0))
			_lerp_arms(delta * 22.0, target_r_arm, target_r_forearm, target_l_arm, target_l_forearm)
			if torso:
				torso.rotation.y = lerp_angle(torso.rotation.y, deg_to_rad(-20.0), delta * 20.0)
		elif punch_is_right:
			var target_r_arm := Vector3(deg_to_rad(85.0), deg_to_rad(-15.0), deg_to_rad(-20.0))
			var target_r_forearm := Vector3(deg_to_rad(20.0), deg_to_rad(10.0), deg_to_rad(0.0))
			var target_l_arm := Vector3(deg_to_rad(65.0), deg_to_rad(-25.0), deg_to_rad(35.0))
			var target_l_forearm := Vector3(deg_to_rad(65.0), deg_to_rad(20.0), deg_to_rad(-15.0))
			_lerp_arms(delta * 24.0, target_r_arm, target_r_forearm, target_l_arm, target_l_forearm)
			if torso:
				torso.rotation.y = lerp_angle(torso.rotation.y, deg_to_rad(-14.0), delta * 20.0)
		else:
			var target_l_arm := Vector3(deg_to_rad(85.0), deg_to_rad(15.0), deg_to_rad(20.0))
			var target_l_forearm := Vector3(deg_to_rad(20.0), deg_to_rad(-10.0), deg_to_rad(0.0))
			var target_r_arm := Vector3(deg_to_rad(65.0), deg_to_rad(25.0), deg_to_rad(-35.0))
			var target_r_forearm := Vector3(deg_to_rad(65.0), deg_to_rad(-20.0), deg_to_rad(15.0))
			_lerp_arms(delta * 24.0, target_r_arm, target_r_forearm, target_l_arm, target_l_forearm)
			if torso:
				torso.rotation.y = lerp_angle(torso.rotation.y, deg_to_rad(14.0), delta * 20.0)
		return

	if torso:
		torso.rotation.y = lerp_angle(torso.rotation.y, 0.0, delta * 12.0)

	if blocking:
		var target_r_arm := Vector3(deg_to_rad(85.0), deg_to_rad(10.0), deg_to_rad(-35.0))
		var target_r_forearm := Vector3(deg_to_rad(80.0), deg_to_rad(25.0), deg_to_rad(-10.0))
		var target_l_arm := Vector3(deg_to_rad(85.0), deg_to_rad(-10.0), deg_to_rad(35.0))
		var target_l_forearm := Vector3(deg_to_rad(80.0), deg_to_rad(-25.0), deg_to_rad(10.0))
		_lerp_arms(delta * 14.0, target_r_arm, target_r_forearm, target_l_arm, target_l_forearm)
		return

	# Базовая стойка бокса
	var target_r_arm := Vector3(deg_to_rad(60.0), deg_to_rad(20.0), deg_to_rad(-35.0))
	var target_r_forearm := Vector3(deg_to_rad(60.0), deg_to_rad(15.0), deg_to_rad(-10.0))
	var target_l_arm := Vector3(deg_to_rad(65.0), deg_to_rad(-20.0), deg_to_rad(35.0))
	var target_l_forearm := Vector3(deg_to_rad(55.0), deg_to_rad(-15.0), deg_to_rad(10.0))

	if sprinting and speed > 2.0:
		target_r_arm.x = deg_to_rad(40.0)
		target_l_arm.x = deg_to_rad(45.0)

	_lerp_arms(delta * 12.0, target_r_arm, target_r_forearm, target_l_arm, target_l_forearm)

func _lerp_arms(speed: float, r_arm: Vector3, r_forearm: Vector3, l_arm: Vector3, l_forearm: Vector3) -> void:
	if arm_right_root:
		arm_right_root.rotation.x = lerp_angle(arm_right_root.rotation.x, r_arm.x, speed)
		arm_right_root.rotation.y = lerp_angle(arm_right_root.rotation.y, r_arm.y, speed)
		arm_right_root.rotation.z = lerp_angle(arm_right_root.rotation.z, r_arm.z, speed)
	if forearm_right:
		forearm_right.rotation.x = lerp_angle(forearm_right.rotation.x, r_forearm.x, speed)
		forearm_right.rotation.y = lerp_angle(forearm_right.rotation.y, r_forearm.y, speed)
		forearm_right.rotation.z = lerp_angle(forearm_right.rotation.z, r_forearm.z, speed)
	if arm_left_root:
		arm_left_root.rotation.x = lerp_angle(arm_left_root.rotation.x, l_arm.x, speed)
		arm_left_root.rotation.y = lerp_angle(arm_left_root.rotation.y, l_arm.y, speed)
		arm_left_root.rotation.z = lerp_angle(arm_left_root.rotation.z, l_arm.z, speed)
	if forearm_left:
		forearm_left.rotation.x = lerp_angle(forearm_left.rotation.x, l_forearm.x, speed)
		forearm_left.rotation.y = lerp_angle(forearm_left.rotation.y, l_forearm.y, speed)
		forearm_left.rotation.z = lerp_angle(forearm_left.rotation.z, l_forearm.z, speed)

var weapon_mount: Node3D = null

func get_weapon_mount() -> Node3D:
	_setup_nodes()
	if weapon_mount == null and forearm_right != null:
		weapon_mount = forearm_right.get_node_or_null("WeaponMount") as Node3D
		if weapon_mount == null:
			weapon_mount = Node3D.new()
			weapon_mount.name = "WeaponMount"
			weapon_mount.position = Vector3(0.02, -0.22, -0.05)
			weapon_mount.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			forearm_right.add_child(weapon_mount)
	return weapon_mount
