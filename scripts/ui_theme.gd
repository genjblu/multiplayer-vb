class_name UITheme
extends RefCounted

const BG_COLOR := Color("121418")
const PANEL_COLOR := Color("1b1e24")
const FIELD_COLOR := Color("0f1115")
const BORDER_COLOR := Color("2c313a")
const TEXT_COLOR := Color("e6e8eb")
const MUTED_COLOR := Color("8b929c")
const ACCENT_COLOR := Color("ff8a2a")
const ERROR_COLOR := Color("ff5d5d")

static func _box(color: Color, border: Color = Color.TRANSPARENT, border_width: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(border_width)
	sb.border_color = border
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

static func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

static func build() -> Theme:
	var t := Theme.new()
	var is_mob := _is_mobile()
	t.default_font_size = 15 if is_mob else 17

	# Панель-карточка
	var panel := _box(PANEL_COLOR, BORDER_COLOR, 1)
	panel.set_corner_radius_all(10)
	if is_mob:
		panel.content_margin_left = 18
		panel.content_margin_right = 18
		panel.content_margin_top = 12
		panel.content_margin_bottom = 12
	else:
		panel.content_margin_left = 26
		panel.content_margin_right = 26
		panel.content_margin_top = 20
		panel.content_margin_bottom = 20
	t.set_stylebox("panel", "PanelContainer", panel)

	# Обычные кнопки
	var btn_v_margin: int = 6 if is_mob else 8
	var btn_h_margin: int = 12 if is_mob else 16
	var btn_normal := _box(Color("252a32"))
	btn_normal.content_margin_top = btn_v_margin
	btn_normal.content_margin_bottom = btn_v_margin
	btn_normal.content_margin_left = btn_h_margin
	btn_normal.content_margin_right = btn_h_margin
	t.set_stylebox("normal", "Button", btn_normal)

	var btn_hover := _box(Color("2f3540"))
	btn_hover.content_margin_top = btn_v_margin
	btn_hover.content_margin_bottom = btn_v_margin
	btn_hover.content_margin_left = btn_h_margin
	btn_hover.content_margin_right = btn_h_margin
	t.set_stylebox("hover", "Button", btn_hover)

	var btn_pressed := _box(Color("1f232a"))
	btn_pressed.content_margin_top = btn_v_margin
	btn_pressed.content_margin_bottom = btn_v_margin
	btn_pressed.content_margin_left = btn_h_margin
	btn_pressed.content_margin_right = btn_h_margin
	t.set_stylebox("pressed", "Button", btn_pressed)

	var btn_disabled := _box(Color("1b1e24"))
	btn_disabled.content_margin_top = btn_v_margin
	btn_disabled.content_margin_bottom = btn_v_margin
	btn_disabled.content_margin_left = btn_h_margin
	btn_disabled.content_margin_right = btn_h_margin
	t.set_stylebox("disabled", "Button", btn_disabled)

	var focus := _box(Color.TRANSPARENT, ACCENT_COLOR, 2)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT_COLOR)
	t.set_color("font_hover_color", "Button", TEXT_COLOR)
	t.set_color("font_pressed_color", "Button", TEXT_COLOR)
	t.set_color("font_disabled_color", "Button", MUTED_COLOR)

	# Акцентные кнопки
	t.set_type_variation("AccentButton", "Button")
	var btn_acc_norm := _box(ACCENT_COLOR)
	btn_acc_norm.content_margin_top = btn_v_margin
	btn_acc_norm.content_margin_bottom = btn_v_margin
	btn_acc_norm.content_margin_left = btn_h_margin
	btn_acc_norm.content_margin_right = btn_h_margin
	t.set_stylebox("normal", "AccentButton", btn_acc_norm)

	var btn_acc_hov := _box(ACCENT_COLOR.lightened(0.15))
	btn_acc_hov.content_margin_top = btn_v_margin
	btn_acc_hov.content_margin_bottom = btn_v_margin
	btn_acc_hov.content_margin_left = btn_h_margin
	btn_acc_hov.content_margin_right = btn_h_margin
	t.set_stylebox("hover", "AccentButton", btn_acc_hov)

	var btn_acc_prs := _box(ACCENT_COLOR.darkened(0.15))
	btn_acc_prs.content_margin_top = btn_v_margin
	btn_acc_prs.content_margin_bottom = btn_v_margin
	btn_acc_prs.content_margin_left = btn_h_margin
	btn_acc_prs.content_margin_right = btn_h_margin
	t.set_stylebox("pressed", "AccentButton", btn_acc_prs)

	t.set_stylebox("disabled", "AccentButton", _box(Color("3a3f48")))
	t.set_color("font_color", "AccentButton", BG_COLOR)
	t.set_color("font_hover_color", "AccentButton", BG_COLOR)
	t.set_color("font_pressed_color", "AccentButton", BG_COLOR)

	# Поля ввода
	var line_edit_box := _box(FIELD_COLOR, BORDER_COLOR, 1)
	line_edit_box.content_margin_top = 6 if is_mob else 8
	line_edit_box.content_margin_bottom = 6 if is_mob else 8
	t.set_stylebox("normal", "LineEdit", line_edit_box)
	var line_edit_focus := _box(FIELD_COLOR, ACCENT_COLOR, 1)
	line_edit_focus.content_margin_top = 6 if is_mob else 8
	line_edit_focus.content_margin_bottom = 6 if is_mob else 8
	t.set_stylebox("focus", "LineEdit", line_edit_focus)
	t.set_color("font_color", "LineEdit", TEXT_COLOR)
	t.set_color("caret_color", "LineEdit", ACCENT_COLOR)
	t.set_color("font_placeholder_color", "LineEdit", MUTED_COLOR)

	# Подписи
	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", 22 if is_mob else 30)
	t.set_color("font_color", "TitleLabel", TEXT_COLOR)
	t.set_type_variation("HeadingLabel", "Label")
	t.set_font_size("font_size", "HeadingLabel", 18 if is_mob else 22)
	t.set_color("font_color", "HeadingLabel", ACCENT_COLOR)
	t.set_type_variation("HintLabel", "Label")
	t.set_font_size("font_size", "HintLabel", 12 if is_mob else 14)
	t.set_color("font_color", "HintLabel", MUTED_COLOR)

	# Разделитель
	var line := StyleBoxLine.new()
	line.color = BORDER_COLOR
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 12)

	# Вкладки (TabContainer) и списки (OptionButton) в едином стиле
	var tab_unsel := _box(FIELD_COLOR, BORDER_COLOR, 1)
	tab_unsel.content_margin_left = 14
	tab_unsel.content_margin_right = 14
	tab_unsel.content_margin_top = 8
	tab_unsel.content_margin_bottom = 8
	var tab_sel := _box(ACCENT_COLOR)
	tab_sel.content_margin_left = 14
	tab_sel.content_margin_right = 14
	tab_sel.content_margin_top = 8
	tab_sel.content_margin_bottom = 8
	var tab_panel := _box(PANEL_COLOR, BORDER_COLOR, 1)
	tab_panel.set_content_margin_all(18)
	t.set_stylebox("tab_unselected", "TabContainer", tab_unsel)
	t.set_stylebox("tab_hovered", "TabContainer", _box(Color("252a32"), BORDER_COLOR, 1))
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("panel", "TabContainer", tab_panel)
	t.set_color("font_selected_color", "TabContainer", BG_COLOR)
	t.set_color("font_unselected_color", "TabContainer", MUTED_COLOR)
	t.set_color("font_hovered_color", "TabContainer", TEXT_COLOR)

	# OptionButton и PopupMenu
	t.set_stylebox("normal", "OptionButton", _box(FIELD_COLOR, BORDER_COLOR, 1))
	t.set_stylebox("hover", "OptionButton", _box(Color("252a32"), ACCENT_COLOR, 1))
	t.set_stylebox("pressed", "OptionButton", _box(FIELD_COLOR, ACCENT_COLOR, 1))
	t.set_color("font_color", "OptionButton", TEXT_COLOR)
	t.set_stylebox("panel", "PopupMenu", _box(PANEL_COLOR, BORDER_COLOR, 1))
	t.set_stylebox("hover", "PopupMenu", _box( Color("2f3540")))
	t.set_color("font_color", "PopupMenu", TEXT_COLOR)
	t.set_color("font_hover_color", "PopupMenu", ACCENT_COLOR)

	# Слайдеры (HSlider)
	var sl_bg := _box(FIELD_COLOR, BORDER_COLOR, 1)
	sl_bg.content_margin_top = 4
	sl_bg.content_margin_bottom = 4
	var sl_fill := _box(ACCENT_COLOR)
	sl_fill.content_margin_top = 4
	sl_fill.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", sl_bg)
	t.set_stylebox("grabber_area", "HSlider", sl_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", sl_fill)

	# Стилизация CheckBox (одинаковые отступы исключают прыжки текста)
	var cb_normal := _box(Color.TRANSPARENT)
	cb_normal.content_margin_left = 8
	cb_normal.content_margin_right = 8
	cb_normal.content_margin_top = 6
	cb_normal.content_margin_bottom = 6

	var cb_hover := _box(Color("252a32"))
	cb_hover.content_margin_left = 8
	cb_hover.content_margin_right = 8
	cb_hover.content_margin_top = 6
	cb_hover.content_margin_bottom = 6

	var cb_pressed := _box(Color("1f232a"))
	cb_pressed.content_margin_left = 8
	cb_pressed.content_margin_right = 8
	cb_pressed.content_margin_top = 6
	cb_pressed.content_margin_bottom = 6

	var cb_focus := _box(Color.TRANSPARENT, ACCENT_COLOR, 1)
	cb_focus.draw_center = false
	cb_focus.content_margin_left = 8
	cb_focus.content_margin_right = 8
	cb_focus.content_margin_top = 6
	cb_focus.content_margin_bottom = 6

	t.set_stylebox("normal", "CheckBox", cb_normal)
	t.set_stylebox("hover", "CheckBox", cb_hover)
	t.set_stylebox("pressed", "CheckBox", cb_pressed)
	t.set_stylebox("hover_pressed", "CheckBox", cb_hover)
	t.set_stylebox("focus", "CheckBox", cb_focus)

	t.set_color("font_color", "CheckBox", TEXT_COLOR)
	t.set_color("font_hover_color", "CheckBox", TEXT_COLOR)
	t.set_color("font_pressed_color", "CheckBox", TEXT_COLOR)
	t.set_color("font_hover_pressed_color", "CheckBox", TEXT_COLOR)
	t.set_constant("h_separation", "CheckBox", 12)

	return t
