class_name Scoreboard
extends CenterContainer

var pinned: bool = false  # включается кнопкой на телефоне
var panel: PanelContainer
var grid: GridContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	grid = GridContainer.new()
	grid.columns = 3
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 32)
	panel.add_child(grid)
	GameStats.stats_changed.connect(_refresh)
	_refresh()

func _process(_delta: float) -> void:
	visible = pinned or Input.is_key_pressed(KEY_TAB)

func _refresh() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	_add_cell("Ник", Color(0.7, 0.7, 0.7))
	_add_cell("Убийства", Color(0.7, 0.7, 0.7))
	_add_cell("Смерти", Color(0.7, 0.7, 0.7))
	var ids: Array = GameStats.players.keys()
	ids.sort_custom(func(a, b): return GameStats.players[a]["kills"] > GameStats.players[b]["kills"])
	var my_id: int = multiplayer.get_unique_id()
	for id in ids:
		var p: Dictionary = GameStats.players[id]
		var color := Color(1, 0.9, 0.3) if id == my_id else Color(1, 1, 1)
		_add_cell(str(p["name"]), color)
		_add_cell(str(p["kills"]), color)
		_add_cell(str(p["deaths"]), color)

func _add_cell(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	grid.add_child(l)
