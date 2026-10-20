class_name PolygonMap
extends Node3D

@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@onready var spawn_points: Node3D = $SpawnPoints
@onready var player_spawner: MultiplayerSpawner = get_node_or_null("PlayerSpawner")
@onready var scoreboard_label: Label3D = get_node_or_null("Scoreboard/ScoreLabel")

var total_hits: int = 0
var total_headshots: int = 0
var total_damage: int = 0

func _ready() -> void:
	if player_spawner:
		player_spawner.add_spawnable_scene("res://scenes/player.tscn")

	if NetworkManager:
		NetworkManager.player_disconnected.connect(_remove_player)

	var has_peer: bool = multiplayer.has_multiplayer_peer()
	var is_server: bool = has_peer and multiplayer.is_server()

	# 1. Если зашли оффлайн (Одиночная игра / Тренировка)
	if not has_peer:
		_spawn_local_offline_player()
	# 2. Если зашли через мультиплеер хостом
	elif is_server:
		ready_peers[1] = true
		if GameStats.players.size() <= 1:
			_spawn_player(1)
		else:
			get_tree().create_timer(3.5).timeout.connect(func():
				if is_instance_valid(self):
					_spawn_all_pending_players()
			)
	# 3. Если зашли клиентом
	elif has_peer:
		_notify_ready_to_server.rpc_id(1)

var ready_peers: Dictionary = {}

func _spawn_all_pending_players() -> void:
	if not multiplayer.is_server():
		return
	if not has_node("1"):
		_spawn_player(1)
	for pid in ready_peers.keys():
		var id := int(pid)
		if id > 1 and not has_node(str(id)):
			_spawn_player(id)

	# Подключаем сигналы со всех мишеней
	_connect_targets()
	_update_scoreboard()

func _spawn_local_offline_player() -> void:
	var player_instance = player_scene.instantiate()
	player_instance.name = "1"
	var sp := get_spawn_position()
	player_instance.position = sp
	add_child(player_instance)
	# Даем полное оружие сразу
	if player_instance.has_method("refill_ammo"):
		player_instance.refill_ammo()

func _connect_targets() -> void:
	for target in get_tree().get_nodes_in_group("targets"):
		if target.has_signal("target_hit") and not target.target_hit.is_connected(_on_target_hit):
			target.target_hit.connect(_on_target_hit)

func _on_target_hit(dmg: int, is_headshot: bool) -> void:
	total_hits += 1
	total_damage += dmg
	if is_headshot:
		total_headshots += 1
	_update_scoreboard()

func _update_scoreboard() -> void:
	if scoreboard_label:
		var acc: float = (float(total_headshots) / float(maxi(total_hits, 1))) * 100.0
		scoreboard_label.text = "🎯 ПОЛИГОН: СТАТИСТИКА\nВЫСТРЕЛОВ В ЦЕЛЬ: %d\nХЕДШОТЫ: %d (%.0f%%)\nОБЩИЙ УРОН: %d" % [
			total_hits, total_headshots, acc, total_damage
		]

func get_spawn_position() -> Vector3:
	if spawn_points and spawn_points.get_child_count() > 0:
		var sp = spawn_points.get_child(0) as Node3D
		if sp:
			return sp.global_position
	return Vector3(0, 1.2, 0)

@rpc("any_peer", "call_local", "reliable")
func _notify_ready_to_server() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	ready_peers[peer_id] = true
	_spawn_all_pending_players()

func _spawn_player(peer_id: int) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if has_node(str(peer_id)):
		return

	var player_instance = player_scene.instantiate()
	player_instance.name = str(peer_id)
	player_instance.position = get_spawn_position()
	player_instance.set_multiplayer_authority(peer_id)
	add_child(player_instance, true)

func _remove_player(peer_id: int) -> void:
	var p = get_node_or_null(str(peer_id))
	if p:
		p.queue_free()
