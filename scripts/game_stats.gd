extends Node

signal stats_changed
signal kill_feed_message(text: String)
signal kill_feed_event(data: Dictionary)

const CONFIG_PATH := "user://player.cfg"
const MAX_NICK_LENGTH := 16

var local_nick: String = ""
# peer_id -> {"name": String, "kills": int, "deaths": int, "team": int, "color": Color, "ping": int}
var players: Dictionary = {}

var _ping_timer: float = 0.0
var _client_ping_timer: float = 0.0
const PING_UPDATE_INTERVAL: float = 1.0

func _ready() -> void:
	_load_nick()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(reset_stats)

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	if multiplayer.is_server():
		_ping_timer += delta
		if _ping_timer >= PING_UPDATE_INTERVAL:
			_ping_timer = 0.0
			_update_server_pings()
	else:
		_client_ping_timer += delta
		if _client_ping_timer >= 1.5:
			_client_ping_timer = 0.0
			_send_client_ping()

func _update_server_pings() -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if not enet or not enet.get_host():
		return

	var changed: bool = false
	for pid in players.keys():
		var p_id: int = int(pid)
		var p_val: int = 0
		if p_id == 1:
			p_val = 0
		else:
			var p = enet.get_peer(p_id)
			if p:
				p_val = int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
		if players[pid].get("ping", -1) != p_val:
			players[pid]["ping"] = p_val
			changed = true

	if changed:
		_broadcast()

func _send_client_ping() -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.get_host():
		var p = enet.get_peer(1)
		if p:
			var my_ping: int = int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
			if my_ping > 0:
				report_ping.rpc_id(1, my_ping)

@rpc("any_peer", "call_local", "unreliable")
func report_ping(val: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if players.has(sender_id):
		players[sender_id]["ping"] = val


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
		if net_manager and net_manager.current_mode == "ffa":
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

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		players.erase(id)
		_broadcast()

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
