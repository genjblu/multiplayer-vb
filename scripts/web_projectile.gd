class_name WebProjectile
extends Node3D

@export var speed: float = 75.0
@export var damage: int = 15
@export var web_potency: float = 25.0 # Процент связывания за попадание
@export var max_lifetime: float = 2.5

var velocity: Vector3 = Vector3.ZERO
var shooter_id: int = 0
var lifetime: float = 0.0

@onready var trail_mesh: MeshInstance3D = get_node_or_null("Trail")

func init_projectile(pos: Vector3, dir: Vector3, shooter: int) -> void:
	global_position = pos
	velocity = dir.normalized() * speed
	shooter_id = shooter
	look_at(global_position + dir, Vector3.UP)

func _physics_process(delta: float) -> void:
	lifetime += delta
	if lifetime >= max_lifetime:
		queue_free()
		return

	var step := velocity * delta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.from = global_position
	query.to = global_position + step
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := space.intersect_ray(query)
	if hit:
		_on_hit(hit)
	else:
		global_position += step

func _on_hit(hit: Dictionary) -> void:
	var collider = hit.collider
	var hit_pos: Vector3 = hit.position
	var hit_norm: Vector3 = hit.normal

	# Звук липкого шлепка паутины
	var sound := AudioStreamPlayer3D.new()
	sound.stream = SoundFX.get_web_hit()
	sound.global_position = hit_pos
	sound.max_distance = 45.0
	get_parent().add_child(sound)
	sound.play()
	sound.finished.connect(sound.queue_free)

	# Нанесение урона и накладывание паутины
	if collider and collider != self:
		if collider.has_method("apply_web_shot"):
			collider.apply_web_shot(web_potency, damage, shooter_id)
		elif collider.has_method("take_damage"):
			collider.take_damage(damage, shooter_id, "Выстрел паутиной")

	# Частицы паутины при ударе
	_spawn_web_splat(hit_pos, hit_norm)
	queue_free()

func _spawn_web_splat(pos: Vector3, norm: Vector3) -> void:
	var cpu := CPUParticles3D.new()
	cpu.emitting = false
	cpu.one_shot = true
	cpu.explosiveness = 0.95
	cpu.amount = 14
	cpu.lifetime = 0.4
	cpu.direction = norm
	cpu.spread = 65.0
	cpu.initial_velocity_min = 4.0
	cpu.initial_velocity_max = 9.0
	cpu.scale_amount_min = 0.08
	cpu.scale_amount_max = 0.2
	cpu.color = Color(0.96, 0.96, 1.0, 0.95)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.95, 1.0, 0.95)
	var sphere := SphereMesh.new()
	sphere.material = mat
	sphere.radius = 0.06
	sphere.height = 0.12
	cpu.mesh = sphere

	get_parent().add_child(cpu)
	cpu.global_position = pos
	cpu.emitting = true
	var tw := cpu.create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(cpu.queue_free)
