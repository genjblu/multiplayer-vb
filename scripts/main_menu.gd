extends Control

var default_ip: String = "127.0.0.1"
var default_port: int = 7777

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
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	# Подписка на сетевые события из NetworkManager
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		net_manager.connection_failed.connect(_on_connection_failed)
		net_manager.server_disconnected.connect(_on_server_disconnected)
		net_manager.game_started.connect(_on_game_started)

func _on_host_pressed() -> void:
	if nick_edit:
		GameStats.set_nick(nick_edit.text)
	var port: int = port_input.text.to_int()
	if port <= 0:
		status_label.text = "Статус: Укажите корректный порт!"
		return

	_set_ui_disabled(true)
	status_label.text = "Статус: Запуск сервера..."
	
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		var err: Error = net_manager.host_game(port)
		if err != OK:
			status_label.text = "Статус: Ошибка создания сервера!"
			_set_ui_disabled(false)

func _on_join_pressed() -> void:
	if nick_edit:
		GameStats.set_nick(nick_edit.text)
	var ip: String = ip_input.text.strip_edges()
	var port: int = port_input.text.to_int()

	if ip.is_empty() or port <= 0:
		status_label.text = "Статус: Введите валидные IP и порт!"
		return

	_set_ui_disabled(true)
	status_label.text = "Статус: Подключение к %s:%d..." % [ip, port]
	
	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		var err: Error = net_manager.join_game(ip, port)
		if err != OK:
			status_label.text = "Статус: Ошибка подключения!"
			_set_ui_disabled(false)

func _on_connection_failed() -> void:
	status_label.text = "Статус: Не удалось подключиться к серверу!"
	_set_ui_disabled(false)

func _on_server_disconnected() -> void:
	status_label.text = "Статус: Соединение с сервером разорвано."
	_set_ui_disabled(false)

func _on_game_started() -> void:
	status_label.text = "Статус: Соединение установлено!"
	get_tree().change_scene_to_file("res://scenes/arena.tscn")

func _set_ui_disabled(disabled: bool) -> void:
	host_button.disabled = disabled
	join_button.disabled = disabled
	ip_input.editable = !disabled
	port_input.editable = !disabled
