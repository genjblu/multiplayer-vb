class_name WebRTCManager
extends Node

signal connection_established
signal connection_failed(reason: String)

const ICE_SERVERS: Array = [
	{"urls": ["stun:stun.l.google.com:19302"]},
	{"urls": ["stun:stun1.l.google.com:19302"]},
	{"urls": ["stun:stun2.l.google.com:19302"]}
]

var rtc_peer: WebRTCMultiplayerPeer = null
var peers: Dictionary = {} # peer_id (int) -> WebRTCPeerConnection
var candidate_buffers: Dictionary = {} # peer_id (int) -> Array[Dictionary]
var has_remote_description: Dictionary = {} # peer_id (int) -> bool

var is_host: bool = false
var my_peer_id: int = 1
var room_code: String = ""
var is_active: bool = false

var poll_timer: float = 0.0
var client_retry_timer: float = 0.0
var client_connect_timer: float = 0.0
const POLL_INTERVAL_FAST: float = 0.35
const POLL_INTERVAL_SLOW: float = 1.5

var http_poll: HTTPRequest
var http_send: HTTPRequest
var send_queue: Array[Dictionary] = []
var is_sending: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_http_nodes()

func _ensure_http_nodes() -> void:
	if not is_instance_valid(http_poll):
		http_poll = HTTPRequest.new()
		http_poll.name = "HTTP_Poll"
		add_child(http_poll)
		http_poll.request_completed.connect(_on_poll_completed)

	if not is_instance_valid(http_send):
		http_send = HTTPRequest.new()
		http_send.name = "HTTP_Send"
		add_child(http_send)
		http_send.request_completed.connect(_on_send_completed)

func get_base_url() -> String:
	GameSettings.ensure_loaded()
	var url := GameSettings.master_server_url.strip_edges()
	if url.is_empty():
		url = "https://fps-master-server.onrender.com"
	if url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	return url

func _assign_to_multiplayer() -> void:
	var mp: MultiplayerAPI = null
	if is_inside_tree():
		mp = get_multiplayer()
	if not mp:
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			mp = tree.get_multiplayer()
	if mp and rtc_peer:
		mp.multiplayer_peer = rtc_peer
		print("[WebRTC] Assigned rtc_peer to MultiplayerAPI on root path: ", mp.get_path() if mp.has_method("get_path") else "")

func start_host(code: String) -> Error:
	stop()
	_ensure_http_nodes()
	room_code = code.strip_edges().to_upper()
	is_host = true
	my_peer_id = 1

	rtc_peer = WebRTCMultiplayerPeer.new()
	var err := rtc_peer.create_server()
	if err != OK:
		printerr("[WebRTC] Failed to create server peer: ", err)
		return err

	_assign_to_multiplayer()
	is_active = true
	print("[WebRTC] Host started for room code: ", room_code)
	return OK

func start_client(code: String) -> Error:
	stop()
	_ensure_http_nodes()
	room_code = code.strip_edges().to_upper()
	is_host = false
	my_peer_id = randi_range(2, 65535)
	client_connect_timer = 0.0

	rtc_peer = WebRTCMultiplayerPeer.new()
	var err := rtc_peer.create_client(my_peer_id)
	if err != OK:
		printerr("[WebRTC] Failed to create client peer: ", err)
		return err

	_assign_to_multiplayer()
	is_active = true

	# Отправляем хосту запрос на присоединение
	_queue_signal("join_request", 1, {})
	print("[WebRTC] Client started with id ", my_peer_id, " for room: ", room_code)
	return OK

func stop() -> void:
	is_active = false
	for p_id in peers.keys():
		var conn: WebRTCPeerConnection = peers[p_id]
		if conn:
			conn.close()
	peers.clear()
	candidate_buffers.clear()
	has_remote_description.clear()

	if rtc_peer:
		rtc_peer.close()
		rtc_peer = null

	send_queue.clear()
	is_sending = false

func _process(delta: float) -> void:
	if not is_active or room_code.is_empty():
		return

	# Регулярно опрашиваем пиры и multiplayer peer
	for p_id in peers.keys():
		var conn: WebRTCPeerConnection = peers[p_id]
		if conn:
			conn.poll()

	if rtc_peer:
		rtc_peer.poll()

	# Клиент периодически повторяет join_request, только если оффер еще не получен (нет пиров)
	if not is_host and peers.is_empty():
		client_retry_timer += delta
		if client_retry_timer >= 1.5:
			client_retry_timer = 0.0
			_queue_signal("join_request", 1, {})

		# Таймаут подключения клиента
		client_connect_timer += delta
		if client_connect_timer >= 14.0 and not _all_connected():
			print("[WebRTC] Connection timed out after 14s")
			stop()
			connection_failed.emit("Не удалось подключиться: хост не отвечает или комната закрыта.")

	# Опрос сигнального сервера
	poll_timer += delta
	var current_interval := POLL_INTERVAL_FAST if peers.size() == 0 or not _all_connected() else POLL_INTERVAL_SLOW
	if poll_timer >= current_interval:
		poll_timer = 0.0
		_poll_signals()

	_process_send_queue()

func _all_connected() -> bool:
	if peers.is_empty():
		return false
	for p_id in peers.keys():
		var conn: WebRTCPeerConnection = peers[p_id]
		if not conn or conn.get_connection_state() != WebRTCPeerConnection.STATE_CONNECTED:
			return false
	return true

