extends Node

signal rooms_changed(rooms: Array)

const DISCOVERY_PORT := 8911
const BROADCAST_INTERVAL := 1.0
const ROOM_TIMEOUT := 4.0
const MAGIC := "FPSVB1"
const MAX_NAME_LENGTH := 32

var _broadcaster: PacketPeerUDP = null
var _listener: PacketPeerUDP = null
var _broadcasting: bool = false
var _listening: bool = false
var _room_name: String = ""
var _game_port: int = 7777
var _timer: float = 0.0
var _found: Dictionary = {}
var _last_signature: String = ""

func _ready() -> void:
	# Рассылка должна работать и когда игра на паузе
	process_mode = Node.PROCESS_MODE_ALWAYS

# ---------- Хост: рассылка ----------

func start_broadcast(room_name: String, game_port: int) -> void:
	_room_name = room_name.strip_edges().substr(0, MAX_NAME_LENGTH)
	_game_port = game_port
	if _broadcaster == null:
		_broadcaster = PacketPeerUDP.new()
		_broadcaster.set_broadcast_enabled(true)
	_broadcasting = true
	_timer = BROADCAST_INTERVAL

func stop_broadcast() -> void:
	_broadcasting = false
	if _broadcaster != null:
		_broadcaster.close()
		_broadcaster = null

# ---------- Клиент: прослушивание ----------

func start_listening() -> void:
	if _listening:
		return
	_listener = PacketPeerUDP.new()
	_listener.set_broadcast_enabled(true)
	var err := _listener.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning("LanDiscovery: не удалось открыть порт %d (код %d)" % [DISCOVERY_PORT, err])
		_listener = null
		return
	_listening = true

func stop_listening() -> void:
	_listening = false
	if _listener != null:
		_listener.close()
		_listener = null
	_found.clear()
	_last_signature = ""

func refresh() -> void:
	_found.clear()
	_last_signature = ""
	rooms_changed.emit([])

func get_rooms() -> Array:
	var result: Array = []
	for key in _found.keys():
		result.append(_found[key])
	result.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	return result

# ---------- Внутреннее ----------

func _process(delta: float) -> void:
	if _broadcasting:
		if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
			stop_broadcast()
		else:
			_timer += delta
			if _timer >= BROADCAST_INTERVAL:
				_timer = 0.0
				_send()
	if _listening:
		_receive()

func _broadcast_targets() -> Array[String]:
	var targets: Array[String] = ["255.255.255.255", "127.0.0.1"]
	for addr in IP.get_local_addresses():
		if addr.contains(":") or addr.count(".") != 3:
			continue
		if addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		var parts := addr.split(".")
		parts[3] = "255"
		var target := ".".join(parts)
		if not targets.has(target):
			targets.append(target)
	return targets

func _send() -> void:
	if _broadcaster == null:
		return
	var data := {
		"m": MAGIC,
		"name": _room_name,
		"port": _game_port,
		"players": multiplayer.get_peers().size() + 1
	}
	var packet := JSON.stringify(data).to_utf8_buffer()
	for target in _broadcast_targets():
		_broadcaster.set_dest_address(target, DISCOVERY_PORT)
		_broadcaster.put_packet(packet)

func _receive() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while _listener != null and _listener.get_available_packet_count() > 0:
		var raw := _listener.get_packet()
		var ip := _listener.get_packet_ip()
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		if str(parsed.get("m", "")) != MAGIC:
			continue
		var port := int(parsed.get("port", 0))
		if port < 1 or port > 65535:
			continue
		var key := "%s:%d" % [ip, port]
		_found[key] = {
			"name": str(parsed.get("name", "Комната")).substr(0, MAX_NAME_LENGTH),
			"ip": ip,
			"port": port,
			"players": maxi(int(parsed.get("players", 1)), 0),
			"seen": now
		}
	for key in _found.keys():
		if now - float(_found[key]["seen"]) > ROOM_TIMEOUT:
			_found.erase(key)
	_emit_if_changed()

func _emit_if_changed() -> void:
	var parts := PackedStringArray()
	for key in _found.keys():
		var r: Dictionary = _found[key]
		parts.append("%s|%s|%d" % [key, r["name"], r["players"]])
	parts.sort()
	var signature := ";".join(parts)
	if signature != _last_signature:
		_last_signature = signature
		rooms_changed.emit(get_rooms())
