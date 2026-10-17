class_name CrosshairView
extends Control

var player: CharacterBody3D = null
var hit_amount: float = 0.0  # 0..1, насколько прицел покраснел

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if player == null or not player.has_method("get_weapon_data"):
		return
	var wd: WeaponData = player.get_weapon_data()
	if wd == null or wd.crosshair_style == WeaponData.CrosshairStyle.NONE:
		return
	if wd.crosshair_hide_in_ads and bool(player.get("is_ads")):
		return

	var center: Vector2 = size / 2.0
	var cam: Camera3D = get_viewport().get_camera_3d()
	var half_fov: float = deg_to_rad(cam.fov) / 2.0 if cam else deg_to_rad(37.5)
	var spread_deg: float = player.get_crosshair_spread_deg()
	# Переводим угол разброса в пиксели на экране
	var gap: float = tan(deg_to_rad(spread_deg)) / tan(half_fov) * (size.y / 2.0)
	gap = maxf(gap, wd.crosshair_min_gap)
	var col: Color = wd.crosshair_color.lerp(wd.crosshair_hit_color, clampf(hit_amount, 0.0, 1.0))
	var t: float = wd.crosshair_thickness
	var l: float = wd.crosshair_length

	match wd.crosshair_style:
		WeaponData.CrosshairStyle.LINES:
			draw_rect(Rect2(center.x - t / 2.0, center.y - gap - l, t, l), col)
			draw_rect(Rect2(center.x - t / 2.0, center.y + gap, t, l), col)
			draw_rect(Rect2(center.x - gap - l, center.y - t / 2.0, l, t), col)
			draw_rect(Rect2(center.x + gap, center.y - t / 2.0, l, t), col)
		WeaponData.CrosshairStyle.CIRCLE:
			draw_arc(center, gap, 0.0, TAU, 64, col, t, true)
		WeaponData.CrosshairStyle.DOT:
			draw_circle(center, wd.crosshair_dot_size, col)

	if wd.crosshair_center_dot and wd.crosshair_style != WeaponData.CrosshairStyle.DOT:
		draw_circle(center, wd.crosshair_dot_size, col)
