class_name WeaponWheel
extends Control

## Сигнал выбора оружия (передаёт WeaponType)
signal weapon_selected(weapon_idx: int)

var player: CharacterBody3D = null
var is_open: bool = false
var selected_index: int = -1

# Конфигурация радиального меню
const WHEEL_RADIUS: float = 175.0
const INNER_RADIUS: float = 55.0
const NUM_SLOTS: int = 4

# Оружия в порядке секторов (0 = Вверх, 1 = Вправо, 2 = Вниз, 3 = Влево)
# Соответствуют enum WeaponType: PISTOL (0), ASSAULT (1), SHOTGUN (2), SNIPER (3)
# Расположим логично по часовой стрелке сверху:
# Сверху: Автомат (1), Справа: Дробовик (2), Снизу: Снайперка (3), Слева: Пистолет (0)
const SLOT_WEAPON_MAP: Array[int] = [1, 2, 3, 0]

var slot_labels: Array[Label] = []
var slot_ammo_labels: Array[Label] = []
var hover_angle: float = -1.0
var has_mouse_moved: bool = false
var center_pos: Vector2 = Vector2.ZERO

func _init() -> void:
	name = "WeaponWheel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_PASS

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	has_mouse_moved = false
	selected_index = -1
	if player:
		# Выбираем текущее оружие как дефолтное
		var cur_w: int = int(player.current_weapon)
		selected_index = SLOT_WEAPON_MAP.find(cur_w)

	center_pos = size * 0.5
	queue_redraw()

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if selected_index >= 0 and selected_index < SLOT_WEAPON_MAP.size():
		var target_weapon: int = SLOT_WEAPON_MAP[selected_index]
		weapon_selected.emit(target_weapon)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		has_mouse_moved = true
		_update_selection_from_point(event.position)
	elif event is InputEventScreenDrag or event is InputEventScreenTouch:
		has_mouse_moved = true
		_update_selection_from_point(event.position)

func _update_selection_from_point(pt: Vector2) -> void:
	var delta_vec := pt - center_pos
	if delta_vec.length() < INNER_RADIUS * 0.5:
		return

	# Угол в радианах (-PI..PI), 0 = вправо, PI/2 = вниз
	# Сдвигаем на +PI/2, чтобы 0 был строго сверху
	var angle := delta_vec.angle() + PI * 0.5
	if angle < 0.0:
		angle += TAU

	# Сектор размером TAU / NUM_SLOTS (90 градусов)
	var sector_size := TAU / float(NUM_SLOTS)
	# Сдвиг на полсектора, чтобы нулевой сектор был симметрично центрирован наверху [-45..+45]
	var adjusted := fmod(angle + sector_size * 0.5, TAU)
	selected_index = int(floor(adjusted / sector_size)) % NUM_SLOTS
	queue_redraw()

func _draw() -> void:
	if not is_open:
		return

	center_pos = size * 0.5

	# 1. Тёмный полупрозрачный фон всей страницы для фокуса
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.55))

	var sector_size: float = TAU / float(NUM_SLOTS)
	var accent_col := UITheme.ACCENT_COLOR
	var bg_col := Color(0.12, 0.14, 0.18, 0.88)
	var bg_hover := Color(0.24, 0.28, 0.35, 0.95)
	var border_col := UITheme.BORDER_COLOR

	# Рисуем сектора
	for i in range(NUM_SLOTS):
		var w_type: int = SLOT_WEAPON_MAP[i]
		var is_selected: bool = (i == selected_index)
		var is_equipped: bool = (player != null and int(player.current_weapon) == w_type)

		# Начальный и конечный углы сектора (0 = вверх, -PI/2 в системе Godot)
		var start_rad: float = (float(i) * sector_size) - (PI * 0.5) - (sector_size * 0.5)
		var end_rad: float = start_rad + sector_size

		# Рисуем кольцевой сегмент полигоном
		var points: PackedVector2Array = []
		var seg_steps: int = 24
		# Внешняя дуга
		var r_outer: float = WHEEL_RADIUS * (1.08 if is_selected else 1.0)
		var r_inner: float = INNER_RADIUS
		for s in range(seg_steps + 1):
			var a: float = lerpf(start_rad, end_rad, float(s) / float(seg_steps))
			points.append(center_pos + Vector2(cos(a), sin(a)) * r_outer)
		# Внутренняя дуга (в обратном порядке)
		for s in range(seg_steps, -1, -1):
			var a: float = lerpf(start_rad, end_rad, float(s) / float(seg_steps))
			points.append(center_pos + Vector2(cos(a), sin(a)) * r_inner)

		var fill_col: Color = bg_hover if is_selected else bg_col
		if is_selected:
			fill_col = fill_col.lerp(accent_col, 0.25)
		draw_colored_polygon(points, fill_col)

		# Контур сектора
		var line_col: Color = accent_col if (is_selected or is_equipped) else border_col
		var line_w: float = 3.0 if is_selected else (2.0 if is_equipped else 1.2)
		draw_polyline(points, line_col, line_w)

		# Текстовые данные для сектора (Название и патроны)
		var mid_angle: float = (start_rad + end_rad) * 0.5
		var label_r: float = (r_inner + r_outer) * 0.5
		var label_pos := center_pos + Vector2(cos(mid_angle), sin(mid_angle)) * label_r

		var w_name: String = ""
		var w_ammo: String = ""
		if player and player.weapon_stats.has(w_type):
			var st: Dictionary = player.weapon_stats[w_type]
			w_name = tr(st.get("name", "Оружие"))
			if player.ammo_state.has(w_type):
				var ast: Dictionary = player.ammo_state[w_type]
				w_ammo = "%d / %d" % [ast.get("mag", 0), ast.get("reserve", 0)]
			elif w_type == int(player.current_weapon):
				w_ammo = "%d / %d" % [player.current_ammo, player.reserve_ammo]

		var font: Font = ThemeDB.fallback_font
		if font:
			var txt_size := font.get_string_size(w_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
			var title_pt := label_pos - Vector2(txt_size.x * 0.5, 2.0)
			var title_col := Color.WHITE if is_selected else (accent_col if is_equipped else UITheme.TEXT_COLOR)
			draw_string(font, title_pt, w_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, title_col)

			if w_ammo != "":
				var ammo_size := font.get_string_size(w_ammo, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
				var ammo_pt := label_pos + Vector2(-ammo_size.x * 0.5, 18.0)
				draw_string(font, ammo_pt, w_ammo, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, UITheme.MUTED_COLOR if not is_selected else Color(1, 1, 1, 0.9))

	# Центральный круг-ступица
	draw_circle(center_pos, INNER_RADIUS - 4.0, Color(0.08, 0.1, 0.13, 0.95))
	draw_arc(center_pos, INNER_RADIUS - 4.0, 0, TAU, 32, UITheme.BORDER_COLOR, 2.0)
	
	# Подсказка по центру
	var center_font: Font = ThemeDB.fallback_font
	if center_font:
		var hint := "ВЫБОР"
		var h_sz := center_font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_string(center_font, center_pos + Vector2(-h_sz.x * 0.5, h_sz.y * 0.35), hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, UITheme.MUTED_COLOR)
