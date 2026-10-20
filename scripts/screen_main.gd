class_name ScreenMain
extends MenuScreen

signal training_requested

var nick_edit: LineEdit

func _ready() -> void:
	nick_edit = LineEdit.new()
	nick_edit.placeholder_text = tr("MENU_NICK_PLACEHOLDER")
	nick_edit.max_length = 16
	add_child(_make_row(tr("MENU_NICK"), nick_edit))

	var b_training := _make_button(tr("MENU_TRAINING"), true)
	b_training.pressed.connect(func(): training_requested.emit())
	add_child(b_training)

	var b_host := _make_button(tr("MENU_HOST"))
	b_host.pressed.connect(func(): navigate.emit("host"))
	add_child(b_host)

	var b_join := _make_button(tr("MENU_JOIN"))
	b_join.pressed.connect(func(): navigate.emit("join"))
	add_child(b_join)

	var b_lan := _make_button(tr("MENU_LAN"))
	b_lan.pressed.connect(func(): navigate.emit("lan"))
	add_child(b_lan)

	var b_settings := _make_button(tr("MENU_SETTINGS"))
	b_settings.name = "SettingsButton"
	b_settings.pressed.connect(func(): navigate.emit("settings"))
	add_child(b_settings)

	var b_quit := _make_button(tr("MENU_QUIT"))
	b_quit.pressed.connect(func(): get_tree().quit())
	add_child(b_quit)

func get_nick() -> String:
	return nick_edit.text
