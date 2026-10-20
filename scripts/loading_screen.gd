class_name LoadingScreen
extends CanvasLayer

signal loading_completed

var map_data: MapData = null
var anim_progress: float = 0.0
var is_finished: bool = false

var title_lbl: Label
var desc_lbl: Label
var stage_lbl: Label
var progress_bar: ProgressBar
var preview_rect: TextureRect
var bg_draw: Control

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if map_data:
		title_lbl.text = map_data.display_name
		desc_lbl.text = map_data.description
		if map_data.preview_texture:
			preview_rect.texture = map_data.preview_texture

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dark_bg := ColorRect.new()
	dark_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark_bg.color = Color(0.1, 0.11, 0.13, 1.0)
	root.add_child(dark_bg)

	preview_rect = TextureRect.new()
	preview_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview_rect.modulate = Color(0.75, 0.75, 0.75, 0.85)
	root.add_child(preview_rect)

	bg_draw = Control.new()
	bg_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_draw.draw.connect(_on_draw_overlay)
	root.add_child(bg_draw)

	var top_box := VBoxContainer.new()
	top_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_box.offset_left = 60
	top_box.offset_top = 40
	top_box.offset_right = 520
	top_box.offset_bottom = 260
	top_box.add_theme_constant_override("separation", 10)
	root.add_child(top_box)

	title_lbl = Label.new()
	title_lbl.text = "Арена"
	title_lbl.add_theme_font_size_override("font_size", 42)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	top_box.add_child(title_lbl)

	desc_lbl = Label.new()
	desc_lbl.text = "Сетевая локация..."
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 18)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.9))
	top_box.add_child(desc_lbl)

	var bottom_box := VBoxContainer.new()
	bottom_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_box.offset_left = 60
	bottom_box.offset_top = -110
	bottom_box.offset_right = -60
	bottom_box.offset_bottom = -30
	bottom_box.add_theme_constant_override("separation", 8)
	root.add_child(bottom_box)

	stage_lbl = Label.new()
	stage_lbl.text = "Подключение..."
	stage_lbl.add_theme_font_size_override("font_size", 16)
	stage_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.95))
	bottom_box.add_child(stage_lbl)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 18)
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false

	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.05, 0.05, 0.07, 0.85)
	sb_bg.set_corner_radius_all(9)
	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = Color(1.0, 0.62, 0.1, 1.0)
	sb_fill.set_corner_radius_all(9)
	progress_bar.add_theme_stylebox_override("background", sb_bg)
	progress_bar.add_theme_stylebox_override("fill", sb_fill)
	bottom_box.add_child(progress_bar)

func _on_draw_overlay() -> void:
	var sz := bg_draw.get_size()
	var orange := Color(1.0, 0.62, 0.1, 1.0)
	var line_w: float = 8.0

	var p1 := Vector2(sz.x * 0.38, 0)
	var p2 := Vector2(sz.x * 0.22, sz.y * 0.75)
	bg_draw.draw_line(p1, p2, orange, line_w, true)

	var p_horiz_left := Vector2(0, sz.y * 0.75)
	var p_horiz_right := Vector2(sz.x, sz.y * 0.75)
	bg_draw.draw_line(p_horiz_left, p_horiz_right, orange, line_w, true)

func _process(delta: float) -> void:
	if is_finished:
		return

	var net_manager = get_node_or_null("/root/NetworkManager")
	var has_peer: bool = multiplayer.has_multiplayer_peer()
	var is_server: bool = has_peer and multiplayer.is_server()
	var is_offline: bool = not has_peer and (net_manager == null or not net_manager.joined_as_late)
	var is_client_connected: bool = false
	if is_offline:
		is_client_connected = true
	elif net_manager and net_manager.peer:
		is_client_connected = (net_manager.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	elif net_manager and net_manager.joined_as_late:
		is_client_connected = true # При Late-Join клиент открывает карту, а подключение выполняет сцена арены

	# Клиент ждет подтверждения от сервера (только в сетевом режиме)
	if not is_offline and not is_server and not is_client_connected:
		anim_progress = move_toward(anim_progress, 0.85, delta * 0.8)
		progress_bar.value = anim_progress
		stage_lbl.text = tr("CONNECTING_TO_SERVER")
		return

	anim_progress = move_toward(anim_progress, 1.0, delta * 2.2)
	progress_bar.value = anim_progress

	if anim_progress < 0.95:
		stage_lbl.text = tr("LATE_JOIN_WAITING") if not is_offline else "Загрузка..."
	else:
		stage_lbl.text = tr("STATUS_READY") if tr("STATUS_READY") != "STATUS_READY" else "Ready!"

	if anim_progress >= 1.0 and not is_finished:
		is_finished = true
		await get_tree().create_timer(0.2).timeout
		loading_completed.emit()
		queue_free()
