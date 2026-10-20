extends Node

signal server_found(server_info: Dictionary)

const BROADCAST_PORT := 8999
const BROADCAST_INTERVAL := 1.0

var udp_broadcaster: PacketPeerUDP = null
var udp_listener: PacketPeerUDP = null
var broadcast_timer: float = 0.0
var is_broadcasting: bool = false
var is_listening: bool = false
var current_room_data: Dictionary = {}
var discovered_servers: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if is_broadcasting and udp_broadcaster:
		broadcast_timer += delta
		if broadcast_timer >= BROADCAST_INTERVAL:
			broadcast_timer = 0.0
			_send_broadcast_packet()

	_listen_packets()

	var now := Time.get_ticks_msec() / 1000.0
	for key in discovered_servers.keys():
		if now - discovered_servers[key]["last_seen"] > 5.0:
			discovered_servers.erase(key)

func start_broadcast(room_name: String, port: int, map_name: String = "Арена", mode: String = "ffa", ff: bool = false, in_game: bool = false) -> void:
	stop_broadcast()
	udp_broadcaster = PacketPeerUDP.new()
	udp_broadcaster.set_broadcast_enabled(true)
	udp_broadcaster.set_dest_address("255.255.255.255", BROADCAST_PORT)

	current_room_data = {
		"room": room_name,
		"host": GameStats.local_nick if not GameStats.local_nick.is_empty() else "Хост",
		"port": port,
		"map": map_name,
		"map_id": NetworkManager.current_map_id if NetworkManager else "default_arena",
		"mode": mode,
		"ff": ff,
		"in_game": in_game,
		"players": 1,
		"max_players": 16
	}
	is_broadcasting = true
	broadcast_timer = BROADCAST_INTERVAL

func update_room_info(players_count: int, in_game: bool) -> void:
	if is_broadcasting:
		current_room_data["players"] = players_count
		current_room_data["in_game"] = in_game

func stop_broadcast() -> void:
	is_broadcasting = false
	if udp_broadcaster:
		udp_broadcaster.close()
		udp_broadcaster = null

func start_listening() -> void:
	is_listening = true
	if udp_listener == null:
		udp_listener = PacketPeerUDP.new()
	if not udp_listener.is_bound():
		var err := udp_listener.bind(BROADCAST_PORT)
		if err != OK:
			printerr("[LAN] Could not bind UDP port %d: %s" % [BROADCAST_PORT, err])

func stop_listening() -> void:
	is_listening = false
	discovered_servers.clear()

func _send_broadcast_packet() -> void:
	if not udp_broadcaster:
		return
	if GameStats:
		current_room_data["players"] = maxi(GameStats.players.size(), 1)
	var json_str := JSON.stringify(current_room_data)
	udp_broadcaster.put_packet(json_str.to_utf8_buffer())

func _listen_packets() -> void:
	if not is_listening or not udp_listener or not udp_listener.is_bound():
		return
	while udp_listener.get_available_packet_count() > 0:
		var pkt := udp_listener.get_packet()
		var sender_ip := udp_listener.get_packet_ip()
		var json_str := pkt.get_string_from_utf8()
		var parsed = JSON.parse_string(json_str)
		if parsed is Dictionary:
			var s_port: int = int(parsed.get("port", 7777))
			var key: String = "%s:%d" % [sender_ip, s_port]
			parsed["ip"] = sender_ip
			discovered_servers[key] = {
				"data": parsed,
				"last_seen": Time.get_ticks_msec() / 1000.0
			}
			server_found.emit(parsed)
