extends Node3D

@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@onready var spawn_points: Node3D = $SpawnPoints
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner

func _ready() -> void:
	player_spawner.add_spawnable_scene("res://scenes/player.tscn")

	if NetworkManager:
		NetworkManager.player_connected.connect(_spawn_player)
		NetworkManager.player_disconnected.connect(_remove_player)

	if multiplayer.is_server():
		_spawn_player(1)

func _spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if has_node(str(peer_id)):
		return

	var player_instance = player_scene.instantiate()
	player_instance.name = str(peer_id)

	# 1. Устанавливаем позицию ДО добавления в дерево
	var points = spawn_points.get_children()
	if points.size() > 0:
		var random_point: Marker3D = points.pick_random()
		player_instance.position = random_point.global_position
	else:
		player_instance.position = Vector3(0, 1, 0)

	# 2. Назначаем сетевой авторитет ДО вызова add_child
	player_instance.set_multiplayer_authority(peer_id)

	# 3. Добавляем в дерево (MultiplayerSpawner синхронизирует узел с клиентами)
	add_child(player_instance, true)

func _remove_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player_node = get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
