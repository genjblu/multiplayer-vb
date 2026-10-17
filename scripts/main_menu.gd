extends Control

var default_ip: String = "127.0.0.1"
var default_port: int = 7777

var menu: MenuManager
var screen_main: ScreenMain

@onready var ip_input: LineEdit = %IPInput
@onready var port_input: LineEdit = %PortInput
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var nick_edit: LineEdit = %NickEdit

func _ready() -> void:
	# Инициализация значений по умолчанию
	ip_input.text = default_ip
	port_input.text = str(default_port)
	if nick_edit:
		nick_edit.max_length = 16
		nick_edit.placeholder_text = "Ваш ник"
		nick_edit.text = GameStats.local_nick

	# Подключение сигналов кнопок
	if host_button:
		host_button.pressed.connect(_on_host_pressed)
	if join_button:
		join_button.pressed.connect(_on_join_pressed)

	# Подписка на сетевые события из NetworkManager
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		net_manager.connection_failed.connect(_on_connection_failed)
		net_manager.server_disconnected.connect(_on_server_disconnected)
		net_manager.game_started.connect(_on_game_started)

	_build_ui()

func _build_ui() -> void:
	# Старый интерфейс только скрываем, не удаляем
	for child in get_children():
		if child is CanvasItem:
			child.visible = false

	var ui_layer := CanvasLayer.new()
	add_child(ui_layer)
	menu = MenuManager.new()
	ui_layer.add_child(menu)

	screen_main = ScreenMain.new()
	var screen_host := ScreenHost.new()
	var screen_join := ScreenJoin.new()
	var screen_lan := ScreenLan.new()
	var screen_settings := ScreenSettings.new()

	menu.register("main", screen_main)
	menu.register("host", screen_host)
	menu.register("join", screen_join)
	menu.register("lan", screen_lan)
	menu.register("settings", screen_settings)

	screen_host.host_requested.connect(_on_host_requested)
	screen_join.join_requested.connect(_on_join_requested)
	screen_lan.join_requested.connect(_on_join_requested)

	menu.show_screen("main")
	screen_main.nick_edit.text = GameStats.local_nick

func _on_host_requested(port: int, room_name: String) -> void:
	GameStats.set_nick(screen_main.get_nick())
	if port <= 0:
		menu.set_status("Статус: Укажите корректный порт!", true)
		return

	menu.set_status("Статус: Запуск сервера...")
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		var err: Error = net_manager.host_game(port)
		if err == OK:
			LanDiscovery.start_broadcast(room_name, port)
		else:
			menu.set_status("Статус: Ошибка создания сервера!", true)

func _on_join_requested(ip: String, port: int) -> void:
	GameStats.set_nick(screen_main.get_nick())
	if ip.is_empty() or port <= 0:
		menu.set_status("Статус: Введите валидные IP и порт!", true)
		return

	menu.set_status("Статус: Подключение к %s:%d..." % [ip, port])
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		var err: Error = net_manager.join_game(ip, port)
		if err != OK:
			menu.set_status("Статус: Ошибка подключения!", true)

func _on_connection_failed() -> void:
	if menu:
		menu.set_status("Статус: Не удалось подключиться к серверу!", true)
	else:
		status_label.text = "Статус: Не удалось подключиться к серверу!"
	_set_ui_disabled(false)

func _on_server_disconnected() -> void:
	if menu:
		menu.set_status("Статус: Соединение с сервером разорвано.", true)
	else:
		status_label.text = "Статус: Соединение с сервером разорвано."
	_set_ui_disabled(false)

func _on_game_started() -> void:
	if menu:
		menu.set_status("Статус: Соединение установлено!")
	else:
		status_label.text = "Статус: Соединение установлено!"
	get_tree().change_scene_to_file("res://scenes/arena.tscn")

func _set_ui_disabled(disabled: bool) -> void:
	if host_button:
		host_button.disabled = disabled
	if join_button:
		join_button.disabled = disabled
	if ip_input:
		ip_input.editable = !disabled
	if port_input:
		port_input.editable = !disabled

func _on_host_pressed() -> void:
	pass

func _on_join_pressed() -> void:
	pass
