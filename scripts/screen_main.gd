class_name ScreenMain
extends MenuScreen

var nick_edit: LineEdit

func _ready() -> void:
	nick_edit = LineEdit.new()
	nick_edit.placeholder_text = "Ваш ник"
	nick_edit.max_length = 16
	add_child(_make_row("Ник", nick_edit))

	var b_host := _make_button("Создать сервер", true)
	b_host.pressed.connect(func(): navigate.emit("host"))
	add_child(b_host)

	var b_join := _make_button("Подключиться по IP")
	b_join.pressed.connect(func(): navigate.emit("join"))
	add_child(b_join)

	var b_lan := _make_button("Комнаты в сети")
	b_lan.pressed.connect(func(): navigate.emit("lan"))
	add_child(b_lan)

	var b_settings := _make_button("Настройки")
	b_settings.pressed.connect(func(): navigate.emit("settings"))
	add_child(b_settings)

	var b_quit := _make_button("Выход")
	b_quit.pressed.connect(func(): get_tree().quit())
	add_child(b_quit)

func get_nick() -> String:
	return nick_edit.text
