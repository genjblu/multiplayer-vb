extends Node3D

@export var weapon_data: Array[WeaponData] = []

const STEP := 0.01
const FINE_STEP := 0.002

var cam: Camera3D
var holder: Node3D
var view: Node3D = null
var index: int = 0
var ads: bool = false
var edit_ads: bool = false
var label: Label

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2b2f36")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)

	cam = Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.current = true
	holder = Node3D.new()
	cam.add_child(holder)

	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(16, 16)
	layer.add_child(label)

	_show_weapon(0)

func _show_weapon(i: int) -> void:
	if weapon_data.is_empty():
		label.text = "Заполни Weapon Data в Inspector (перетащи .tres файлы)"
		return
	index = clampi(i, 0, weapon_data.size() - 1)
	if is_instance_valid(view):
		view.queue_free()
		view = null
	var d: WeaponData = weapon_data[index]
	if d != null and d.view_scene != null:
		view = d.view_scene.instantiate() as Node3D
		holder.add_child(view)
		view.position = d.hip_pos
	_update_label()

func _process(delta: float) -> void:
	if weapon_data.is_empty() or not is_instance_valid(view):
		return
	var d: WeaponData = weapon_data[index]
	if d == null:
		return
	var target: Vector3 = d.ads_pos if ads else d.hip_pos
	view.position = view.position.lerp(target, delta * 15.0)
	var target_fov: float = d.ads_fov if ads else 75.0
	cam.fov = lerpf(cam.fov, target_fov, delta * 15.0)

func _unhandled_input(event: InputEvent) -> void:
	if weapon_data.is_empty():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			ads = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_call_view("play_fire")
		return
	if event is InputEventKey and event.pressed:
		var k: int = event.keycode
		if k >= KEY_1 and k <= KEY_9 and not event.echo:
			var n: int = k - KEY_1
			if n < weapon_data.size():
				_show_weapon(n)
		elif k == KEY_F and not event.echo:
			_call_view("play_fire")
		elif k == KEY_R and not event.echo:
			_call_view("play_reload")
		elif k == KEY_TAB and not event.echo:
			edit_ads = not edit_ads
			_update_label()
		elif k == KEY_LEFT:
			_nudge(Vector3.LEFT)
		elif k == KEY_RIGHT:
			_nudge(Vector3.RIGHT)
		elif k == KEY_UP:
			_nudge(Vector3.UP)
		elif k == KEY_DOWN:
			_nudge(Vector3.DOWN)
		elif k == KEY_PAGEUP:
			_nudge(Vector3.FORWARD)
		elif k == KEY_PAGEDOWN:
			_nudge(Vector3.BACK)
		elif (k == KEY_ENTER or k == KEY_KP_ENTER) and not event.echo:
			_save()

func _call_view(method: String) -> void:
	if is_instance_valid(view) and view.has_method(method):
		view.call(method)

func _nudge(dir: Vector3) -> void:
	var d: WeaponData = weapon_data[index]
	if d == null:
		return
	var step := FINE_STEP if Input.is_key_pressed(KEY_SHIFT) else STEP
	if edit_ads:
		d.ads_pos += dir * step
	else:
		d.hip_pos += dir * step
	_update_label()

func _save() -> void:
	var d: WeaponData = weapon_data[index]
	if d == null or d.resource_path == "":
		label.text = "Нельзя сохранить: ресурс не из файла"
		return
	var err := ResourceSaver.save(d, d.resource_path)
	_update_label()
	if err == OK:
		label.text += "\nСОХРАНЕНО в " + d.resource_path
	else:
		label.text += "\nОшибка сохранения: " + str(err)

func _update_label() -> void:
	var d: WeaponData = weapon_data[index]
	if d == null:
		label.text = "Пустой слот в Weapon Data"
		return
	var t := "Оружие %d: %s\n" % [index + 1, d.display_name]
	if edit_ads:
		t += "Редактируется: ПРИЦЕЛИВАНИЕ (ads_pos)\n"
	else:
		t += "Редактируется: ОТ БЕДРА (hip_pos)\n"
	t += "hip_pos = %s\nads_pos = %s\n" % [d.hip_pos, d.ads_pos]
	if d.view_scene == null:
		t += "У этого оружия не задана View Scene\n"
	t += "\n1-9 выбор | F или ЛКМ огонь | R перезарядка | ПКМ прицел | Tab: бедро/прицел"
	t += "\nСтрелки и PgUp/PgDn: сдвиг (Shift = точнее) | Enter: сохранить в .tres"
	label.text = t
