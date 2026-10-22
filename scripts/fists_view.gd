class_name FistsView
extends Node3D

@onready var left_holder: Node3D = $LeftArmHolder
@onready var right_holder: Node3D = $RightArmHolder
@onready var left_arm: Node3D = $LeftArmHolder/LeftArm
@onready var right_arm: Node3D = $RightArmHolder/RightArm

var team_color: Color = Color(1.0, 0.55, 0.1)
var team_material: StandardMaterial3D = null

# Базовые позиции в стойке бокса
var left_rest_pos: Vector3 = Vector3(-0.16, -0.16, -0.32)
var right_rest_pos: Vector3 = Vector3(0.16, -0.18, -0.30)
var left_rest_rot: Vector3 = Vector3(deg_to_rad(12.0), deg_to_rad(-8.0), deg_to_rad(6.0))
var right_rest_rot: Vector3 = Vector3(deg_to_rad(14.0), deg_to_rad(8.0), deg_to_rad(-6.0))

# Блок (высокая глухая защита)
var left_block_pos: Vector3 = Vector3(-0.07, -0.05, -0.22)
var right_block_pos: Vector3 = Vector3(0.07, -0.05, -0.20)
var left_block_rot: Vector3 = Vector3(deg_to_rad(25.0), deg_to_rad(-16.0), deg_to_rad(18.0))
var right_block_rot: Vector3 = Vector3(deg_to_rad(25.0), deg_to_rad(16.0), deg_to_rad(-18.0))

var is_blocking: bool = false
var is_charging: bool = false
var charge_amount: float = 0.0
var idle_time: float = 0.0

var left_tween: Tween = null
var right_tween: Tween = null

func _ready() -> void:
	_init_materials()
	_reset_pose()

func _init_materials() -> void:
	if team_material == null:
		team_material = StandardMaterial3D.new()
		team_material.albedo_color = team_color
		team_material.roughness = 0.45
		team_material.metallic = 0.1
	_apply_team_material(self)

func set_team_color(col: Color) -> void:
	team_color = col
	if team_material:
		team_material.albedo_color = col
	else:
		_init_materials()

func _apply_team_material(n: Node) -> void:
	if n is MeshInstance3D and n.name.ends_with("ArmBand"):
		n.material_override = team_material
	for c in n.get_children():
		_apply_team_material(c)

func _reset_pose() -> void:
	if left_holder:
		left_holder.position = left_rest_pos
		left_holder.rotation = left_rest_rot
	if right_holder:
		right_holder.position = right_rest_pos
		right_holder.rotation = right_rest_rot

