class_name SpiderModel
extends Node3D

@onready var pelvis: Node3D = $Pelvis
@onready var torso: Node3D = $Pelvis/Torso
@onready var head_node: Node3D = $Pelvis/Torso/Head
@onready var leg_l: Node3D = $Pelvis/LegL
@onready var shin_l: Node3D = $Pelvis/LegL/ShinL
@onready var leg_r: Node3D = $Pelvis/LegR
@onready var shin_r: Node3D = $Pelvis/LegR/ShinR
@onready var arm_l: Node3D = $Pelvis/Torso/ArmL
@onready var forearm_l: Node3D = $Pelvis/Torso/ArmL/ForearmL
@onready var arm_r: Node3D = $Pelvis/Torso/ArmR
@onready var forearm_r: Node3D = $Pelvis/Torso/ArmR/ForearmR
@onready var wrist_l: Node3D = $Pelvis/Torso/ArmL/ForearmL/WristL
@onready var wrist_r: Node3D = $Pelvis/Torso/ArmR/ForearmR/WristR
@onready var spider_sense_fx: Node3D = $SpiderSenseFX
@onready var cocoon_mesh: MeshInstance3D = $CocoonMesh

var anim_phase: float = 0.0
var punch_timer: float = 0.0
var punch_index: int = 0
var is_right_arm_swinging: bool = true

func _ready() -> void:
	if spider_sense_fx:
		spider_sense_fx.visible = false
	if cocoon_mesh:
		cocoon_mesh.visible = false

func set_spider_sense(active: bool) -> void:
	if spider_sense_fx:
		spider_sense_fx.visible = active

func set_cocooned(active: bool) -> void:
	if cocoon_mesh:
		cocoon_mesh.visible = active
	if active:
		# Скован в коконе
		if arm_l and arm_r:
			arm_l.rotation = Vector3(0, 0, deg_to_rad(15))
			arm_r.rotation = Vector3(0, 0, deg_to_rad(-15))
		if leg_l and leg_r:
			leg_l.rotation = Vector3(0, 0, deg_to_rad(-5))
			leg_r.rotation = Vector3(0, 0, deg_to_rad(5))

func play_punch(combo_idx: int) -> void:
	punch_index = combo_idx
	punch_timer = 0.24

func get_wrist_global_pos(is_right: bool = true) -> Vector3:
	var w := wrist_r if is_right else wrist_l
	if w and is_instance_valid(w):
		return w.global_position
	return global_position + Vector3.UP * 1.2 + (global_transform.basis.x * (0.35 if is_right else -0.35))

