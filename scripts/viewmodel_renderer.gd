class_name ViewmodelRenderer
extends SubViewportContainer

const VIEWMODEL_LAYER: int = 20  # номер слоя 1..20

var weapon_root: Node = null
var viewport: SubViewport
var weapon_cam: Camera3D

func _ready() -> void:
	process_priority = 1000  # выполняться после всех остальных, чтобы не было дрожания
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = false  # общий мир с основной камерой
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	if OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]:
		viewport.msaa_3d = Viewport.MSAA_DISABLED
	else:
		viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)

	weapon_cam = Camera3D.new()
	weapon_cam.cull_mask = 0
	weapon_cam.set_cull_mask_value(VIEWMODEL_LAYER, true)
	weapon_cam.near = 0.01
	weapon_cam.far = 10.0
	weapon_cam.environment = _make_environment()
	viewport.add_child(weapon_cam)
	weapon_cam.current = true
	
	var fill := DirectionalLight3D.new()
	fill.light_cull_mask = 1 << (VIEWMODEL_LAYER - 1)  # светит только на слой оружия
	fill.shadow_enabled = false
	fill.light_energy = 0.8
	fill.rotation_degrees = Vector3(-45, 30, 0)
	weapon_cam.add_child(fill)

func setup(root: Node) -> void:
	weapon_root = root
	_set_layer_recursive(weapon_root)
	get_tree().node_added.connect(_on_node_added)

func _process(_delta: float) -> void:
	if not is_instance_valid(weapon_cam):
		return
	var main_cam: Camera3D = get_viewport().get_camera_3d()
	if main_cam == null:
		return
	if main_cam.get_cull_mask_value(VIEWMODEL_LAYER):
		main_cam.set_cull_mask_value(VIEWMODEL_LAYER, false)
	weapon_cam.global_transform = main_cam.global_transform
	weapon_cam.fov = main_cam.fov
	weapon_cam.keep_aspect = main_cam.keep_aspect

func _make_environment() -> Environment:
	var main_env: Environment = null
	var main_cam: Camera3D = get_viewport().get_camera_3d()
	if main_cam and main_cam.environment:
		main_env = main_cam.environment
	else:
		var we = get_tree().root.find_child("WorldEnvironment", true, false)
		if we is WorldEnvironment:
			main_env = we.environment

	var env: Environment
	if main_env:
		env = main_env.duplicate()
		var src = env.ambient_light_source
		if src == Environment.AMBIENT_SOURCE_BG or src == Environment.AMBIENT_SOURCE_SKY:
			if env.sky != null:
				env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
				env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
			else:
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				env.ambient_light_color = Color(0.6, 0.6, 0.6)
				env.ambient_light_energy = maxf(env.ambient_light_energy, 0.5)
				env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED

	# Прозрачный фон и никаких тяжёлых эффектов для оружия
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.glow_enabled = false
	env.ssao_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	return env

func _set_layer_recursive(node: Node) -> void:
	_apply_layer(node)
	for child in node.get_children():
		_set_layer_recursive(child)

func _apply_layer(node: Node) -> void:
	var gi := node as GeometryInstance3D
	if gi:
		gi.layers = 0
		gi.set_layer_mask_value(VIEWMODEL_LAYER, true)

# Новые узлы оружия, созданные во время игры, тоже получают слой
func _on_node_added(node: Node) -> void:
	if is_instance_valid(weapon_root) and weapon_root.is_ancestor_of(node):
		_apply_layer(node)
