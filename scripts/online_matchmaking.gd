extends Node

signal online_servers_received(servers: Array)
signal register_result(success: bool, server_id: String)

var http_fetch: HTTPRequest
var http_register: HTTPRequest
var http_heartbeat: HTTPRequest
var http_unregister: HTTPRequest

var current_server_id: String = ""
var is_registered: bool = false
var heartbeat_timer: float = 0.0
const HEARTBEAT_INTERVAL: float = 8.0

var last_players: int = 1
var last_in_game: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	http_fetch = HTTPRequest.new()
	add_child(http_fetch)
	http_fetch.request_completed.connect(_on_fetch_completed)

	http_register = HTTPRequest.new()
	add_child(http_register)
	http_register.request_completed.connect(_on_register_completed)

	http_heartbeat = HTTPRequest.new()
	add_child(http_heartbeat)

	http_unregister = HTTPRequest.new()
	add_child(http_unregister)

func _process(delta: float) -> void:
	if is_registered and not current_server_id.is_empty():
		heartbeat_timer += delta
		if heartbeat_timer >= HEARTBEAT_INTERVAL:
			heartbeat_timer = 0.0
			_send_heartbeat()

func get_api_base_url() -> String:
	GameSettings.ensure_loaded()
	var url: String = GameSettings.master_server_url.strip_edges()
	if url.is_empty():
		url = "http://localhost:8080"
	if url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	return url

# 1. Fetch servers list
func fetch_servers() -> void:
	if http_fetch.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		http_fetch.cancel_request()

	var url := "%s/api/servers" % get_api_base_url()
	var headers := ["User-Agent: GodotFPSClient/1.0"]
	http_fetch.request(url, headers, HTTPClient.METHOD_GET)

func _on_fetch_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		online_servers_received.emit([])
		return

	var json_str := body.get_string_from_utf8()
	var json = JSON.parse_string(json_str)
	if json is Dictionary and json.has("servers") and json["servers"] is Array:
		online_servers_received.emit(json["servers"])
	else:
		online_servers_received.emit([])

# 2. Register server with Master Server
func register_server(room_name: String, port: int, map_name: String, mode: String, ff: bool, custom_ip: String = "") -> void:
	is_registered = false
	current_server_id = ""

	var url := "%s/api/servers/register" % get_api_base_url()
	var headers := ["Content-Type: application/json", "User-Agent: GodotFPSServer/1.0"]
	var data := {
		"name": room_name,
		"host_name": GameStats.local_nick if not GameStats.local_nick.is_empty() else "Хост",
		"port": port,
		"map": map_name,
		"mode": mode,
		"players": GameStats.players.size() if GameStats.players.size() > 0 else 1,
		"max_players": 16,
		"friendly_fire": ff,
		"custom_ip": custom_ip
	}
	var body := JSON.stringify(data)
	http_register.request(url, headers, HTTPClient.METHOD_POST, body)

func _on_register_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 201):
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json is Dictionary and json.get("success", false):
			current_server_id = json.get("server_id", "")
			is_registered = true
			heartbeat_timer = 0.0
			register_result.emit(true, current_server_id)
			print("[OnlineMatchmaking] Registered with Master Server ID: ", current_server_id)
			return
	register_result.emit(false, "")

# 3. Heartbeat
func update_room_info(players_count: int, in_game: bool) -> void:
	last_players = players_count
	last_in_game = in_game
	if is_registered:
		_send_heartbeat()

func _send_heartbeat() -> void:
	if not is_registered or current_server_id.is_empty():
		return
	if http_heartbeat.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return

	var url := "%s/api/servers/heartbeat" % get_api_base_url()
	var headers := ["Content-Type: application/json"]
	var data := {
		"server_id": current_server_id,
		"players": last_players,
		"in_game": last_in_game
	}
	http_heartbeat.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(data))

# 4. Unregister
func unregister_server() -> void:
	if not is_registered or current_server_id.is_empty():
		return

	var url := "%s/api/servers/unregister" % get_api_base_url()
	var headers := ["Content-Type: application/json"]
	var data := { "server_id": current_server_id }
	http_unregister.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(data))

	is_registered = false
	current_server_id = ""
	print("[OnlineMatchmaking] Unregistered from Master Server")
