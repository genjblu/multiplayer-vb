class_name WeaponView
extends Node3D

@export var muzzle_smoke: GPUParticles3D
# Если пусто, AnimationPlayer ищется среди дочерних узлов
@export var animation_player: AnimationPlayer
@export var cast_shadows: bool = false
## Анимации, которые ждут окончания текущей и запускаются после неё.
## Все остальные запросы во время другой анимации просто пропускаются.
@export var queued_animations: PackedStringArray = []
## Плавный переход между анимациями, секунды (0 = без плавности)
@export var blend_time: float = 0.05
## Запретить стрельбу, пока играет анимация доставания (draw)
@export var block_fire_during_draw: bool = true
@export var ammo_label_3d: Label3D
@export_group("3D Патроны (Ammo 3D)")
@export var ammo_3d_scale: float = 0.0005:
	set(val):
		ammo_3d_scale = val
		if ammo_label_3d and is_instance_valid(ammo_label_3d):
			ammo_label_3d.pixel_size = ammo_3d_scale

var _queued: StringName = &""

func _ready() -> void:
	_setup_smoke()
	if animation_player == null:
		animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ammo_label_3d == null:
		ammo_label_3d = find_child("Label3D", true, false) as Label3D
	if ammo_label_3d == null:
		ammo_label_3d = Label3D.new()
		ammo_label_3d.name = "AutoAmmoLabel3D"
		ammo_label_3d.text = "30/90"
		ammo_label_3d.font_size = 96
		ammo_label_3d.outline_size = 24
		ammo_label_3d.pixel_size = ammo_3d_scale
		ammo_label_3d.position = Vector3(-0.06, 0.05, -0.18)
		ammo_label_3d.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		ammo_label_3d.no_depth_test = true
		ammo_label_3d.shaded = false
		ammo_label_3d.render_priority = 5
		ammo_label_3d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		ammo_label_3d.visible = false
		var visual_parent: Node = null
		for child in get_children():
			if child is Node3D and child != ammo_label_3d:
				visual_parent = child
				break
		if visual_parent == null:
			visual_parent = self
		visual_parent.add_child(ammo_label_3d)
	else:
		if ammo_label_3d.pixel_size > 0.002:
			ammo_label_3d.pixel_size = 0.0005
			ammo_label_3d.font_size = 96
			ammo_label_3d.outline_size = 24
		ammo_label_3d.shaded = false
		ammo_label_3d.no_depth_test = true
		ammo_label_3d.render_priority = 5
		ammo_label_3d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not cast_shadows:
		_disable_shadows(self)
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
		if animation_player.has_animation("draw"):
			_start(&"draw")
		elif animation_player.has_animation("idle"):
			animation_player.play("idle")

func play_reload() -> void:
	if animation_player and animation_player.has_animation(&"reload"):
		_request(&"reload")
	else:
		_procedural_reload()

func _procedural_reload() -> void:
	var tw := create_tween()
	var orig_pos := position
	var dip_pos := orig_pos + Vector3(0.0, -0.12, 0.05)
	tw.tween_property(self, "position", dip_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.3)
	tw.tween_property(self, "position", orig_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func set_ammo_display(current: int, reserve: int) -> void:
	if ammo_label_3d:
		ammo_label_3d.text = "%d/%d" % [current, reserve]

func set_ammo(current: int, reserve: int) -> void:
	set_ammo_display(current, reserve)

func set_ammo_3d_visible(vis: bool) -> void:
	if ammo_label_3d:
		ammo_label_3d.visible = vis

func setup_ammo_3d_params(offset: Vector3, rot_deg: Vector3, font_sz: int, px_scale: float) -> void:
	ammo_3d_scale = px_scale
	if ammo_label_3d:
		ammo_label_3d.position = offset
		ammo_label_3d.rotation_degrees = rot_deg
		ammo_label_3d.font_size = font_sz
		ammo_label_3d.pixel_size = px_scale
		
func _request(anim_name: StringName) -> void:
	if animation_player == null or not animation_player.has_animation(anim_name):
		return
	if _is_busy():
		# Занято: нужные анимации встают в очередь (одна), остальные пропускаются
		if queued_animations.has(String(anim_name)):
			_queued = anim_name
		return
	_start(anim_name)

func _is_busy() -> bool:
	return animation_player.is_playing() and animation_player.current_animation != "idle"

func _start(anim_name: StringName) -> void:
	_queued = &""
	animation_player.play(anim_name, blend_time)

func _on_animation_finished(anim_name: StringName) -> void:
	if _queued != &"" and animation_player.has_animation(_queued):
		_start(_queued)
	elif anim_name != &"idle" and animation_player.has_animation("idle"):
		animation_player.play("idle", blend_time)

func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)
		
		# Можно ли начинать перезарядку прямо сейчас (не играет выстрел или доставание)
func can_start_reload() -> bool:
	if animation_player == null or not animation_player.has_animation("reload"):
		return true
	return not _is_busy()

# Длительность анимации перезарядки в секундах (0, если анимации нет)
func get_reload_duration() -> float:
	if animation_player == null or not animation_player.has_animation("reload"):
		return 0.0
	var anim: Animation = animation_player.get_animation("reload")
	return anim.length / maxf(animation_player.speed_scale, 0.01)

# Можно ли стрелять прямо сейчас
func can_fire() -> bool:
	if not block_fire_during_draw or animation_player == null:
		return true
	return not (animation_player.is_playing() and animation_player.current_animation == "draw")

func play_fire() -> void:
	if animation_player and animation_player.has_animation(&"fire"):
		_request(&"fire")
	else:
		_procedural_kick()
	if muzzle_smoke and not muzzle_smoke.emitting:
		muzzle_smoke.restart()

func _procedural_kick() -> void:
	var tw := create_tween()
	var orig_pos := position
	var kick_offset := Vector3(0.0, 0.02, 0.06)
	tw.tween_property(self, "position", orig_pos + kick_offset, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", orig_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func _setup_smoke() -> void:
	if muzzle_smoke == null:
		return
	muzzle_smoke.amount = 8
	muzzle_smoke.lifetime = 1.0
	muzzle_smoke.one_shot = true
	muzzle_smoke.explosiveness = 1.0
	muzzle_smoke.local_coords = false
	muzzle_smoke.emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, 0.2, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	# Дым растёт со временем
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	# Серый, плавно исчезающий
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([Color(0.75, 0.75, 0.75, 0.5), Color(0.75, 0.75, 0.75, 0.0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	muzzle_smoke.process_material = pm

	# Мягкое круглое пятно
	var soft := Gradient.new()
	soft.offsets = PackedFloat32Array([0.0, 1.0])
	soft.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var soft_tex := GradientTexture2D.new()
	soft_tex.gradient = soft
	soft_tex.width = 64
	soft_tex.height = 64
	soft_tex.fill = GradientTexture2D.FILL_RADIAL
	soft_tex.fill_from = Vector2(0.5, 0.5)
	soft_tex.fill_to = Vector2(1.0, 0.5)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = soft_tex

	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	quad.material = mat
	muzzle_smoke.draw_pass_1 = quad
