extends Node3D

@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@onready var spawn_points: Node3D = $SpawnPoints
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner

var team_dialog_canvas: CanvasLayer = null

func _ready() -> void:
	if has_node("FallbackCamera"):
		var cam := get_node("FallbackCamera") as Camera3D
		if cam:
			cam.make_current()

	player_spawner.add_spawnable_scene("res://scenes/player.tscn")

	if NetworkManager:
		NetworkManager.player_disconnected.connect(_remove_player)

	var has_peer: bool = multiplayer.has_multiplayer_peer()
	var is_server: bool = has_peer and multiplayer.is_server()

	# 1. Если это Late-Join клиент — подключаемся к сети и ждем готовности соединения
	if NetworkManager and NetworkManager.joined_as_late and not is_server:
		_handle_late_join_flow()
		return

	# 2. Если игра началась штатно из лобби:
	if is_server:
		# Хост спавнит себя
		_spawn_player(1)
	elif has_peer:
		# Клиент рапортует хосту, что сцена загружена
		_notify_ready_to_server.rpc_id(1)

func _handle_late_join_flow() -> void:
	if not multiplayer.has_multiplayer_peer():
		if NetworkManager.pending_ip.is_empty():
			_show_late_join_error(tr("LATE_JOIN_FAILED"))
			return
		var err := NetworkManager.join_game(NetworkManager.pending_ip, NetworkManager.pending_port)
		if err != OK:
			_show_late_join_error(tr("LATE_JOIN_FAILED"))
			return

	var is_connected: bool = false
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer:
		is_connected = (multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)

	if is_connected:
		_show_late_join_team_selection()
	else:
		_show_late_join_connecting()
		if not multiplayer.connected_to_server.is_connected(_on_late_join_connected):
			multiplayer.connected_to_server.connect(_on_late_join_connected, CONNECT_ONE_SHOT)
		if NetworkManager and not NetworkManager.game_started.is_connected(_on_late_join_connected):
			NetworkManager.game_started.connect(_on_late_join_connected, CONNECT_ONE_SHOT)
		if not multiplayer.connection_failed.is_connected(_on_late_join_failed):
			multiplayer.connection_failed.connect(_on_late_join_failed, CONNECT_ONE_SHOT)
		if not multiplayer.server_disconnected.is_connected(_on_late_join_failed):
			multiplayer.server_disconnected.connect(_on_late_join_failed, CONNECT_ONE_SHOT)

func _on_late_join_connected() -> void:
	# Небольшая задержка, чтобы успели прийти _sync_match_info и GameStats
	await get_tree().create_timer(0.08).timeout
	if not is_instance_valid(self):
		return
	_show_late_join_team_selection()

func _on_late_join_failed() -> void:
	_show_late_join_error(tr("LATE_JOIN_FAILED"))

func _show_late_join_connecting() -> void:
	if team_dialog_canvas and is_instance_valid(team_dialog_canvas):
		team_dialog_canvas.queue_free()

	team_dialog_canvas = CanvasLayer.new()
	team_dialog_canvas.layer = 110
	add_child(team_dialog_canvas)

	var panel := PanelContainer.new()
	panel.theme = UITheme.build()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(380, 160)
	panel.offset_left = -190
	panel.offset_top = -80
	panel.offset_right = 190
	panel.offset_bottom = 80
	team_dialog_canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.theme_type_variation = "HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = tr("CONNECTING_TO_SERVER")
	vbox.add_child(title)

