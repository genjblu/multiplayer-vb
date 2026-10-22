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
		_spawn_player(1)
		_connect_targets()
		_update_scoreboard()
	# 3. Если зашли клиентом
	elif has_peer:
		_notify_ready_to_server.rpc_id(1)
		_start_client_resync_check()
		_connect_targets()

var ready_peers: Dictionary = {}

func _start_client_resync_check() -> void:
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func():
		if not is_instance_valid(self) or not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
			return
		var current_player_nodes: int = 0
		for child in get_children():
			if child is CharacterBody3D and child.name.is_valid_int():
				current_player_nodes += 1
		if current_player_nodes < GameStats.players.size():
			_request_resync.rpc_id(1)
	)

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

	if not has_node(str(peer_id)):
		_spawn_player(peer_id)

	_sync_all_players_to(peer_id)
	var new_p_data := _get_player_sync_data(peer_id)
	for oid in ready_peers.keys():
		var target_id := int(oid)
		if target_id != peer_id and target_id != 1:
			_sync_single_player.rpc_id(target_id, new_p_data)

func _sync_all_players_to(target_peer_id: int) -> void:
	var existing: Array = []
	for child in get_children():
		if child is CharacterBody3D and child.name.is_valid_int():
			var pid: int = child.name.to_int()
			existing.append(_get_player_sync_data(pid))
	_sync_existing_players.rpc_id(target_peer_id, existing)

func _get_player_sync_data(peer_id: int) -> Dictionary:
	var p_node := get_node_or_null(str(peer_id)) as CharacterBody3D
	var pos: Vector3 = p_node.global_position if p_node else get_spawn_position()
	var rot_y: float = p_node.rotation.y if p_node else 0.0
	var w_type: int = int(p_node.current_weapon) if (p_node and "current_weapon" in p_node) else 0
	return {
		"id": peer_id,
		"pos": pos,
		"rot_y": rot_y,
		"team": GameStats.get_player_team(peer_id),
		"color": GameStats.get_player_color(peer_id),
		"weapon": w_type
	}

@rpc("any_peer", "call_local", "reliable")
func _request_resync() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	_sync_all_players_to(sender_id)

@rpc("authority", "call_local", "reliable")
func _sync_existing_players(players_data: Array) -> void:
	if multiplayer.is_server():
		return
	for p_info in players_data:
		_apply_player_data(p_info)

@rpc("authority", "call_local", "reliable")
func _sync_single_player(p_info: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_apply_player_data(p_info)

func _apply_player_data(p_info: Dictionary) -> void:
	var pid: int = int(p_info.get("id", 0))
	if pid <= 0:
		return
	var node_name := str(pid)
	var player_instance := get_node_or_null(node_name) as CharacterBody3D
	var is_new: bool = false
	if player_instance == null:
		player_instance = player_scene.instantiate() as CharacterBody3D
		player_instance.name = node_name
		player_instance.position = p_info.get("pos", Vector3.ZERO)
		player_instance.set_multiplayer_authority(pid)
		add_child(player_instance)
		is_new = true

	if is_instance_valid(player_instance):
		var pos: Vector3 = p_info.get("pos", player_instance.global_position)
		if is_new or player_instance.global_position.distance_squared_to(pos) > 25.0:
			player_instance.global_position = pos
		player_instance.sync_position = pos
		if p_info.has("rot_y"):
			player_instance.rotation.y = float(p_info["rot_y"])
		if p_info.has("weapon"):
			var w_type: int = int(p_info["weapon"])
			if player_instance.has_method("_switch_weapon") and player_instance.current_weapon != w_type:
				player_instance._switch_weapon(w_type)
		if player_instance.has_method("_update_body_color"):
			player_instance._update_body_color()

		var is_local: bool = (pid == multiplayer.get_unique_id())
		var soldier = player_instance.get_node_or_null("SoldierModel")
		if soldier:
			soldier.visible = not is_local

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
	ready_peers.erase(peer_id)
	var p = get_node_or_null(str(peer_id))
	if p:
		p.queue_free()
