extends Node

signal stats_changed
signal kill_feed_message(text: String)

const CONFIG_PATH := "user://player.cfg"
const MAX_NICK_LENGTH := 16

var local_nick: String = ""
# peer_id -> {"name": String, "kills": int, "deaths": int}
var players: Dictionary = {}

func _ready() -> void:
	_load_nick()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(reset_stats)

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
		players[id] = {"name": clean, "kills": 0, "deaths": 0}
	_broadcast()

# Погибший игрок сообщает серверу о своей смерти. attacker_id = 0 значит "никто" (падение)
@rpc("any_peer", "call_local", "reliable")
func report_death(attacker_id: int) -> void:
	if not multiplayer.is_server():
		return
	var victim_id := multiplayer.get_remote_sender_id()
	if victim_id == 0:
		victim_id = multiplayer.get_unique_id()
	if not players.has(victim_id):
		return
	players[victim_id]["deaths"] += 1
	var victim_name: String = players[victim_id]["name"]
	if attacker_id != victim_id and players.has(attacker_id):
		players[attacker_id]["kills"] += 1
		var killer_name: String = players[attacker_id]["name"]
		_announce.rpc(killer_name + " убил " + victim_name)
	else:
		_announce.rpc(victim_name + " погиб")
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

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		players.erase(id)
		_broadcast()
