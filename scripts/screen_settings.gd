class_name ScreenSettings
extends MenuScreen

func _ready() -> void:
	add_child(_make_label("Настройки", "HeadingLabel"))

	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	volume.value_changed.connect(_on_volume_changed)
	add_child(_make_row("Громкость", volume))

	var res_scale := HSlider.new()
	res_scale.min_value = 0.35
	res_scale.max_value = 1.0
	res_scale.step = 0.05
	res_scale.value = get_viewport().scaling_3d_scale
	res_scale.value_changed.connect(_on_scale_changed)
	add_child(_make_row("Разрешение", res_scale))

	var fullscreen := CheckBox.new()
	fullscreen.text = "Полный экран"
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(_on_fullscreen_toggled)
	add_child(fullscreen)

	var vsync := CheckBox.new()
	vsync.text = "Вертикальная синхронизация"
	vsync.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	vsync.toggled.connect(_on_vsync_toggled)
	add_child(vsync)

	add_child(_make_back_button())

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))

func _on_scale_changed(value: float) -> void:
	get_viewport().scaling_3d_scale = value

func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_vsync_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