func set_blocking(blocking: bool) -> void:
	if is_blocking == blocking:
		return
	is_blocking = blocking

	if left_tween and left_tween.is_valid(): left_tween.kill()
	if right_tween and right_tween.is_valid(): right_tween.kill()

	left_tween = create_tween().set_parallel(true)
	right_tween = create_tween().set_parallel(true)

	var target_l_pos = left_block_pos if is_blocking else left_rest_pos
	var target_l_rot = left_block_rot if is_blocking else left_rest_rot
	var target_r_pos = right_block_pos if is_blocking else right_rest_pos
	var target_r_rot = right_block_rot if is_blocking else right_rest_rot

	var dur: float = 0.15 if is_blocking else 0.2
	left_tween.tween_property(left_holder, "position", target_l_pos, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	left_tween.tween_property(left_holder, "rotation", target_l_rot, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	right_tween.tween_property(right_holder, "position", target_r_pos, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	right_tween.tween_property(right_holder, "rotation", target_r_rot, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func set_charging(charging: bool, amount: float = 0.0) -> void:
	is_charging = charging
	charge_amount = clampf(amount, 0.0, 1.0)
	if is_charging and not is_blocking:
		# Правая рука взводится назад перед нокаутирующим ударом
		var windup_pos = right_rest_pos + Vector3(0.06, -0.04, 0.12) * charge_amount
		var windup_rot = right_rest_rot + Vector3(deg_to_rad(-10.0), deg_to_rad(20.0), deg_to_rad(-15.0)) * charge_amount
		right_holder.position = right_holder.position.lerp(windup_pos, 0.25)
		right_holder.rotation = right_holder.rotation.lerp(windup_rot, 0.25)

func play_punch(is_right: bool, is_heavy: bool) -> void:
	if is_blocking:
		return

	if is_heavy:
		# ТЯЖЁЛЫЙ ЗАРЯЖЕННЫЙ ХАЙМЕЙКЕР (Правая рука)
		if right_tween and right_tween.is_valid(): right_tween.kill()
		right_tween = create_tween()

		var lunge_pos = right_rest_pos + Vector3(-0.14, 0.06, -0.42)
		var lunge_rot = right_rest_rot + Vector3(deg_to_rad(-18.0), deg_to_rad(-22.0), deg_to_rad(45.0))

		# Мощный выброс вперёд за 0.09 сек
		right_tween.tween_property(right_holder, "position", lunge_pos, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		right_tween.parallel().tween_property(right_holder, "rotation", lunge_rot, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		# Возврат в стойку
		right_tween.tween_property(right_holder, "position", right_rest_pos, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		right_tween.parallel().tween_property(right_holder, "rotation", right_rest_rot, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

		# Левая рука слегка уходит в защитный блок на время тяжёлого удара
		if left_tween and left_tween.is_valid(): left_tween.kill()
		left_tween = create_tween()
		left_tween.tween_property(left_holder, "position", left_rest_pos + Vector3(0.04, 0.02, 0.05), 0.1).set_trans(Tween.TRANS_QUAD)
		left_tween.tween_property(left_holder, "position", left_rest_pos, 0.28).set_trans(Tween.TRANS_QUAD)
	elif is_right:
		# БЫСТРЫЙ ПРАВЫЙ ХУК / ПРЯМОЙ
		if right_tween and right_tween.is_valid(): right_tween.kill()
		right_tween = create_tween()

		var punch_pos = right_rest_pos + Vector3(-0.08, 0.03, -0.28)
		var punch_rot = right_rest_rot + Vector3(deg_to_rad(-10.0), deg_to_rad(-15.0), deg_to_rad(28.0))

		right_tween.tween_property(right_holder, "position", punch_pos, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		right_tween.parallel().tween_property(right_holder, "rotation", punch_rot, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		right_tween.tween_property(right_holder, "position", right_rest_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		right_tween.parallel().tween_property(right_holder, "rotation", right_rest_rot, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		# БЫСТРЫЙ ЛЕВЫЙ ДЖЕБ
		if left_tween and left_tween.is_valid(): left_tween.kill()
		left_tween = create_tween()

		var punch_pos = left_rest_pos + Vector3(0.07, 0.03, -0.26)
		var punch_rot = left_rest_rot + Vector3(deg_to_rad(-8.0), deg_to_rad(14.0), deg_to_rad(-24.0))

		left_tween.tween_property(left_holder, "position", punch_pos, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		left_tween.parallel().tween_property(left_holder, "rotation", punch_rot, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		left_tween.tween_property(left_holder, "position", left_rest_pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		left_tween.parallel().tween_property(left_holder, "rotation", left_rest_rot, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func play_dodge_sway(dir: Vector2) -> void:
	var tw = create_tween().set_parallel(true)
	var sway_l = Vector3(dir.x * 0.05, 0.02, -dir.y * 0.04)
	var sway_r = Vector3(dir.x * 0.05, 0.02, -dir.y * 0.04)
	tw.tween_property(left_holder, "position", left_rest_pos + sway_l, 0.08).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(right_holder, "position", right_rest_pos + sway_r, 0.08).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_property(left_holder, "position", left_rest_pos, 0.18).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(right_holder, "position", right_rest_pos, 0.18).set_trans(Tween.TRANS_QUAD)

func _process(delta: float) -> void:
	idle_time += delta

	# Дрожь правого кулака при зарядке мощного удара
	if is_charging and not is_blocking:
		var jitter = Vector3(
			randf_range(-0.003, 0.003) * charge_amount,
			randf_range(-0.003, 0.003) * charge_amount,
			randf_range(-0.003, 0.003) * charge_amount
		)
		right_holder.position += jitter

	# Дыхание и покачивание в стойке бокса
	if (not left_tween or not left_tween.is_running()) and not is_blocking:
		var breath = sin(idle_time * 2.8) * 0.004
		left_holder.position.y = lerpf(left_holder.position.y, left_rest_pos.y + breath, delta * 8.0)
	if (not right_tween or not right_tween.is_running()) and not is_blocking and not is_charging:
		var breath = cos(idle_time * 2.8) * 0.004
		right_holder.position.y = lerpf(right_holder.position.y, right_rest_pos.y + breath, delta * 8.0)
