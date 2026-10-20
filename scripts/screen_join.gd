class_name ScreenJoin
extends MenuScreen

signal join_requested(ip: String, port: int)
signal join_by_code_requested(code: String)

var code_edit: LineEdit
var ip_edit: LineEdit
var port_edit: LineEdit

func _ready() -> void:
	add_child(_make_label(tr("MENU_JOIN"), "HeadingLabel"))

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 160)
	add_child(tabs)

	# --- ВКЛАДКА 1: ПО КОДУ КОМНАТЫ ---
	var vbox_code := VBoxContainer.new()
	vbox_code.name = tr("JOIN_BY_CODE")
	vbox_code.add_theme_constant_override("separation", 10)
	tabs.add_child(vbox_code)

	code_edit = LineEdit.new()
	code_edit.placeholder_text = tr("ROOM_CODE_PLACEHOLDER")
	code_edit.max_length = 10
	code_edit.custom_minimum_size = Vector2(0, 44)
	vbox_code.add_child(_make_row(tr("ROOM_CODE_LABEL"), code_edit))

	var b_join_code := _make_button(tr("BTN_JOIN_BY_CODE"), true)
	b_join_code.custom_minimum_size = Vector2(0, 44)
	b_join_code.pressed.connect(_on_join_by_code_pressed)
	vbox_code.add_child(b_join_code)

	# --- ВКЛАДКА 2: ПРЯМОЕ ПО IP / ПОРТУ ---
	var vbox_ip := VBoxContainer.new()
	vbox_ip.name = tr("JOIN_BY_IP")
	vbox_ip.add_theme_constant_override("separation", 8)
	tabs.add_child(vbox_ip)

	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.max_length = 45
	ip_edit.custom_minimum_size = Vector2(0, 42)
	vbox_ip.add_child(_make_row("IP", ip_edit))

	port_edit = LineEdit.new()
	port_edit.text = "7777"
	port_edit.max_length = 5
	port_edit.custom_minimum_size = Vector2(0, 42)
	vbox_ip.add_child(_make_row(tr("HOST_PORT"), port_edit))

	var b_join_ip := _make_button(tr("MENU_JOIN"), true)
	b_join_ip.custom_minimum_size = Vector2(0, 44)
	b_join_ip.pressed.connect(_on_join_by_ip_pressed)
	vbox_ip.add_child(b_join_ip)

	add_child(_make_back_button())

	if OnlineMatchmaking:
		OnlineMatchmaking.room_lookup_result.connect(_on_room_lookup_result)

func _on_join_by_code_pressed() -> void:
	var code := code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		status_requested.emit(tr("ERR_ENTER_ROOM_CODE"), true)
		return

	status_requested.emit("Подключение по коду %s..." % code, false)
	join_by_code_requested.emit(code)

func _on_room_lookup_result(success: bool, server_data: Dictionary, error_msg: String) -> void:
	if not success:
		status_requested.emit(error_msg, true)
		return

	var target_ip: String = str(server_data.get("ip", ""))
	var target_port: int = int(server_data.get("port", 7777))
	if target_ip.is_empty() or target_port <= 0:
		status_requested.emit("Некорректный адрес комнаты!", true)
		return

	status_requested.emit("Комната найдена! Подключение...", false)
	join_requested.emit(target_ip, target_port)

func _on_join_by_ip_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	var port := port_edit.text.strip_edges().to_int()
	if ip.is_empty():
		status_requested.emit("Введите IP-адрес!", true)
		return
	if port < 1024 or port > 65535:
		status_requested.emit(tr("HOST_ERR_PORT"), true)
		return
	join_requested.emit(ip, port)
