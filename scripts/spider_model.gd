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
var punch_duration: float = 0.28
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
		if arm_l and arm_r:
			arm_l.rotation = Vector3(0, 0, deg_to_rad(15))
			arm_r.rotation = Vector3(0, 0, deg_to_rad(-15))
		if leg_l and leg_r:
			leg_l.rotation = Vector3(0, 0, deg_to_rad(-5))
			leg_r.rotation = Vector3(0, 0, deg_to_rad(5))

func play_punch(combo_idx: int) -> void:
	punch_index = combo_idx
	punch_duration = 0.28 if combo_idx <= 2 else 0.36
	punch_timer = punch_duration

func get_wrist_global_pos(is_right: bool = true) -> Vector3:
	var w := wrist_r if is_right else wrist_l
	if w and is_instance_valid(w):
		return w.global_position
	return global_position + Vector3.UP * 1.2 + (global_transform.basis.x * (0.35 if is_right else -0.35))

func update_animation(
	delta: float,
	velocity: Vector3,
	on_floor: bool,
	is_swinging: bool,
	is_zipping: bool,
	is_wall_climbing: bool,
	is_web_striking: bool,
	is_charging_jump: bool,
	aim_pitch: float
) -> void:
	if cocoon_mesh and cocoon_mesh.visible:
		return

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()

	# ========================================================
	# 1. 4-ХИТОВАЯ БОЕВАЯ КОМБИНАЦИЯ КОНЕЧНОСТЯМИ
	# 1: Левый прямой (Jab)
	# 2: Правый хук / кросс (Cross)
	# 3: Круговой удар ногой (Roundhouse Kick)
	# 4: Акробатический удар в кувырке (Spider Flip-Kick)
	# ========================================================
	if punch_timer > 0.0:
		punch_timer -= delta
		var p_frac: float = clampf(punch_timer / punch_duration, 0.0, 1.0)
		var reach: float = sin((1.0 - p_frac) * PI)

		match punch_index:
			1:
				# 1. Левый прямой джеб (arm_l резкий выпад вперед, разворот корпуса)
				if torso: torso.rotation = Vector3(0.0, deg_to_rad(-20.0 * reach), 0.0)
				if arm_l: arm_l.rotation = Vector3(deg_to_rad(-85.0 * reach), deg_to_rad(10.0), deg_to_rad(15.0))
				if forearm_l: forearm_l.rotation = Vector3(deg_to_rad(-15.0 * reach), 0, 0)
				if arm_r: arm_r.rotation = Vector3(deg_to_rad(10.0), deg_to_rad(-25.0), deg_to_rad(-30.0))
				if leg_l: leg_l.rotation = Vector3(deg_to_rad(15.0 * reach), 0, 0)
				if leg_r: leg_r.rotation = Vector3(deg_to_rad(-15.0 * reach), 0, 0)
			2:
				# 2. Мощный правый хук/кросс с доворотом плеча
				if torso: torso.rotation = Vector3(deg_to_rad(-10.0 * reach), deg_to_rad(30.0 * reach), 0.0)
				if arm_r: arm_r.rotation = Vector3(deg_to_rad(-80.0 * reach), deg_to_rad(-35.0 * reach), deg_to_rad(-20.0))
				if forearm_r: forearm_r.rotation = Vector3(deg_to_rad(-45.0 * reach), 0, 0)
				if arm_l: arm_l.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(20.0), deg_to_rad(25.0))
				if leg_r: leg_r.rotation = Vector3(deg_to_rad(20.0 * reach), deg_to_rad(-15.0), 0)
			3:
				# 3. Круговой удар правой ногой (Roundhouse kick)
				if torso: torso.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(-40.0 * reach), deg_to_rad(-25.0 * reach))
				if pelvis: pelvis.rotation.y = deg_to_rad(45.0 * reach)
				if leg_r: leg_r.rotation = Vector3(deg_to_rad(-70.0 * reach), deg_to_rad(-60.0 * reach), deg_to_rad(50.0 * reach))
				if shin_r: shin_r.rotation = Vector3(deg_to_rad(-20.0 * reach), 0, deg_to_rad(-30.0 * reach))
				if arm_l and arm_r:
					arm_l.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(35.0), deg_to_rad(35.0))
					arm_r.rotation = Vector3(deg_to_rad(20.0), deg_to_rad(-30.0), deg_to_rad(-40.0))
			4, _:
				# 4. Акробатический паучий flip-kick (удар снизу вверх двумя ногами с кувырком)
				if torso: torso.rotation.x = deg_to_rad(35.0 * reach)
				if pelvis: pelvis.position.y = lerpf(0.85, 1.25, reach)
				if leg_l:
					leg_l.rotation = Vector3(deg_to_rad(-95.0 * reach), deg_to_rad(10.0), 0)
					if shin_l: shin_l.rotation.x = deg_to_rad(10.0)
				if leg_r:
					leg_r.rotation = Vector3(deg_to_rad(-105.0 * reach), deg_to_rad(-10.0), 0)
					if shin_r: shin_r.rotation.x = deg_to_rad(10.0)
				if arm_l: arm_l.rotation = Vector3(deg_to_rad(45.0 * reach), deg_to_rad(25.0), deg_to_rad(35.0))
				if arm_r: arm_r.rotation = Vector3(deg_to_rad(45.0 * reach), deg_to_rad(-25.0), deg_to_rad(-35.0))
		return

	# Сброс дополнительных вращений таза после ударов
	if pelvis:
		pelvis.rotation = Vector3.ZERO

	# ========================================================
	# 2. ПОЛЁТ НА ПАУТИНЕ (Spider-Man 2 Iconic Swing Pose)
	# ========================================================
	if is_swinging:
		anim_phase = 0.0
		var vertical_vel: float = velocity.y
		# Динамический наклон тела: вперед при наборе скорости вниз, назад при подъеме вверх
		var target_pitch: float = deg_to_rad(clampf(-vertical_vel * 1.5, -35.0, 30.0))
		if torso:
			torso.rotation.x = lerp_angle(torso.rotation.x, target_pitch, delta * 10.0)
			torso.rotation.y = deg_to_rad(-12.0 if is_right_arm_swinging else 12.0)

		if is_right_arm_swinging:
			# Правая рука держит нить сверху-впереди
			if arm_r: arm_r.rotation = Vector3(deg_to_rad(-145.0), deg_to_rad(-8.0), deg_to_rad(-12.0))
			if forearm_r: forearm_r.rotation = Vector3(deg_to_rad(-12.0), 0, 0)
			# Левая рука раскинута для баланса
			if arm_l: arm_l.rotation = Vector3(deg_to_rad(35.0), deg_to_rad(30.0), deg_to_rad(50.0))
			if forearm_l: forearm_l.rotation = Vector3(deg_to_rad(10.0), 0, 0)
			# Динамичная поза ног в полете: правая нога согнута, левая вытянута
			if leg_r:
				leg_r.rotation.x = deg_to_rad(30.0)
				if shin_r: shin_r.rotation.x = deg_to_rad(70.0)
			if leg_l:
				leg_l.rotation.x = deg_to_rad(55.0)
				if shin_l: shin_l.rotation.x = deg_to_rad(25.0)
		else:
			# Левая рука держит нить
			if arm_l: arm_l.rotation = Vector3(deg_to_rad(-145.0), deg_to_rad(8.0), deg_to_rad(12.0))
			if forearm_l: forearm_l.rotation = Vector3(deg_to_rad(-12.0), 0, 0)
			if arm_r: arm_r.rotation = Vector3(deg_to_rad(35.0), deg_to_rad(-30.0), deg_to_rad(-50.0))
			if forearm_r: forearm_r.rotation = Vector3(deg_to_rad(10.0), 0, 0)
			if leg_l:
				leg_l.rotation.x = deg_to_rad(30.0)
				if shin_l: shin_l.rotation.x = deg_to_rad(70.0)
			if leg_r:
				leg_r.rotation.x = deg_to_rad(55.0)
				if shin_r: shin_r.rotation.x = deg_to_rad(25.0)
		return

	# ========================================================
	# 3. РЫВОК К СТЕНЕ (Web-Zip)
	# ========================================================
	if is_zipping:
		if torso: torso.rotation = Vector3(deg_to_rad(-45.0), 0, 0)
		if arm_l: arm_l.rotation = Vector3(deg_to_rad(-95.0), deg_to_rad(8.0), deg_to_rad(12.0))
		if arm_r: arm_r.rotation = Vector3(deg_to_rad(-95.0), deg_to_rad(-8.0), deg_to_rad(-12.0))
		if forearm_l: forearm_l.rotation = Vector3.ZERO
		if forearm_r: forearm_r.rotation = Vector3.ZERO
		if leg_l and leg_r:
			leg_l.rotation = Vector3(deg_to_rad(45.0), 0, deg_to_rad(-8.0))
			leg_r.rotation = Vector3(deg_to_rad(45.0), 0, deg_to_rad(8.0))
			if shin_l: shin_l.rotation.x = deg_to_rad(30.0)
			if shin_r: shin_r.rotation.x = deg_to_rad(30.0)
		return

	# ========================================================
	# 4. ДРОПКИК С НАЛЁТА (Web-Strike)
	# ========================================================
	if is_web_striking:
		if torso: torso.rotation = Vector3(deg_to_rad(35.0), 0, 0)
		if arm_l: arm_l.rotation = Vector3(deg_to_rad(-70.0), deg_to_rad(25.0), deg_to_rad(35.0))
		if arm_r: arm_r.rotation = Vector3(deg_to_rad(-70.0), deg_to_rad(-25.0), deg_to_rad(-35.0))
		if leg_l and leg_r:
			leg_l.rotation = Vector3(deg_to_rad(-85.0), 0, 0)
			leg_r.rotation = Vector3(deg_to_rad(-90.0), 0, 0)
			if shin_l: shin_l.rotation.x = deg_to_rad(10.0)
			if shin_r: shin_r.rotation.x = deg_to_rad(10.0)
		return

	# ========================================================
	# 5. КАРАБКАНİЕ И БЕГ ПО СТЕНАМ (Spider Wall Crawl)
	# ========================================================
	if is_wall_climbing:
		var speed_wall := velocity.length()
		var is_moving := speed_wall > 1.0

		if is_moving:
			anim_phase += delta * 16.0
			var step := sin(anim_phase)
			# Попеременная паучья походка по поверхности
			if torso: torso.rotation = Vector3(deg_to_rad(-25.0), 0, 0)
			if pelvis: pelvis.position.y = 0.65
			# Руки цепляются за стену впереди
			if arm_l: arm_l.rotation = Vector3(deg_to_rad(-75.0 + step * 25.0), deg_to_rad(35.0), deg_to_rad(25.0))
			if arm_r: arm_r.rotation = Vector3(deg_to_rad(-75.0 - step * 25.0), deg_to_rad(-35.0), deg_to_rad(-25.0))
			if forearm_l: forearm_l.rotation = Vector3(deg_to_rad(-30.0), 0, 0)
			if forearm_r: forearm_r.rotation = Vector3(deg_to_rad(-30.0), 0, 0)
			# Ноги растопырены в стороны
			if leg_l: leg_l.rotation = Vector3(deg_to_rad(25.0 - step * 30.0), deg_to_rad(45.0), deg_to_rad(-20.0))
			if leg_r: leg_r.rotation = Vector3(deg_to_rad(25.0 + step * 30.0), deg_to_rad(-45.0), deg_to_rad(20.0))
			if shin_l: shin_l.rotation.x = deg_to_rad(65.0)
			if shin_r: shin_r.rotation.x = deg_to_rad(65.0)
		else:
			# Стойка зацепа на стене (4 точки опоры, прижавшись к стене)
			if torso: torso.rotation = Vector3(deg_to_rad(-30.0), 0, 0)
			if pelvis: pelvis.position.y = 0.55
			if arm_l: arm_l.rotation = Vector3(deg_to_rad(-75.0), deg_to_rad(40.0), deg_to_rad(30.0))
			if arm_r: arm_r.rotation = Vector3(deg_to_rad(-75.0), deg_to_rad(-40.0), deg_to_rad(-30.0))
			if forearm_l: forearm_l.rotation = Vector3(deg_to_rad(-35.0), 0, 0)
			if forearm_r: forearm_r.rotation = Vector3(deg_to_rad(-35.0), 0, 0)
			if leg_l: leg_l.rotation = Vector3(deg_to_rad(35.0), deg_to_rad(50.0), deg_to_rad(-25.0))
			if leg_r: leg_r.rotation = Vector3(deg_to_rad(35.0), deg_to_rad(-50.0), deg_to_rad(25.0))
			if shin_l: shin_l.rotation.x = deg_to_rad(75.0)
			if shin_r: shin_r.rotation.x = deg_to_rad(75.0)
		return

	# ========================================================
	# 6. ЗАРЯДКА СУПЕР-ПРЫЖКА (Паучья боевая стойка)
	# ========================================================
	if is_charging_jump:
		if pelvis: pelvis.position.y = lerpf(pelvis.position.y, 0.42, delta * 14.0)
		if torso: torso.rotation.x = lerp_angle(torso.rotation.x, deg_to_rad(35.0), delta * 14.0)
		if leg_l and leg_r:
			leg_l.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(20.0), deg_to_rad(-15.0))
			shin_l.rotation.x = deg_to_rad(95.0)
			leg_r.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(-20.0), deg_to_rad(15.0))
			shin_r.rotation.x = deg_to_rad(95.0)
		if arm_l and arm_r:
			arm_l.rotation = Vector3(deg_to_rad(20.0), deg_to_rad(30.0), deg_to_rad(40.0))
			arm_r.rotation = Vector3(deg_to_rad(20.0), deg_to_rad(-30.0), deg_to_rad(-40.0))
		return

	# ========================================================
	# 7. ОБЫЧНОЕ ДВИЖЕНИЕ / БЕГ / ПОКОЙ
	# ========================================================
	if pelvis: pelvis.position.y = lerpf(pelvis.position.y, 0.85, delta * 12.0)
	if torso: torso.rotation = Vector3(aim_pitch * 0.35, 0, 0)

	if on_floor:
		if horizontal_speed > 0.5:
			var run_freq: float = 14.0 if horizontal_speed > 13.0 else 9.5
			anim_phase += delta * run_freq
			var swing: float = sin(anim_phase)

			# Ноги
			if leg_l:
				leg_l.rotation = Vector3(swing * 0.75, 0, 0)
				if shin_l: shin_l.rotation.x = maxf(0.0, -swing * 0.95)
			if leg_r:
				leg_r.rotation = Vector3(-swing * 0.75, 0, 0)
				if shin_r: shin_r.rotation.x = maxf(0.0, swing * 0.95)

			# Руки в такт
			if arm_l: arm_l.rotation = Vector3(-swing * 0.65, 0, deg_to_rad(12.0))
			if arm_r: arm_r.rotation = Vector3(swing * 0.65, 0, deg_to_rad(-12.0))
			if forearm_l: forearm_l.rotation = Vector3.ZERO
			if forearm_r: forearm_r.rotation = Vector3.ZERO
		else:
			# Дыхание в покое
			anim_phase += delta * 2.2
			var breathe: float = sin(anim_phase) * 0.04
			if arm_l: arm_l.rotation = Vector3(breathe, 0, deg_to_rad(12.0))
			if arm_r: arm_r.rotation = Vector3(-breathe, 0, deg_to_rad(-12.0))
			if forearm_l: forearm_l.rotation = Vector3.ZERO
			if forearm_r: forearm_r.rotation = Vector3.ZERO
			if leg_l:
				leg_l.rotation = Vector3.ZERO
				if shin_l: shin_l.rotation = Vector3.ZERO
			if leg_r:
				leg_r.rotation = Vector3.ZERO
				if shin_r: shin_r.rotation = Vector3.ZERO
	else:
		# Свободное падение в воздухе
		if leg_l: leg_l.rotation = Vector3(deg_to_rad(25.0), deg_to_rad(10.0), 0)
		if leg_r: leg_r.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(-10.0), 0)
		if arm_l: arm_l.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(25.0), deg_to_rad(40.0))
		if arm_r: arm_r.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(-25.0), deg_to_rad(-40.0))
		if forearm_l: forearm_l.rotation = Vector3.ZERO
		if forearm_r: forearm_r.rotation = Vector3.ZERO
