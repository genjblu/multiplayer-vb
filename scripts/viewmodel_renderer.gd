class_name ViewmodelRenderer
extends SubViewportContainer

const VIEWMODEL_LAYER: int = 20  # номер слоя 1..20

var weapon_root: Node = null
var viewport: SubViewport
var weapon_cam: Camera3D
var sun_light: DirectionalLight3D
var fill_light: DirectionalLight3D

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
	weapon_cam.near = 0.05
	weapon_cam.far = 100.0
	#weapon_cam.environment = _make_environment()
	viewport.add_child(weapon_cam)
	weapon_cam.current = true

	# 1. Основной свет (солнце), с динамическими тенями и рельефом
	sun_light = DirectionalLight3D.new()
	sun_light.light_cull_mask = 1 << (VIEWMODEL_LAYER - 1)  # слой 20
	sun_light.shadow_enabled = true
	sun_light.shadow_caster_mask = 1 << (VIEWMODEL_LAYER - 1)
	sun_light.shadow_bias = 0.01
	sun_light.shadow_normal_bias = 1.0
	sun_light.directional_shadow_split_1 = 0.05
	sun_light.directional_shadow_max_distance = 10.0
	sun_light.light_energy = 1.2
	viewport.add_child(sun_light)

	# 2. Мягкий заполняющий свет, чтобы теневые грани не были чёрными
	fill_light = DirectionalLight3D.new()
	fill_light.light_cull_mask = 1 << (VIEWMODEL_LAYER - 1)
	fill_light.shadow_enabled = false
	fill_light.light_energy = 0.35
	fill_light.rotation_degrees = Vector3(-60, 45, 0)
	weapon_cam.add_child(fill_light)

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

	# Синхронизируем направление основного света с солнцем в сцене
	if is_instance_valid(sun_light):
		var dir_lights = get_tree().get_nodes_in_group("directional_lights")
		if dir_lights.size() > 0 and dir_lights[0] is DirectionalLight3D:
			var scene_sun: DirectionalLight3D = dir_lights[0]
			sun_light.global_transform.basis = scene_sun.global_transform.basis
			sun_light.light_color = scene_sun.light_color
			sun_light.light_energy = scene_sun.light_energy
			sun_light.shadow_enabled = scene_sun.shadow_enabled
		else:
			sun_light.rotation_degrees = Vector3(-45, -30, 0)

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
	else:
		env = Environment.new()

	# Используем цвет неба / эмбиента из сцены, но мягкий, чтобы был контраст между светом и тенью
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.25, 0.28)
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if env.sky != null else Environment.REFLECTION_SOURCE_DISABLED

	# Прозрачный фон
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
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
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

# Новые узлы оружия, созданные во время игры, тоже получают слой
func _on_node_added(node: Node) -> void:
	if is_instance_valid(weapon_root) and weapon_root.is_ancestor_of(node):
		_apply_layer(node)
