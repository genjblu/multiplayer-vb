extends Node


signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal connection_failed
signal game_started
signal match_launch_requested

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 32

var peer: ENetMultiplayerPeer = null
var current_map_id: String = "default_arena"
var current_mode: String = "ffa"
var friendly_fire: bool = false
var is_match_running: bool = false
var joined_as_late: bool = false
var pending_ip: String = ""
var pending_port: int = DEFAULT_PORT

var webrtc: WebRTCManager = null
var is_webrtc: bool = false

func _ready() -> void:
	webrtc = WebRTCManager.new()
	webrtc.name = "WebRTCManager"
	add_child(webrtc)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_multiplayer_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		disconnect_peer()

func _reset_peer() -> void:
	if webrtc:
		webrtc.stop()
	is_webrtc = false

	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if peer:
		peer.close()
		peer = null

func host_game_webrtc(room_code: String, map_id: String = "default_arena", mode: String = "ffa", ff: bool = false) -> Error:
	_reset_peer()
	is_webrtc = true
	current_map_id = map_id
	current_mode = mode
	friendly_fire = ff

	var err := webrtc.start_host(room_code)
	if err != OK:
		is_webrtc = false
		return err

	multiplayer.multiplayer_peer = webrtc.rtc_peer
	GameStats.register_name(GameStats.local_nick)
	return OK

func join_game_webrtc(room_code: String) -> Error:
	_reset_peer()
	is_webrtc = true
	var err := webrtc.start_client(room_code)
	if err != OK:
		is_webrtc = false
		return err

	multiplayer.multiplayer_peer = webrtc.rtc_peer
	return OK

func host_game(port: int = DEFAULT_PORT, map_id: String = "default_arena", mode: String = "ffa", ff: bool = false) -> Error:
	_reset_peer()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		printerr("Failed to create server: ", error)
		peer = null
		return error

	multiplayer.multiplayer_peer = peer
	current_map_id = map_id
	current_mode = mode
	friendly_fire = ff

	# Хост сразу регистрирует себя в GameStats
	GameStats.register_name(GameStats.local_nick)
	return OK

func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	_reset_peer()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port)
	if error != OK:
		printerr("Failed to create client for IP %s:%d -> %s" % [ip, port, error])
		peer = null
		return error

	multiplayer.multiplayer_peer = peer
	return OK

func disconnect_peer() -> void:
	is_match_running = false
	joined_as_late = false
	_reset_peer()
	GameStats.reset_stats()
	LanDiscovery.stop_broadcast()
	if OnlineMatchmaking:
		OnlineMatchmaking.unregister_server()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)
	if multiplayer.is_server():
		# Отправляем новому игроку текущие данные и флаг is_match_running
		_sync_match_info.rpc_id(id, current_map_id, current_mode, friendly_fire, is_match_running)
		# Сразу синхронизируем список игроков, чтобы лобби не было пустым при первом входе
		GameStats._sync_stats.rpc_id(id, GameStats.players)
		# Обновляем счётчик игроков в UDP-рассылке и онлайн-трекере
		LanDiscovery.update_room_info(GameStats.players.size(), is_match_running)
		if OnlineMatchmaking:
			OnlineMatchmaking.update_room_info(GameStats.players.size(), is_match_running)
	else:
		if id == 1:
			_on_connected_to_server()
		
func _on_peer_disconnected(id: int) -> void:
	player_disconnected.emit(id)
	if multiplayer.is_server():
		GameStats.remove_player(id)
		LanDiscovery.update_room_info(GameStats.players.size(), is_match_running)
		if OnlineMatchmaking:
			OnlineMatchmaking.update_room_info(GameStats.players.size(), is_match_running)

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()

func _on_multiplayer_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_connected_to_server() -> void:
	# Сообщаем хосту свой ник
	GameStats.register_name.rpc_id(1, GameStats.local_nick)

@rpc("authority", "call_local", "reliable")
func _sync_match_info(map_id: String, mode: String, ff: bool, in_game: bool) -> void:
	current_map_id = map_id
	current_mode = mode
	friendly_fire = ff
	is_match_running = in_game
	game_started.emit()

# Хост запускает матч у всех сразу
func host_start_match() -> void:
	if multiplayer.is_server():
		is_match_running = true
		LanDiscovery.update_room_info(GameStats.players.size(), true)
		_launch_match_for_all.rpc()

@rpc("authority", "call_local", "reliable")
func _launch_match_for_all() -> void:
	is_match_running = true
	match_launch_requested.emit()

@rpc("any_peer", "call_local", "reliable")
func request_late_spawn(team_id: int, col: Color) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	GameStats.set_player_team_and_color(sender_id, team_id, col)
	var current_scene = get_tree().current_scene
	if current_scene and current_scene.has_method("spawn_player_for_peer"):
		current_scene.spawn_player_for_peer(sender_id)
