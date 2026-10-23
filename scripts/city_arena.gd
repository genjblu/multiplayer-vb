class_name CityArena
extends Node3D

@export var player_scene: PackedScene = preload("res://scenes/spider_player.tscn")
@export var barrel_scene: PackedScene = preload("res://scenes/interactive/throw_barrel.tscn")

const PauseMenuClass = preload("res://scripts/pause_menu.gd")

@onready var city_root: Node3D = $CityModel
@onready var spawn_points_root: Node3D = $SpawnPoints
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var barrels_root: Node3D = $ThrowableBarrels

var pause_menu = null
var ready_peers: Dictionary = {}

func _ready() -> void:
	# 1. Генерация тримеш-коллизий для всех зданий города
	_generate_city_collisions()

	# 2. Спавн интерактивных взрывных бочек для паутинного броска
	_spawn_interactive_props()

	# 3. Настройка мультиплеерного спавнера
	if player_spawner:
		player_spawner.add_spawnable_scene("res://scenes/spider_player.tscn")

	var net_mgr = get_node_or_null("/root/NetworkManager")
	if net_mgr:
		net_mgr.player_disconnected.connect(_on_player_disconnected)

	# 4. Универсальное красивое меню паузы
	pause_menu = PauseMenuClass.new()
	add_child(pause_menu)

	var has_peer := multiplayer.has_multiplayer_peer()
	var is_server := has_peer and multiplayer.is_server()

	if not has_peer:
		# Defer спавн на следующий физический кадр — даём время коллизиям загрузиться
		call_deferred("_spawn_solo_spider")
	elif is_server:
		ready_peers[1] = true
		call_deferred("_spawn_spider_player", 1)
	elif has_peer:
		_notify_ready_to_server.rpc_id(1)

func _physics_process(_delta: float) -> void:
	# Защита от вылета за карту (void recovery)
	for child in get_children():
		if child is CharacterBody3D and child.name.is_valid_int():
			if child.global_position.y < -15.0:
				var p_id: int = child.name.to_int()
				var spawn_nodes := spawn_points_root.get_children() if spawn_points_root else []
				if not spawn_nodes.is_empty():
					var idx: int = (p_id - 1) % spawn_nodes.size()
					child.global_position = (spawn_nodes[idx] as Node3D).global_position + Vector3(0, 1.5, 0)
					child.velocity = Vector3.ZERO

func _generate_city_collisions() -> void:
	if not city_root:
		return
	var count := 0
	for child in city_root.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D and child.mesh:
			child.create_trimesh_collision()
			count += 1

func _spawn_interactive_props() -> void:
	if not barrels_root or not barrel_scene:
		return

	var prop_positions := [
		Vector3(-233.0, 88.7, -212.0),
		Vector3(-258.0, 88.7, -206.0),
		Vector3(-216.0, 99.1, -97.0),
		Vector3(-301.0, 99.1, -210.0),
		Vector3(-246.0, 73.2, -106.0),
		Vector3(-107.0, 73.2, -96.0),
		Vector3(-73.0, 62.0, -126.0),
		Vector3(-210.0, 1.4, -205.0)
	]

	for pos in prop_positions:
		var barrel := barrel_scene.instantiate() as RigidBody3D
		barrels_root.add_child(barrel)
		barrel.global_position = pos

func _spawn_solo_spider() -> void:
	_spawn_spider_player(1)

func _spawn_spider_player(peer_id: int) -> void:
	if has_node(str(peer_id)):
		return

	var sp = player_scene.instantiate()
	sp.name = str(peer_id)
	sp.set_multiplayer_authority(peer_id)

	# Выбор точки спавна
	var spawn_pos: Vector3 = Vector3(-235.2, 88.7, -215.6)
	var spawn_nodes := spawn_points_root.get_children() if spawn_points_root else []
	if not spawn_nodes.is_empty():
		var idx: int = (peer_id - 1) % spawn_nodes.size()
		spawn_pos = (spawn_nodes[idx] as Node3D).global_position

	sp.position = spawn_pos
	add_child(sp, true)

	if peer_id == multiplayer.get_unique_id() or not multiplayer.has_multiplayer_peer():
		if pause_menu:
			pause_menu.set_target_player(sp)

@rpc("any_peer", "call_local", "reliable")
func _notify_ready_to_server() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	ready_peers[peer_id] = true
	_spawn_spider_player(peer_id)

func _on_player_disconnected(peer_id: int) -> void:
	var p := get_node_or_null(str(peer_id))
	if p:
		p.queue_free()
