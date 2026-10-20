class_name ScreenHost
extends MenuScreen

signal host_requested(port: int, room_name: String, map_id: String, mode: String, friendly_fire: bool, publish_online: bool, custom_ip: String, is_private: bool)

var room_edit: LineEdit
var port_edit: LineEdit
var tunnel_edit: LineEdit
var lobby_type_option: OptionButton
var map_option: OptionButton
var mode_option: OptionButton
var ff_checkbox: CheckBox
var online_checkbox: CheckBox
var available_maps: Array[MapData] = []
const MAP_PATHS: Array[String] = [
	"res://maps/default_arena.tres",
	"res://maps/Industrial.tres",
	"res://maps/polygon.tres",
]
func _ready() -> void:
	add_child(_make_label(tr("HOST_TITLE"), "HeadingLabel"))

	room_edit = LineEdit.new()
	room_edit.text = tr("HOST_DEFAULT_ROOM")
	room_edit.max_length = 32
	add_child(_make_row(tr("HOST_ROOM_NAME"), room_edit))

	lobby_type_option = OptionButton.new()
	lobby_type_option.add_item(tr("LOBBY_TYPE_PUBLIC"), 0)
	lobby_type_option.add_item(tr("LOBBY_TYPE_PRIVATE"), 1)
	lobby_type_option.item_selected.connect(func(idx: int):
		if idx == 1: # Private by code
			online_checkbox.button_pressed = true
			online_checkbox.disabled = true
		else:
			online_checkbox.disabled = false
	)
	add_child(_make_row(tr("LOBBY_TYPE"), lobby_type_option))

	port_edit = LineEdit.new()
	port_edit.text = "7777"
	port_edit.max_length = 5
	add_child(_make_row(tr("HOST_PORT"), port_edit))

	GameSettings.ensure_loaded()
	tunnel_edit = LineEdit.new()
	tunnel_edit.text = GameSettings.playit_tunnel_address
	tunnel_edit.placeholder_text = tr("HOST_TUNNEL_PLACEHOLDER")
	tunnel_edit.max_length = 64
	add_child(_make_row(tr("HOST_TUNNEL_ADDR"), tunnel_edit))

	_scan_maps()

	map_option = OptionButton.new()
	for i in range(available_maps.size()):
		map_option.add_item(tr(available_maps[i].display_name), i)
	add_child(_make_row(tr("HOST_MAP"), map_option))

	mode_option = OptionButton.new()
	mode_option.add_item(tr("HOST_MODE_FFA"), 0)
	mode_option.add_item(tr("HOST_MODE_2V2"), 1)
	mode_option.add_item(tr("HOST_MODE_3V3V3"), 2)
	mode_option.add_item(tr("HOST_MODE_4V4"), 3)
	add_child(_make_row(tr("HOST_MODE"), mode_option))

	var chk_box := HBoxContainer.new()
	chk_box.add_theme_constant_override("separation", 8)
	add_child(chk_box)

	online_checkbox = CheckBox.new()
	online_checkbox.text = tr("HOST_PUBLISH_ONLINE")
	online_checkbox.button_pressed = true
	online_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chk_box.add_child(online_checkbox)

	ff_checkbox = CheckBox.new()
	ff_checkbox.text = tr("HOST_FF")
	ff_checkbox.button_pressed = false
	ff_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chk_box.add_child(ff_checkbox)

	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 8)
	add_child(btn_box)

	var b_back := _make_back_button()
	b_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_box.add_child(b_back)

	var b_create := _make_button(tr("HOST_BTN_CREATE"), true)
	b_create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_create.pressed.connect(_on_create_pressed)
	btn_box.add_child(b_create)

func _scan_maps() -> void:
	available_maps.clear()
	for path in MAP_PATHS:
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is MapData:
				available_maps.append(res)

	# Запасной вариант, если ничего не нашлось
	if available_maps.is_empty():
		var def_map := MapData.new()
		def_map.id = "arena"
		def_map.display_name = "MAP_DEFAULT_ARENA"
		def_map.description = "MAP_DEFAULT_DESC"
		def_map.scene_path = "res://scenes/arena.tscn"
		available_maps.append(def_map)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() and tunnel_edit:
		tunnel_edit.text = GameSettings.playit_tunnel_address

func _on_create_pressed() -> void:
	var port := port_edit.text.strip_edges().to_int()
	if port < 1024 or port > 65535:
		status_requested.emit(tr("HOST_ERR_PORT"), true)
		return
	var room := room_edit.text.strip_edges()
	if room.is_empty():
		room = tr("HOST_DEFAULT_ROOM_FALLBACK")
	var selected_map_id: String = "arena"
	if map_option.selected >= 0 and map_option.selected < available_maps.size():
		selected_map_id = available_maps[map_option.selected].id
	var modes := ["ffa", "2v2", "3v3v3", "4v4"]
	var selected_mode: String = modes[mode_option.selected] if mode_option.selected < modes.size() else "ffa"
	var ff: bool = ff_checkbox.button_pressed
	var is_priv: bool = (lobby_type_option.selected == 1)
	var pub_online: bool = online_checkbox.button_pressed or is_priv
	var custom_ip: String = tunnel_edit.text.strip_edges()
	GameSettings.playit_tunnel_address = custom_ip
	GameSettings.save_to_disk()
	host_requested.emit(port, room, selected_map_id, selected_mode, ff, pub_online, custom_ip, is_priv)
