class_name ScreenMain
extends MenuScreen

signal training_requested

var nick_edit: LineEdit
var root_buttons: VBoxContainer
var play_buttons: VBoxContainer

func _ready() -> void:
	var is_mob := OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

	# Поле никнейма
	nick_edit = LineEdit.new()
	nick_edit.placeholder_text = tr("MENU_NICK_PLACEHOLDER")
	nick_edit.max_length = 16
	nick_edit.custom_minimum_size = Vector2(0, 42 if is_mob else 46)
	if GameStats and not GameStats.local_nick.is_empty():
		nick_edit.text = GameStats.local_nick
	nick_edit.text_changed.connect(func(new_text):
		if GameStats:
			GameStats.set_nick(new_text)
	)
	add_child(_make_row(tr("MENU_NICK"), nick_edit))

	var sep := HSeparator.new()
	add_child(sep)

	# --- 1. Основное меню (Главный уровень) ---
	root_buttons = VBoxContainer.new()
	root_buttons.add_theme_constant_override("separation", 10 if is_mob else 14)
	add_child(root_buttons)

	var b_play := _make_button(tr("MENU_PLAY"), true)
	b_play.custom_minimum_size = Vector2(0, 46 if is_mob else 54)
	b_play.pressed.connect(_show_play_suboptions)
	root_buttons.add_child(b_play)

	var b_settings := _make_button(tr("MENU_SETTINGS"))
	b_settings.name = "SettingsButton"
	b_settings.custom_minimum_size = Vector2(0, 42 if is_mob else 48)
	b_settings.pressed.connect(func(): navigate.emit("settings"))
	root_buttons.add_child(b_settings)

	if not OS.has_feature("web"):
		var b_quit := _make_button(tr("MENU_QUIT"))
		b_quit.custom_minimum_size = Vector2(0, 42 if is_mob else 48)
		b_quit.pressed.connect(func(): get_tree().quit())
		root_buttons.add_child(b_quit)

	# --- 2. Меню игры (Подпункты кнопки "Играть") ---
	play_buttons = VBoxContainer.new()
	play_buttons.add_theme_constant_override("separation", 8 if is_mob else 12)
	play_buttons.visible = false
	add_child(play_buttons)

	var b_host := _make_button(tr("MENU_HOST"), true)
	b_host.custom_minimum_size = Vector2(0, 42 if is_mob else 48)
	b_host.pressed.connect(func(): navigate.emit("host"))
	play_buttons.add_child(b_host)

	var b_lan := _make_button(tr("MENU_LAN"))
	b_lan.custom_minimum_size = Vector2(0, 42 if is_mob else 48)
	b_lan.pressed.connect(func(): navigate.emit("lan"))
	play_buttons.add_child(b_lan)

	var b_join := _make_button(tr("MENU_JOIN"))
	b_join.custom_minimum_size = Vector2(0, 42 if is_mob else 48)
	b_join.pressed.connect(func(): navigate.emit("join"))
	play_buttons.add_child(b_join)

	var b_training := _make_button(tr("MENU_TRAINING"))
	b_training.custom_minimum_size = Vector2(0, 42 if is_mob else 48)
	b_training.pressed.connect(func(): training_requested.emit())
	play_buttons.add_child(b_training)

	var b_back_main := _make_button(tr("MENU_BACK_MAIN"))
	b_back_main.custom_minimum_size = Vector2(0, 38 if is_mob else 44)
	b_back_main.pressed.connect(_show_root_buttons)
	play_buttons.add_child(b_back_main)

func _show_play_suboptions() -> void:
	root_buttons.visible = false
	play_buttons.visible = true

func _show_root_buttons() -> void:
	play_buttons.visible = false
	root_buttons.visible = true

func on_shown() -> void:
	_show_root_buttons()
	if nick_edit and GameStats and not GameStats.local_nick.is_empty():
		nick_edit.text = GameStats.local_nick

func get_nick() -> String:
	return nick_edit.text if nick_edit else ""
