class_name ScreenHost
extends MenuScreen

signal host_requested(port: int, room_name: String)

var room_edit: LineEdit
var port_edit: LineEdit

func _ready() -> void:
	add_child(_make_label("Создать сервер", "HeadingLabel"))

	room_edit = LineEdit.new()
	room_edit.text = "Моя комната"
	room_edit.max_length = 32
	add_child(_make_row("Название", room_edit))

	port_edit = LineEdit.new()
	port_edit.text = "7777"
	port_edit.max_length = 5
	add_child(_make_row("Порт", port_edit))

	var b_create := _make_button("Создать", true)
	b_create.pressed.connect(_on_create_pressed)
	add_child(b_create)
	add_child(_make_back_button())

func _on_create_pressed() -> void:
	var port := port_edit.text.strip_edges().to_int()
	if port < 1024 or port > 65535:
		status_requested.emit("Неверный порт (1024-65535)", true)
		return
	var room := room_edit.text.strip_edges()
	if room.is_empty():
		room = "Комната"
	host_requested.emit(port, room)
