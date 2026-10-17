class_name ScreenJoin
extends MenuScreen

signal join_requested(ip: String, port: int)

var ip_edit: LineEdit
var port_edit: LineEdit

func _ready() -> void:
	add_child(_make_label("Подключение по IP", "HeadingLabel"))

	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.max_length = 45
	add_child(_make_row("IP-адрес", ip_edit))

	port_edit = LineEdit.new()
	port_edit.text = "7777"
	port_edit.max_length = 5
	add_child(_make_row("Порт", port_edit))

	var b_join := _make_button("Подключиться", true)
	b_join.pressed.connect(_on_join_pressed)
	add_child(b_join)
	add_child(_make_back_button())

func _on_join_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	var port := port_edit.text.strip_edges().to_int()
	if ip.is_empty():
		status_requested.emit("Введите IP-адрес", true)
		return
	if port < 1024 or port > 65535:
		status_requested.emit("Неверный порт (1024-65535)", true)
		return
	join_requested.emit(ip, port)
