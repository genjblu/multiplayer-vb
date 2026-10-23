class_name CityArena
extends Node3D

@export var player_scene: PackedScene = preload("res://scenes/spider_player.tscn")
@export var barrel_scene: PackedScene = preload("res://scenes/interactive/throw_barrel.tscn")

@onready var city_root: Node3D = $CityModel
@onready var spawn_points_root: Node3D = $SpawnPoints
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var barrels_root: Node3D = $ThrowableBarrels

var pause_menu: Control = null
var is_paused: bool = false
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

	_build_pause_menu()

	var has_peer := multiplayer.has_multiplayer_peer()
	var is_server := has_peer and multiplayer.is_server()

	if not has_peer:
		_spawn_solo_spider()
	elif is_server:
		ready_peers[1] = true
		_spawn_spider_player(1)
	elif has_peer:
		_notify_ready_to_server.rpc_id(1)

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
		Vector3(5, 50.0, 5),
		Vector3(-8, 50.0, -12),
		Vector3(45, 64.0, -78),
		Vector3(-55, 57.0, 68),
		Vector3(105, 77.0, -145),
		Vector3(-85, 44.0, -105),
		Vector3(30, 87.0, 115),
		Vector3(12, 1.5, 20),
		Vector3(-35, 1.5, -25),
		Vector3(75, 1.5, -45)
	]

	for pos in prop_positions:
		var barrel := barrel_scene.instantiate() as RigidBody3D
		barrel.global_position = pos
		barrels_root.add_child(barrel)

func _spawn_solo_spider() -> void:
	_spawn_spider_player(1)

func _spawn_spider_player(peer_id: int) -> void:
	if has_node(str(peer_id)):
		return

	var sp = player_scene.instantiate()
	sp.name = str(peer_id)
	sp.set_multiplayer_authority(peer_id)

	# Выбор точки спавна
	var spawn_pos: Vector3 = Vector3(0, 50.0, 0)
	var spawn_nodes := spawn_points_root.get_children() if spawn_points_root else []
	if not spawn_nodes.is_empty():
		var idx: int = (peer_id - 1) % spawn_nodes.size()
		spawn_pos = (spawn_nodes[idx] as Node3D).global_position

	sp.position = spawn_pos
	add_child(sp, true)

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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	is_paused = not is_paused
	if pause_menu:
		pause_menu.visible = is_paused
		pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP if is_paused else Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_paused else Input.MOUSE_MODE_CAPTURED

func _build_pause_menu() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 120
	add_child(canvas)

	pause_menu = Control.new()
	pause_menu.name = "SpiderPauseMenu"
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	pause_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(pause_menu)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.65)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_menu.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(center)

	var panel := PanelContainer.new()
	panel.theme = UITheme.build()
	panel.custom_minimum_size = Vector2(380, 320)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "ПАУЧИЙ БОЙ (CITY)"
	title.theme_type_variation = "HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(0.9, 0.15, 0.2)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var btn_resume := Button.new()
	btn_resume.text = "Продолжить бой"
	btn_resume.custom_minimum_size = Vector2(0, 42)
	btn_resume.pressed.connect(_toggle_pause)
	vbox.add_child(btn_resume)

	var btn_quit := Button.new()
	btn_quit.text = "Выход в главное меню"
	btn_quit.custom_minimum_size = Vector2(0, 42)
	btn_quit.modulate = Color(1.0, 0.4, 0.4)
	btn_quit.pressed.connect(func():
		var stats = get_node_or_null("/root/GameStats")
		if stats and stats.has_method("reset_stats"):
			stats.reset_stats()
		var lan = get_node_or_null("/root/LanDiscovery")
		if lan and lan.has_method("stop_broadcast"):
			lan.stop_broadcast()
		var net_disconnect = get_node_or_null("/root/NetworkManager")
		if net_disconnect and net_disconnect.has_method("disconnect_peer"):
			net_disconnect.disconnect_peer()
		else:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	vbox.add_child(btn_quit)
