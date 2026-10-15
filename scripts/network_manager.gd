extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal connection_failed
signal game_started

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 32

var peer: ENetMultiplayerPeer = null

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_multiplayer_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		disconnect_peer()

func _reset_peer() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if peer:
		peer.close()
		peer = null

func host_game(port: int = DEFAULT_PORT) -> Error:
	_reset_peer()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		printerr("Failed to create server: ", error)
		peer = null
		return error
	multiplayer.multiplayer_peer = peer
	print("Server hosted successfully on port %d" % port)
	player_connected.emit(1)
	game_started.emit()
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
	print("Connecting to server at %s:%d..." % [ip, port])
	return OK

func disconnect_peer() -> void:
	_reset_peer()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func close_connection() -> void:
	disconnect_peer()

func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	player_disconnected.emit(id)

func _on_server_disconnected() -> void:
	print("Server disconnected.")
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()

func _on_multiplayer_connection_failed() -> void:
	print("Connection failed.")
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_connected_to_server() -> void:
	print("Connected to server successfully!")
	game_started.emit()
