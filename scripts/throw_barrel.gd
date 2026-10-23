class_name ThrowBarrel
extends RigidBody3D

signal exploded(pos: Vector3, radius: float, damage: int)

@export var max_health: int = 50
@export var damage: int = 70
@export var explosion_radius: float = 6.0

var health: int = 50
var is_thrown: bool = false
var thrown_by_peer: int = 0
var is_exploded: bool = false

@onready var mesh_inst: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("throwable_objects")
	add_to_group("explosives")
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

func launch(direction: Vector3, speed: float, thrower_id: int) -> void:
	is_thrown = true
	thrown_by_peer = thrower_id
	freeze = false
	linear_velocity = direction.normalized() * speed
	angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))

func _on_body_entered(body: Node) -> void:
	if not is_thrown or is_exploded:
		return
	# Взрыв при сильном ударе после броска
	if linear_velocity.length() > 12.0 or body.is_in_group("players") or body is CharacterBody3D:
		explode()

func take_damage(dmg: int, attacker_id: int = 0, _weapon: String = "") -> void:
	if is_exploded:
		return
	health -= dmg
	if health <= 0:
		thrown_by_peer = attacker_id
		explode()

func explode() -> void:
	if is_exploded:
		return
	is_exploded = true
	exploded.emit(global_position, explosion_radius, damage)

	# 1. Звук взрыва
	var sound := AudioStreamPlayer3D.new()
	sound.stream = SoundFX.get_car_explosion()
	sound.global_position = global_position
	sound.max_distance = 65.0
	get_parent().add_child(sound)
	sound.play()
	sound.finished.connect(sound.queue_free)

	# 2. Визуальный взрыв
	_spawn_explosion_particles()

	# 3. Нанесение урона в радиусе
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = explosion_radius
	query.shape = sphere
	query.transform = global_transform
	query.collide_with_bodies = true

	var results := space.intersect_shape(query, 16)
	for res in results:
		var collider = res.collider
		if collider and collider != self:
			var dist: float = global_position.distance_to(collider.global_position)
			var falloff: float = clampf(1.0 - (dist / explosion_radius), 0.2, 1.0)
			var actual_damage: int = int(damage * falloff)

			if collider.has_method("take_damage"):
				collider.take_damage(actual_damage, thrown_by_peer, "Паутинный бросок")

			# Импульс от взрыва
			if collider is RigidBody3D:
				var push_dir: Vector3 = (collider.global_position - global_position).normalized()
				collider.apply_central_impulse(push_dir * 30.0 * falloff)
			elif collider is CharacterBody3D and "velocity" in collider:
				var push_dir: Vector3 = (collider.global_position - global_position).normalized()
				collider.velocity += push_dir * 24.0 * falloff + Vector3.UP * 8.0

	visible = false
	collision_shape.set_deferred("disabled", true)
	await get_tree().create_timer(1.5).timeout
	queue_free()

func _spawn_explosion_particles() -> void:
	var cpu := CPUParticles3D.new()
	cpu.emitting = false
	cpu.one_shot = true
	cpu.explosiveness = 0.95
	cpu.amount = 45
	cpu.lifetime = 0.8
	cpu.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cpu.emission_sphere_radius = 0.6
	cpu.direction = Vector3.UP
	cpu.spread = 180.0
	cpu.initial_velocity_min = 12.0
	cpu.initial_velocity_max = 24.0
	cpu.scale_amount_min = 0.3
	cpu.scale_amount_max = 0.8
	cpu.color = Color(1.0, 0.45, 0.1, 1.0)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.5, 0.08, 1.0)
	var mesh := BoxMesh.new()
	mesh.material = mat
	mesh.size = Vector3(0.25, 0.25, 0.25)
	cpu.mesh = mesh

	get_parent().add_child(cpu)
	cpu.global_position = global_position
	cpu.emitting = true
	var tw := cpu.create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(cpu.queue_free)
