class_name DamageIndicatorView
extends Control

var indicators: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func add_indicator(attacker_dir_3d: Vector3, camera: Camera3D) -> void:
	if attacker_dir_3d.length_squared() < 0.001 or camera == null:
		return

	var cam_forward: Vector3 = -camera.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()

	var cam_right: Vector3 = camera.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()

	var dir_flat: Vector3 = attacker_dir_3d
	dir_flat.y = 0.0
	dir_flat = dir_flat.normalized()

	var dot_fwd: float = cam_forward.dot(dir_flat)
	var dot_right: float = cam_right.dot(dir_flat)
	# В экранных координатах 2D: X вправо (+dot_right), Y вниз (-dot_fwd, так как спереди - это верх экрана)
	var screen_angle: float = atan2(-dot_fwd, dot_right)

	indicators.append({
		"angle": screen_angle,
		"time_left": 1.2,
		"max_time": 1.2
	})
	queue_redraw()

func _process(delta: float) -> void:
	if indicators.is_empty():
		return

	var active: Array[Dictionary] = []
	for ind in indicators:
		ind["time_left"] -= delta
		if ind["time_left"] > 0.0:
			active.append(ind)
	indicators = active
	queue_redraw()

func _draw() -> void:
	if indicators.is_empty():
		return

	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.28
	var arc_half_span: float = deg_to_rad(22.0)

	for ind in indicators:
		var progress: float = clampf(ind["time_left"] / ind["max_time"], 0.0, 1.0)
		var alpha: float = ease(progress, 0.5)
		var col := Color(1.0, 0.12, 0.12, alpha * 0.85)

		var godot_angle: float = ind["angle"]
		var start_ang: float = godot_angle - arc_half_span
		var end_ang: float = godot_angle + arc_half_span

		# Рисуем изогнутую дугу индикатора попадания
		draw_arc(center, radius, start_ang, end_ang, 24, col, 5.0, true)

		# Треугольный маркер по центру дуги, указывающий внутрь к прицелу
		var mid_dir := Vector2(cos(godot_angle), sin(godot_angle))
		var tip := center + mid_dir * (radius - 8.0)
		var side_l := center + Vector2(cos(godot_angle - 0.12), sin(godot_angle - 0.12)) * (radius + 2.0)
		var side_r := center + Vector2(cos(godot_angle + 0.12), sin(godot_angle + 0.12)) * (radius + 2.0)
		draw_colored_polygon(PackedVector2Array([tip, side_l, side_r]), col)