# --- Создание P2P подключения к конкретному пиру ---
func _create_peer_connection(target_id: int) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	var err := conn.initialize({"iceServers": ICE_SERVERS})
	if err != OK:
		printerr("[WebRTC] Failed to initialize WebRTCPeerConnection: ", err)
		return null

	conn.session_description_created.connect(func(type: String, sdp: String):
		print("[WebRTC %s] session_description_created (%s) for peer %d" % ["Host" if is_host else "Client", type, target_id])
		conn.set_local_description(type, sdp)
		_queue_signal(type, target_id, {"sdp": sdp})
	)

	conn.ice_candidate_created.connect(func(media: String, index: int, candidate_name: String):
		print("[WebRTC %s] ice_candidate_created for peer %d: %s" % ["Host" if is_host else "Client", target_id, candidate_name])
		_queue_signal("candidate", target_id, {
			"media": media,
			"index": index,
			"name": candidate_name
		})
	)

	peers[target_id] = conn
	has_remote_description[target_id] = false
	candidate_buffers[target_id] = []
	rtc_peer.add_peer(conn, target_id)
	return conn

func _flush_candidate_buffer(p_id: int, conn: WebRTCPeerConnection) -> void:
	if candidate_buffers.has(p_id):
		var list: Array = candidate_buffers[p_id]
		for cand in list:
			conn.add_ice_candidate(cand.get("media", ""), int(cand.get("index", 0)), cand.get("name", ""))
			print("[WebRTC] Flushed buffered candidate for peer ", p_id)
		candidate_buffers[p_id].clear()

# --- Обработка входящих сигнальных сообщений ---
func _on_signal_message(msg: Dictionary) -> void:
	var sender_id := int(msg.get("sender_id", 0))
	var type := str(msg.get("type", ""))
	var data: Dictionary = msg.get("data", {})

	if sender_id <= 0:
		return

	if is_host:
		match type:
			"join_request":
				print("[WebRTC Host] Received join_request from client ", sender_id)
				var conn: WebRTCPeerConnection = null
				if peers.has(sender_id):
					conn = peers[sender_id]
					var state = conn.get_connection_state()
					if state == WebRTCPeerConnection.STATE_CONNECTED or state == WebRTCPeerConnection.STATE_CONNECTING:
						print("[WebRTC Host] Peer %d already in state %d, ignoring duplicate join_request" % [sender_id, state])
						return
					conn.close()
					peers.erase(sender_id)
				conn = _create_peer_connection(sender_id)
				if conn:
					conn.create_offer()

			"answer":
				print("[WebRTC Host] Received answer from client ", sender_id)
				if peers.has(sender_id):
					var conn: WebRTCPeerConnection = peers[sender_id]
					var err := conn.set_remote_description("answer", data.get("sdp", ""))
					if err == OK:
						has_remote_description[sender_id] = true
						conn.poll()
						_flush_candidate_buffer(sender_id, conn)

			"candidate":
				if peers.has(sender_id):
					var conn: WebRTCPeerConnection = peers[sender_id]
					if has_remote_description.get(sender_id, false):
						conn.add_ice_candidate(data.get("media", ""), int(data.get("index", 0)), data.get("name", ""))
						print("[WebRTC Host] Added remote candidate from client ", sender_id)
					else:
						candidate_buffers[sender_id].append(data)
						print("[WebRTC Host] Buffered candidate from client ", sender_id)

	else: # Client
		match type:
			"offer":
				print("[WebRTC Client] Received offer from host!")
				var conn: WebRTCPeerConnection = null
				if peers.has(1):
					conn = peers[1]
					if conn.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTED:
						return
					conn.close()
					peers.erase(1)
				conn = _create_peer_connection(1)
				if conn:
					var err := conn.set_remote_description("offer", data.get("sdp", ""))
					if err == OK:
						has_remote_description[1] = true
						conn.poll()
						_flush_candidate_buffer(1, conn)

			"candidate":
				if peers.has(1):
					var conn: WebRTCPeerConnection = peers[1]
					if has_remote_description.get(1, false):
						conn.add_ice_candidate(data.get("media", ""), int(data.get("index", 0)), data.get("name", ""))
						print("[WebRTC Client] Added remote candidate from host")
					else:
						candidate_buffers[1].append(data)
						print("[WebRTC Client] Buffered candidate from host")

# --- Сетевые запросы сигналов к Master Server ---
func _queue_signal(type: String, target_id: int, data: Dictionary) -> void:
	send_queue.append({
		"sender_id": my_peer_id,
		"target_id": target_id,
		"type": type,
		"data": data
	})
	_process_send_queue()

func _process_send_queue() -> void:
	if is_sending or send_queue.is_empty():
		return
	if not is_instance_valid(http_send) or not http_send.is_inside_tree():
		return
	if http_send.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return

	is_sending = true
	var payload: Dictionary = send_queue.pop_front()
	var url := "%s/api/rooms/%s/signal" % [get_base_url(), room_code.uri_encode()]
	var headers := ["Content-Type: application/json", "User-Agent: GodotWebRTC/1.0"]
	http_send.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func _on_send_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	is_sending = false
	if not send_queue.is_empty():
		_process_send_queue()

func _poll_signals() -> void:
	if not is_active or room_code.is_empty():
		return
	if not is_instance_valid(http_poll) or not http_poll.is_inside_tree():
		return
	if http_poll.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return

	var url := "%s/api/rooms/%s/signal?peer_id=%d" % [get_base_url(), room_code.uri_encode(), my_peer_id]
	var headers := ["User-Agent: GodotWebRTC/1.0"]
	http_poll.request(url, headers, HTTPClient.METHOD_GET)

func _on_poll_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return

	var json_str := body.get_string_from_utf8()
	var json: Variant = JSON.parse_string(json_str)
	if json is Dictionary and json.get("success", false):
		var msgs: Array = json.get("messages", [])
		for msg in msgs:
			if msg is Dictionary:
				_on_signal_message(msg)
