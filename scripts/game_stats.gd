extends Node

signal stats_changed
signal kill_feed_message(text: String)
signal kill_feed_event(data: Dictionary)

const CONFIG_PATH := "user://player.cfg"
const MAX_NICK_LENGTH := 16

var local_nick: String = ""
# peer_id -> {"name": String, "kills": int, "deaths": int, "team": int, "color": Color, "ping": int}
var players: Dictionary = {}

var my_ping: int = 0
var _ping_timer: float = 0.0
var _client_ping_timer: float = 0.0
const PING_UPDATE_INTERVAL: float = 1.0

func get_my_ping() -> int:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return 0
	if my_ping > 0:
		return my_ping
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.get_host():
		var p = enet.get_peer(1)
		if p and p.get_state() == ENetPacketPeer.STATE_CONNECTED:
			return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	return 0

func _ready() -> void:
	_load_nick()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(reset_stats)

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	if multiplayer.is_server():
		_ping_timer += delta
		if _ping_timer >= PING_UPDATE_INTERVAL:
			_ping_timer = 0.0
			_update_server_pings()
	else:
		_client_ping_timer += delta
		if _client_ping_timer >= 1.0:
			_client_ping_timer = 0.0
			_send_client_ping()

func _update_server_pings() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if not multiplayer.is_server():
		return

	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.get_host():
		for pid in players.keys():
			var p_id: int = int(pid)
			if p_id == 1:
				if players[pid].get("ping", -1) != 0:
					players[pid]["ping"] = 0
			else:
				var p = enet.get_peer(p_id)
				if p and p.get_state() == ENetPacketPeer.STATE_CONNECTED:
					var p_val: int = int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
					if p_val > 0 and players[pid].get("ping", -1) != p_val:
						players[pid]["ping"] = p_val
						_sync_player_ping.rpc(p_id, p_val)

func _send_client_ping() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if multiplayer.is_server():
		return
	if not (1 in multiplayer.get_peers()):
		return

	# If ENet, fast-read statistic directly if available:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.get_host():
		var p = enet.get_peer(1)
		if p and p.get_state() == ENetPacketPeer.STATE_CONNECTED:
			var ep_ping: int = int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
			if ep_ping > 0:
				my_ping = ep_ping
				var my_id := multiplayer.get_unique_id()
				if players.has(my_id):
					players[my_id]["ping"] = my_ping
				report_ping.rpc_id(1, my_ping)
				return

	# Universal ping-pong RPC probe (for WebRTC & any transport)
	_ping_server.rpc_id(1, Time.get_ticks_msec())

@rpc("any_peer", "call_remote", "unreliable")
func _ping_server(client_time: int) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0:
		_pong_client.rpc_id(sender_id, client_time)

@rpc("authority", "call_remote", "unreliable")
func _pong_client(client_time: int) -> void:
	var rtt := Time.get_ticks_msec() - client_time
	if rtt >= 0:
		if my_ping == 0:
			my_ping = maxi(1, rtt)
		else:
			my_ping = maxi(1, int(my_ping * 0.6 + rtt * 0.4))
		var my_id := multiplayer.get_unique_id()
		if players.has(my_id):
			players[my_id]["ping"] = my_ping
		report_ping.rpc_id(1, my_ping)

