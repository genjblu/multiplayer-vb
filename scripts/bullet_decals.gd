extends Node

# ---------- НАСТРОЙКИ (меняй числа здесь) ----------
const MAX_DECALS := 120                 # сколько декалей держать одновременно
const LIFETIME := 30.0                  # сколько секунд живёт декаль
const DECAL_SIZE := 0.14                # размер в метрах
const SIZE_VARIATION := Vector2(0.8, 1.25)  # случайный разброс размера (мин, макс)
const CUSTOM_TEXTURE_PATH := "res://textures/bullet_hole.png"  # своя текстура (необязательно)

var hole_texture: Texture2D
var _decals: Array[Node3D] = []

func _ready() -> void:
	hole_texture = _make_texture()

# Вызывается стрелком: создаёт декаль у себя и у всех остальных игроков
func spawn_hit(pos: Vector3, normal: Vector3) -> void:
	_spawn_local(pos, normal)
	if multiplayer.has_multiplayer_peer():
		_spawn_remote.rpc(pos, normal)

@rpc("any_peer", "call_remote", "unreliable")
func _spawn_remote(pos: Vector3, normal: Vector3) -> void:
	_spawn_local(pos, normal)

func clear_all() -> void:
	for d in _decals.duplicate():
		_remove(d)

func _spawn_local(pos: Vector3, normal: Vector3) -> void:
	if normal.length() < 0.001:
		return
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	var n: Vector3 = normal.normalized()
	var size_now: float = DECAL_SIZE * randf_range(SIZE_VARIATION.x, SIZE_VARIATION.y)
	var node: Node3D
	var offset: float = 0.0

	if RenderingServer.get_current_rendering_method() == "forward_plus":
		var d := Decal.new()
		d.texture_albedo = hole_texture
		d.size = Vector3(size_now, 0.2, size_now)
		d.cull_mask = 1
		node = d
	else:
		# Запасной вариант без Decal: плоский квадрат чуть над поверхностью
		var m := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(size_now, size_now)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = hole_texture
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		plane.material = mat
		m.mesh = plane
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node = m
		offset = 0.004

	parent.add_child(node)
	var b: Basis = _basis_from_normal(n).rotated(n, randf() * TAU)
	node.global_transform = Transform3D(b, pos + n * offset)

	_decals.append(node)
	while _decals.size() > MAX_DECALS:
		_remove(_decals[0])
	var tw := node.create_tween()
	tw.tween_interval(LIFETIME)
	tw.tween_callback(func(): _remove(node))

func _remove(node: Node3D) -> void:
	_decals.erase(node)
	if is_instance_valid(node):
		node.queue_free()

# Базис, у которого ось Y направлена вдоль нормали поверхности
func _basis_from_normal(n: Vector3) -> Basis:
	var ref: Vector3 = Vector3.RIGHT if absf(n.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x: Vector3 = ref.cross(n).normalized()
	var z: Vector3 = x.cross(n).normalized()
	return Basis(x, n, z)

func _make_texture() -> Texture2D:
	if ResourceLoader.exists(CUSTOM_TEXTURE_PATH):
		var custom := load(CUSTOM_TEXTURE_PATH) as Texture2D
		if custom:
			return custom
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([
		Color(0.02, 0.02, 0.02, 0.95),
		Color(0.05, 0.05, 0.05, 0.8),
		Color(0.05, 0.05, 0.05, 0.0)
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t
