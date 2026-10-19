extends SceneTree

# Запуск выделенного сервера 24/7 (Headless Dedicated Server):
# godot --headless -s scripts/dedicated_server.gd --port=7777 --map=Industrial --mode=ffa

var port: int = 7777
var map_id: String = "Industrial"
var mode: String = "ffa"
var room_name: String = "Официальный 24/7 Сервер"

func _init() -> void:
	print("==================================================")
	print("       GODOT FPS DEDICATED SERVER 24/7           ")
	print("==================================================")

	# Парсинг аргументов командной строки
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--map="):
			map_id = arg.trim_prefix("--map=")
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--name="):
			room_name = arg.trim_prefix("--name=")

	print("[DedicatedServer] Config: Port=%d, Map=%s, Mode=%s, Name=%s" % [port, map_id, mode, room_name])

	# Загружаем арену сразу
	var arena_scn := load("res://scenes/arena.tscn") as PackedScene
	if arena_scn:
		var arena := arena_scn.instantiate()
		root.add_child(arena)
		print("[DedicatedServer] Arena scene loaded successfully.")

	# Запускаем сервер через NetworkManager
	var net_manager = root.get_node_or_null("NetworkManager")
	if net_manager:
		var err = net_manager.host_game(port, map_id, mode, false)
		if err == OK:
			print("[DedicatedServer] Server listening on UDP port: ", port)
			net_manager.is_match_running = true

			var online_mgr = root.get_node_or_null("OnlineMatchmaking")
			if online_mgr:
				online_mgr.register_server(room_name, port, map_id, mode, false)
				print("[DedicatedServer] Registered on Master Server.")
		else:
			printerr("[DedicatedServer] Failed to bind port: ", err)
			quit(1)
	else:
		printerr("[DedicatedServer] NetworkManager autoload not found!")