@rpc("any_peer", "call_local", "unreliable")
func report_ping(val: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if players.has(sender_id):
		if players[sender_id].get("ping", 0) != val:
			players[sender_id]["ping"] = val
			_sync_player_ping.rpc(sender_id, val)

@rpc("authority", "call_local", "unreliable")
func _sync_player_ping(peer_id: int, val: int) -> void:
	if players.has(peer_id):
		players[peer_id]["ping"] = val
		stats_changed.emit()


func set_nick(nick: String) -> void:
	local_nick = _sanitize(nick)
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("player", "nick", local_nick)
	cfg.save(CONFIG_PATH)

func _load_nick() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		local_nick = _sanitize(str(cfg.get_value("player", "nick", "")))

func _sanitize(nick: String) -> String:
	var n := nick.strip_edges()
	if n.length() > MAX_NICK_LENGTH:
		n = n.substr(0, MAX_NICK_LENGTH)
	return n

func reset_stats() -> void:
	players.clear()
	my_ping = 0
	_ping_timer = 0.0
	_client_ping_timer = 0.0
	stats_changed.emit()

# Клиент или сервер сообщает серверу свой ник
@rpc("any_peer", "call_local", "reliable")
func register_name(nick: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	var clean := _sanitize(nick)
	if clean.is_empty():
		clean = "Игрок" + str(id)

	if players.has(id):
		players[id]["name"] = clean
	else:
		# Назначаем начальный цвет по порядку подключения
		var ffa_colors = [
			Color(1.0, 0.55, 0.1),  # Оранжевый (Хост)
			Color(0.1, 0.85, 0.85), # Бирюзовый (Игрок 2)
			Color(0.7, 0.3, 0.95),  # Фиолетовый
			Color(0.4, 0.95, 0.2),  # Лаймовый
			Color(1.0, 0.35, 0.7)   # Розовый
		]
		var auto_col: Color = ffa_colors[players.size() % ffa_colors.size()]
		var auto_team: int = (players.size() % 2) + 1 # Команда 1 или 2 по очереди

		var net_manager = get_node_or_null("/root/NetworkManager")
		if net_manager and (net_manager.current_mode == "ffa" or net_manager.current_mode == "fist_fight"):
			auto_team = 0

		players[id] = {"name": clean, "kills": 0, "deaths": 0, "team": auto_team, "color": auto_col, "ping": 0}

	_broadcast()

# Погибший игрок сообщает серверу о своей смерти. attacker_id = 0 значит "никто" (падение)
@rpc("any_peer", "call_local", "reliable")
func report_death(attacker_id: int, weapon_name: String = "", is_headshot: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var victim_id := multiplayer.get_remote_sender_id()
	if victim_id == 0:
		victim_id = multiplayer.get_unique_id()
	if not players.has(victim_id):
		return
	players[victim_id]["deaths"] += 1
	var victim_name: String = players[victim_id]["name"]
	var victim_col: Color = players[victim_id].get("color", Color.WHITE)

	if attacker_id != victim_id and players.has(attacker_id):
		players[attacker_id]["kills"] += 1
		var killer_name: String = players[attacker_id]["name"]
		var killer_col: Color = players[attacker_id].get("color", Color.WHITE)
		_announce_kill.rpc(killer_name, killer_col, victim_name, victim_col, weapon_name, is_headshot)
	else:
		_announce_death.rpc(victim_name, victim_col)
	_broadcast()

func _broadcast() -> void:
	_sync_stats.rpc(players)

@rpc("authority", "call_local", "reliable")
func _sync_stats(data: Dictionary) -> void:
	players = data
	stats_changed.emit()

@rpc("authority", "call_local", "reliable")
func _announce(text: String) -> void:
	kill_feed_message.emit(text)

@rpc("authority", "call_local", "reliable")
func _announce_kill(killer_name: String, killer_col: Color, victim_name: String, victim_col: Color, weapon_name: String, is_headshot: bool) -> void:
	kill_feed_event.emit({
		"killer_name": killer_name,
		"killer_col": killer_col,
		"victim_name": victim_name,
		"victim_col": victim_col,
		"weapon_name": weapon_name,
		"is_headshot": is_headshot,
		"is_suicide": false
	})
	var hs_str: String = " 🎯" if is_headshot else ""
	var wp_str: String = " [%s]" % weapon_name if not weapon_name.is_empty() else ""
	kill_feed_message.emit("%s%s убил %s%s" % [killer_name, wp_str, victim_name, hs_str])

@rpc("authority", "call_local", "reliable")
func _announce_death(victim_name: String, victim_col: Color) -> void:
	kill_feed_event.emit({
		"victim_name": victim_name,
		"victim_col": victim_col,
		"is_suicide": true
	})
	kill_feed_message.emit("%s погиб" % victim_name)

func remove_player(id: int) -> void:
	if players.has(id):
		players.erase(id)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_broadcast()

func _on_peer_disconnected(id: int) -> void:
	remove_player(id)

# Универсальный метод: поддерживает вызов и с 2 аргументами (team_id, col), и с 3 (target_id, team_id, col)
@rpc("any_peer", "call_local", "reliable")
func set_player_team_and_color(arg1, arg2, arg3 = null) -> void:
	if not multiplayer.is_server():
		# Если вызвано на клиенте — отправляем запрос на сервер
		if arg3 == null:
			set_player_team_and_color.rpc_id(1, arg1, arg2)
		else:
			set_player_team_and_color.rpc_id(1, arg1, arg2, arg3)
		return

	# Логика сервера:
	var target_id: int = 0
	var team_id: int = 0
	var col: Color = Color.WHITE

	if arg3 == null:
		# Вызов из лобби: set_player_team_and_color(team_id, col)
		team_id = int(arg1)
		col = arg2 as Color
		target_id = multiplayer.get_remote_sender_id()
		if target_id == 0:
			target_id = multiplayer.get_unique_id()
	else:
		# Вызов с явным ID: set_player_team_and_color(target_id, team_id, col)
		target_id = int(arg1)
		team_id = int(arg2)
		col = arg3 as Color

	_apply_team_and_color(target_id, team_id, col)

func _apply_team_and_color(id: int, team_id: int, col: Color) -> void:
	if not players.has(id):
		players[id] = {"name": "Игрок" + str(id), "kills": 0, "deaths": 0, "team": team_id, "color": col, "ping": 0}
	else:
		players[id]["team"] = team_id
		players[id]["color"] = col
	_broadcast()

func are_allies(id_a: int, id_b: int) -> bool:
	if id_a == id_b:
		return true
	if not players.has(id_a) or not players.has(id_b):
		return false
	var t_a: int = int(players[id_a].get("team", 0))
	var t_b: int = int(players[id_b].get("team", 0))
	if t_a == 0 or t_b == 0:
		return false # В FFA команды равны 0 — каждый сам за себя
	return t_a == t_b

func get_player_color(peer_id: int) -> Color:
	if players.has(peer_id):
		return players[peer_id].get("color", Color.WHITE)
	return Color.WHITE

func get_player_team(peer_id: int) -> int:
	if players.has(peer_id):
		return int(players[peer_id].get("team", 0))
	return 0
