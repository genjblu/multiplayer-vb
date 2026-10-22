class_name TargetDummy
extends StaticBody3D

signal target_hit(damage: int, is_headshot: bool)
signal target_down

@export var max_health: int = 100
@export var is_moving: bool = false
@export var move_distance: float = 6.0
@export var move_speed: float = 2.5
@export var auto_reset: bool = true
@export var reset_delay: float = 2.0
@export var knock_down_on_kill: bool = true

var health: int = 100
var is_down: bool = false
var origin_pos: Vector3
var move_dir: float = 1.0

@onready var plate: Node3D = $Pivot/Plate
@onready var pivot: Node3D = $Pivot
@onready var head_marker: Marker3D = get_node_or_null("Pivot/HeadMarker")

var _tween: Tween = null
var _orig_rotation: Vector3

func _ready() -> void:
	health = max_health
	origin_pos = position
	if pivot:
		_orig_rotation = pivot.rotation
	add_to_group("targets")

func _process(delta: float) -> void:
	if is_moving and not is_down:
		position.x += move_dir * move_speed * delta
		if abs(position.x - origin_pos.x) >= move_distance * 0.5:
			move_dir *= -1.0

func take_damage(amount: int, attacker_id: int = 1, weapon_name: String = "", is_headshot: bool = false) -> void:
	if is_down:
		return

	health -= amount
	target_hit.emit(amount, is_headshot)
	_spawn_damage_indicator(amount, is_headshot)
	_flash_effect(is_headshot)

	if health <= 0 and knock_down_on_kill:
		knock_down()
	else:
		_wobble_animation()

func _wobble_animation() -> void:
	if not pivot or is_down:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	pivot.rotation.x = _orig_rotation.x + deg_to_rad(-12.0)
	_tween.tween_property(pivot, "rotation:x", _orig_rotation.x, 0.4)

func knock_down() -> void:
	if is_down:
		return
	is_down = true
	target_down.emit()

	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(pivot, "rotation:x", _orig_rotation.x + deg_to_rad(-88.0), 0.35)

	if auto_reset:
		get_tree().create_timer(reset_delay).timeout.connect(reset_target)

func reset_target() -> void:
	if not is_instance_valid(self) or not is_down:
		return
	health = max_health
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	_tween.tween_property(pivot, "rotation:x", _orig_rotation.x, 0.45)
	await _tween.finished
	is_down = false

func _flash_effect(is_headshot: bool) -> void:
	if not plate:
		return
	var mesh_inst: MeshInstance3D = plate.get_node_or_null("Mesh") as MeshInstance3D
	if not mesh_inst:
		for child in plate.get_children():
			if child is MeshInstance3D:
				mesh_inst = child
				break
	if not mesh_inst:
		return

	var orig_mat = mesh_inst.get_surface_override_material(0)
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.2, 0.2) if is_headshot else Color(1.0, 0.8, 0.2)
	flash_mat.emission_enabled = true
	flash_mat.emission = flash_mat.albedo_color
	flash_mat.emission_energy_multiplier = 2.0
	mesh_inst.set_surface_override_material(0, flash_mat)

	var tw := mesh_inst.create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(func():
		if is_instance_valid(mesh_inst):
			mesh_inst.set_surface_override_material(0, orig_mat)
	)

func _spawn_damage_indicator(amount: int, is_headshot: bool) -> void:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.text = ("🎯 " if is_headshot else "") + str(amount)
	label.modulate = Color(1.0, 0.25, 0.2) if is_headshot else Color(1.0, 0.9, 0.3)
	label.font_size = 48 if is_headshot else 36
	label.outline_size = 10
	label.outline_modulate = Color.BLACK
	add_child(label)

	var spawn_y := 1.8 if is_headshot else 1.2
	label.position = Vector3(randf_range(-0.2, 0.2), spawn_y, 0.1)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(label, "position:y", spawn_y + 0.8, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tw.chain().tween_callback(label.queue_free)