func update_animation(delta: float, velocity: Vector3, on_floor: bool, is_swinging: bool, is_zipping: bool, is_wall_climbing: bool, is_web_striking: bool, is_charging_jump: bool, aim_pitch: float) -> void:
	if cocoon_mesh and cocoon_mesh.visible:
		return

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()

	# 1. Атака / Удар паука
	if punch_timer > 0.0:
		punch_timer -= delta
		var p_frac: float = clampf(punch_timer / 0.24, 0.0, 1.0)
		var reach: float = sin((1.0 - p_frac) * PI)
		if punch_index % 2 == 1:
			# Правый хук / удар
			if arm_r: arm_r.rotation = Vector3(deg_to_rad(-70.0 * reach), deg_to_rad(-25.0 * reach), deg_to_rad(-15.0))
			if forearm_r: forearm_r.rotation = Vector3(deg_to_rad(-20.0 * reach), 0, 0)
		else:
			# Левый хук / удар
			if arm_l: arm_l.rotation = Vector3(deg_to_rad(-70.0 * reach), deg_to_rad(25.0 * reach), deg_to_rad(15.0))
			if forearm_l: forearm_l.rotation = Vector3(deg_to_rad(-20.0 * reach), 0, 0)
		return

	# 2. Полет на паутине (Web-Swinging Pose)
	if is_swinging:
		anim_phase = 0.0
		if torso:
			torso.rotation.x = lerp_angle(torso.rotation.x, deg_to_rad(-25.0), delta * 12.0)
		if is_right_arm_swinging:
			# Правая рука держит нить сверху-впереди
			if arm_r: arm_r.rotation = Vector3(deg_to_rad(-135.0), deg_to_rad(-10.0), deg_to_rad(-15.0))
			if forearm_r: forearm_r.rotation = Vector3(deg_to_rad(-10.0), 0, 0)
			# Левая рука балансирует в воздухе
			if arm_l: arm_l.rotation = Vector3(deg_to_rad(30.0), deg_to_rad(25.0), deg_to_rad(45.0))
		else:
			if arm_l: arm_l.rotation = Vector3(deg_to_rad(-135.0), deg_to_rad(10.0), deg_to_rad(15.0))
			if forearm_l: forearm_l.rotation = Vector3(deg_to_rad(-10.0), 0, 0)
			if arm_r: arm_r.rotation = Vector3(deg_to_rad(30.0), deg_to_rad(-25.0), deg_to_rad(-45.0))

		# Ноги согнуты в динамичной дуге полета
		if leg_l and leg_r:
			leg_l.rotation.x = lerp_angle(leg_l.rotation.x, deg_to_rad(45.0), delta * 10.0)
			shin_l.rotation.x = lerp_angle(shin_l.rotation.x, deg_to_rad(35.0), delta * 10.0)
			leg_r.rotation.x = lerp_angle(leg_r.rotation.x, deg_to_rad(20.0), delta * 10.0)
			shin_r.rotation.x = lerp_angle(shin_r.rotation.x, deg_to_rad(65.0), delta * 10.0)
		return

	# 3. Рывок к стене (Web-Zip)
	if is_zipping:
		if torso: torso.rotation.x = lerp_angle(torso.rotation.x, deg_to_rad(-40.0), delta * 16.0)
		# Обе руки вытянуты вперед
		if arm_l: arm_l.rotation = Vector3(deg_to_rad(-90.0), deg_to_rad(10.0), deg_to_rad(10.0))
		if arm_r: arm_r.rotation = Vector3(deg_to_rad(-90.0), deg_to_rad(-10.0), deg_to_rad(-10.0))
		if leg_l and leg_r:
			leg_l.rotation.x = deg_to_rad(40.0)
			leg_r.rotation.x = deg_to_rad(40.0)
		return

	# 4. Удар с наскока (Web-Strike)
	if is_web_striking:
		# Тело откинуто назад, обе ноги вытянуты вперед для дропкика
		if torso: torso.rotation.x = lerp_angle(torso.rotation.x, deg_to_rad(35.0), delta * 16.0)
		if arm_l: arm_l.rotation = Vector3(deg_to_rad(-80.0), deg_to_rad(25.0), deg_to_rad(30.0))
		if arm_r: arm_r.rotation = Vector3(deg_to_rad(-80.0), deg_to_rad(-25.0), deg_to_rad(-30.0))
		if leg_l and leg_r:
			leg_l.rotation.x = deg_to_rad(-80.0)
			shin_l.rotation.x = deg_to_rad(10.0)
			leg_r.rotation.x = deg_to_rad(-80.0)
			shin_r.rotation.x = deg_to_rad(10.0)
		return

	# 5. Карабкание / бег по стене (Wall-Run / Wall-Climb)
	if is_wall_climbing:
		anim_phase += delta * 18.0
		var crawl_swing: float = sin(anim_phase)
		if torso: torso.rotation.x = lerp_angle(torso.rotation.x, deg_to_rad(-55.0), delta * 14.0)
		# Паучьи конечности цепляются за поверхность
		if arm_l: arm_l.rotation = Vector3(deg_to_rad(-80.0 + crawl_swing * 25.0), deg_to_rad(35.0), deg_to_rad(20.0))
		if arm_r: arm_r.rotation = Vector3(deg_to_rad(-80.0 - crawl_swing * 25.0), deg_to_rad(-35.0), deg_to_rad(-20.0))
		if leg_l: leg_l.rotation = Vector3(deg_to_rad(-crawl_swing * 30.0), deg_to_rad(25.0), deg_to_rad(-15.0))
		if leg_r: leg_r.rotation = Vector3(deg_to_rad(crawl_swing * 30.0), deg_to_rad(-25.0), deg_to_rad(15.0))
		return

	# 6. Зарядка супер-прыжка (приседание в паучью стойку)
	if is_charging_jump:
		if pelvis: pelvis.position.y = lerpf(pelvis.position.y, 0.45, delta * 14.0)
		if torso: torso.rotation.x = lerp_angle(torso.rotation.x, deg_to_rad(30.0), delta * 14.0)
		if leg_l and leg_r:
			leg_l.rotation.x = deg_to_rad(-45.0)
			shin_l.rotation.x = deg_to_rad(90.0)
			leg_r.rotation.x = deg_to_rad(-45.0)
			shin_r.rotation.x = deg_to_rad(90.0)
		if arm_l and arm_r:
			arm_l.rotation = Vector3(deg_to_rad(15.0), deg_to_rad(25.0), deg_to_rad(35.0))
			arm_r.rotation = Vector3(deg_to_rad(15.0), deg_to_rad(-25.0), deg_to_rad(-35.0))
		return

	# 7. Обычный бег / шаг / прыжок на полу
	if pelvis: pelvis.position.y = lerpf(pelvis.position.y, 0.85, delta * 12.0)
	if torso: torso.rotation.x = lerp_angle(torso.rotation.x, aim_pitch * 0.4, delta * 12.0)

	if on_floor:
		if horizontal_speed > 0.5:
			var run_freq: float = 12.0 if horizontal_speed > 9.0 else 8.0
			anim_phase += delta * run_freq
			var swing: float = sin(anim_phase)

			# Ноги
			if leg_l:
				leg_l.rotation.x = swing * 0.7
				if shin_l: shin_l.rotation.x = maxf(0.0, -swing * 0.9)
			if leg_r:
				leg_r.rotation.x = -swing * 0.7
				if shin_r: shin_r.rotation.x = maxf(0.0, swing * 0.9)

			# Руки в такт
			if arm_l: arm_l.rotation = Vector3(-swing * 0.6, 0, deg_to_rad(10.0))
			if arm_r: arm_r.rotation = Vector3(swing * 0.6, 0, deg_to_rad(-10.0))
		else:
			# Дыхание в покое
			anim_phase += delta * 2.0
			var breathe: float = sin(anim_phase) * 0.03
			if arm_l: arm_l.rotation = Vector3(breathe, 0, deg_to_rad(12.0))
			if arm_r: arm_r.rotation = Vector3(-breathe, 0, deg_to_rad(-12.0))
			if leg_l:
				leg_l.rotation = Vector3.ZERO
				if shin_l: shin_l.rotation = Vector3.ZERO
			if leg_r:
				leg_r.rotation = Vector3.ZERO
				if shin_r: shin_r.rotation = Vector3.ZERO
	else:
		# Свободное падение в воздухе
		if leg_l: leg_l.rotation.x = lerp_angle(leg_l.rotation.x, deg_to_rad(20.0), delta * 8.0)
		if leg_r: leg_r.rotation.x = lerp_angle(leg_r.rotation.x, deg_to_rad(-15.0), delta * 8.0)
		if arm_l: arm_l.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(20.0), deg_to_rad(35.0))
		if arm_r: arm_r.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(-20.0), deg_to_rad(-35.0))