func _show_late_join_error(msg: String) -> void:
	if team_dialog_canvas and is_instance_valid(team_dialog_canvas):
		team_dialog_canvas.queue_free()

	team_dialog_canvas = CanvasLayer.new()
	team_dialog_canvas.layer = 110
	add_child(team_dialog_canvas)

	var panel := PanelContainer.new()
	panel.theme = UITheme.build()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(380, 180)
	panel.offset_left = -190
	panel.offset_top = -90
	panel.offset_right = 190
	panel.offset_bottom = 90
	team_dialog_canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var lbl := Label.new()
	lbl.theme_type_variation = "HeadingLabel"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = msg
	vbox.add_child(lbl)

	var btn := Button.new()
	btn.text = tr("BTN_BACK_TO_MENU")
	btn.pressed.connect(func():
		if NetworkManager:
			NetworkManager.disconnect_peer()
		else:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	vbox.add_child(btn)

@rpc("any_peer", "call_local", "reliable")
func _notify_ready_to_server() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	_spawn_player(peer_id)

func _show_late_join_team_selection() -> void:
	if team_dialog_canvas and is_instance_valid(team_dialog_canvas):
		team_dialog_canvas.queue_free()

	team_dialog_canvas = CanvasLayer.new()
	team_dialog_canvas.layer = 110
	add_child(team_dialog_canvas)

	var panel := PanelContainer.new()
	panel.theme = UITheme.build()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(440, 320)
	panel.offset_left = -220
	panel.offset_top = -160
	panel.offset_right = 220
	panel.offset_bottom = 160
	team_dialog_canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.theme_type_variation = "HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var mode: String = NetworkManager.current_mode if NetworkManager else "ffa"

	if mode == "ffa":
		title.text = tr("CHOOSE_COLOR")
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		vbox.add_child(grid)

		var colors = [
			{"name": tr("COLOR_ORANGE"), "col": Color(1.0, 0.55, 0.1)},
			{"name": tr("COLOR_CYAN"), "col": Color(0.1, 0.85, 0.85)},
			{"name": tr("COLOR_PURPLE"), "col": Color(0.7, 0.3, 0.95)},
			{"name": tr("COLOR_LIME"), "col": Color(0.4, 0.95, 0.2)},
			{"name": tr("COLOR_WHITE"), "col": Color(0.95, 0.95, 0.95)},
			{"name": tr("COLOR_PINK"), "col": Color(1.0, 0.35, 0.7)}
		]
		for item in colors:
			var btn := Button.new()
			btn.text = item["name"]
			btn.custom_minimum_size = Vector2(0, 42)
			var col: Color = item["col"]
			btn.pressed.connect(func(): _confirm_late_join(0, col))
			grid.add_child(btn)
	else:
		title.text = tr("CHOOSE_TEAM")
		var teams = [
			{"id": 1, "name": tr("TEAM_BLUE"), "col": Color(0.2, 0.5, 1.0)},
			{"id": 2, "name": tr("TEAM_RED"), "col": Color(1.0, 0.25, 0.25)},
			{"id": 3, "name": tr("TEAM_GREEN"), "col": Color(0.2, 0.85, 0.3)},
			{"id": 4, "name": tr("TEAM_YELLOW"), "col": Color(1.0, 0.85, 0.15)}
		]
		var count: int = 2
		if mode == "3v3v3": count = 3
		elif mode == "4v4": count = 4
		for i in range(count):
			var t = teams[i]
			var btn := Button.new()
			btn.text = t["name"]
			btn.custom_minimum_size = Vector2(0, 40)
			var tid: int = t["id"]
			var col: Color = t["col"]
			btn.pressed.connect(func(): _confirm_late_join(tid, col))
			vbox.add_child(btn)

func _confirm_late_join(team_id: int, col: Color) -> void:
	if team_dialog_canvas and is_instance_valid(team_dialog_canvas):
		team_dialog_canvas.queue_free()
		team_dialog_canvas = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if not multiplayer.has_multiplayer_peer():
		return
	var my_id := multiplayer.get_unique_id()
	if NetworkManager:
		NetworkManager.request_late_spawn.rpc_id(1, team_id, col)
	else:
		request_late_spawn.rpc_id(1, my_id, team_id, col)

@rpc("any_peer", "call_local", "reliable")
func request_late_spawn(target_peer_id: int, team_id: int, col: Color) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if target_peer_id == 0 or sender != 0:
		target_peer_id = sender
	GameStats.set_player_team_and_color(target_peer_id, team_id, col)
	spawn_player_for_peer(target_peer_id)

func spawn_player_for_peer(peer_id: int) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if not has_node(str(peer_id)):
		_spawn_player(peer_id)

	# Отправляем новому игроку данные обо всех уже существующих игроках
	# на случай, если пакеты MultiplayerSpawner были пропущены до входа в арену
	var existing: Array = []
	for child in get_children():
		if child is CharacterBody3D and child.name.is_valid_int():
			var pid: int = child.name.to_int()
			existing.append({
				"id": pid,
				"pos": child.global_position,
				"team": GameStats.get_player_team(pid)
			})
	_sync_existing_players.rpc_id(peer_id, existing)

@rpc("authority", "call_local", "reliable")
func _sync_existing_players(players_data: Array) -> void:
	if multiplayer.is_server():
		return
	for p_info in players_data:
		var pid: int = int(p_info.get("id", 0))
		if pid <= 0:
			continue
		var node_name := str(pid)
		if not has_node(node_name):
			var player_instance = player_scene.instantiate()
			player_instance.name = node_name
			player_instance.position = p_info.get("pos", Vector3.ZERO)
			player_instance.set_multiplayer_authority(pid)
			add_child(player_instance)

func _spawn_player(peer_id: int) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if has_node(str(peer_id)):
		return

	var my_team: int = GameStats.get_player_team(peer_id)
	var player_instance = player_scene.instantiate()
	player_instance.name = str(peer_id)
	player_instance.position = get_spawn_position(my_team)
	player_instance.set_multiplayer_authority(peer_id)
	add_child(player_instance, true)

func get_spawn_position(team_id: int = 0) -> Vector3:
	var team_group: String = "spawns_team_%d" % team_id
	var team_points = get_tree().get_nodes_in_group(team_group)
	if team_points.size() > 0:
		var node = team_points.pick_random()
		if node is Node3D:
			return (node as Node3D).global_position

	if spawn_points:
		var team_node = spawn_points.get_node_or_null("Team_%d" % team_id)
		if team_node and team_node.get_child_count() > 0:
			var pt = team_node.get_children().pick_random()
			if pt is Node3D:
				return pt.global_position

		var general_pts = spawn_points.get_children()
		if general_pts.size() > 0:
			var rand_pt = general_pts.pick_random()
			if rand_pt is Node3D:
				return rand_pt.global_position

	return Vector3(randf_range(-4, 4), 2.0, randf_range(-4, 4))

func _remove_player(peer_id: int) -> void:
	var p = get_node_or_null(str(peer_id))
	if p:
		p.queue_free()
