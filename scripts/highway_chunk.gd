class_name HighwayChunk
extends Node3D

const CHUNK_LENGTH: float = 100.0
const ROAD_WIDTH: float = 26.0

var chunk_index: int = 0

# Общие статические материалы для максимальной производительности
static var mat_asphalt: StandardMaterial3D = null
static var mat_lane_stripe: StandardMaterial3D = null
static var mat_guardrail: StandardMaterial3D = null
static var mat_neon_rail: StandardMaterial3D = null
static var mat_concrete_barrier: StandardMaterial3D = null
static var mat_ramp: StandardMaterial3D = null
static var mat_ramp_arrow: StandardMaterial3D = null
static var mat_wreck: StandardMaterial3D = null

static func _init_materials() -> void:
	if mat_asphalt != null:
		return
	
	mat_asphalt = StandardMaterial3D.new()
	mat_asphalt.albedo_color = Color(0.13, 0.14, 0.16)
	mat_asphalt.roughness = 0.85

	mat_lane_stripe = StandardMaterial3D.new()
	mat_lane_stripe.albedo_color = Color(0.9, 0.85, 0.3)
	mat_lane_stripe.emission_enabled = true
	mat_lane_stripe.emission = Color(0.9, 0.8, 0.2)
	mat_lane_stripe.emission_energy_multiplier = 0.8

	mat_guardrail = StandardMaterial3D.new()
	mat_guardrail.albedo_color = Color(0.25, 0.28, 0.32)
	mat_guardrail.metallic = 0.8
	mat_guardrail.roughness = 0.4

	mat_neon_rail = StandardMaterial3D.new()
	mat_neon_rail.albedo_color = Color(0.1, 0.8, 1.0)
	mat_neon_rail.emission_enabled = true
	mat_neon_rail.emission = Color(0.1, 0.8, 1.0)
	mat_neon_rail.emission_energy_multiplier = 3.0

	mat_concrete_barrier = StandardMaterial3D.new()
	mat_concrete_barrier.albedo_color = Color(0.4, 0.4, 0.42)
	mat_concrete_barrier.roughness = 0.9

	mat_ramp = StandardMaterial3D.new()
	mat_ramp.albedo_color = Color(0.2, 0.22, 0.26)
	mat_ramp.metallic = 0.5
	mat_ramp.roughness = 0.5

	mat_ramp_arrow = StandardMaterial3D.new()
	mat_ramp_arrow.albedo_color = Color(1.0, 0.55, 0.05)
	mat_ramp_arrow.emission_enabled = true
	mat_ramp_arrow.emission = Color(1.0, 0.55, 0.05)
	mat_ramp_arrow.emission_energy_multiplier = 4.0

	mat_wreck = StandardMaterial3D.new()
	mat_wreck.albedo_color = Color(0.08, 0.08, 0.09)
	mat_wreck.roughness = 0.95

func setup_chunk(index: int, seed_val: int) -> void:
	_init_materials()
	chunk_index = index
	position = Vector3(0, 0, -float(index) * CHUNK_LENGTH)

	_build_road_and_rails()

	# Стартовый чанк (индекс 0) делаем чистым без препятствий для разгона
	if index > 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val + index * 9973
		_generate_features(rng)

func _build_road_and_rails() -> void:
	# 1. Дорожное полотно с физической коллизией
	var road_body := StaticBody3D.new()
	road_body.name = "RoadBody"
	add_child(road_body)

	var road_col := CollisionShape3D.new()
	var road_box_shape := BoxShape3D.new()
	road_box_shape.size = Vector3(ROAD_WIDTH, 1.0, CHUNK_LENGTH)
	road_col.shape = road_box_shape
	road_col.position = Vector3(0, -0.5, -CHUNK_LENGTH * 0.5)
	road_body.add_child(road_col)

	var road_mesh_inst := MeshInstance3D.new()
	var road_box := BoxMesh.new()
	road_box.size = Vector3(ROAD_WIDTH, 1.0, CHUNK_LENGTH)
	road_box.material = mat_asphalt
	road_mesh_inst.mesh = road_box
	road_mesh_inst.position = road_col.position
	add_child(road_mesh_inst)

	# 2. Разметка полос (3 линии для 4 полос)
	var lane_xs = [-6.0, 0.0, 6.0]
	for lx in lane_xs:
		# Пунктирная линия из 10 сегментов
		for seg in range(10):
			var stripe := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.25, 0.02, 5.0)
			sm.material = mat_lane_stripe
			stripe.mesh = sm
			stripe.position = Vector3(lx, 0.02, -float(seg) * 10.0 - 5.0)
			add_child(stripe)

	# 3. Боковые отбойники (слева и справа)
	_build_guardrail(-ROAD_WIDTH * 0.5 + 0.35, true)
	_build_guardrail(ROAD_WIDTH * 0.5 - 0.35, false)

func _build_guardrail(x_pos: float, is_left: bool) -> void:
	var rail_body := StaticBody3D.new()
	rail_body.name = "Guardrail_" + ("L" if is_left else "R")
	add_child(rail_body)

	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(0.7, 1.6, CHUNK_LENGTH)
	col.shape = col_shape
	col.position = Vector3(x_pos, 0.8, -CHUNK_LENGTH * 0.5)
	rail_body.add_child(col)

	var rail_mesh := MeshInstance3D.new()
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(0.6, 1.4, CHUNK_LENGTH)
	b_mesh.material = mat_guardrail
	rail_mesh.mesh = b_mesh
	rail_mesh.position = Vector3(x_pos, 0.7, -CHUNK_LENGTH * 0.5)
	add_child(rail_mesh)

	# Неоновая световая полоса на верхушке отбойника
	var neon_mesh := MeshInstance3D.new()
	var n_box := BoxMesh.new()
	n_box.size = Vector3(0.15, 0.15, CHUNK_LENGTH)
	n_box.material = mat_neon_rail
	neon_mesh.mesh = n_box
	neon_mesh.position = Vector3(x_pos, 1.45, -CHUNK_LENGTH * 0.5)
	add_child(neon_mesh)

func _generate_features(rng: RandomNumberGenerator) -> void:
	# Кибер-арка над дорогой (каждые 3-4 чанка)
	if chunk_index % 3 == 0:
		_build_cyber_arch()

	# Трамплин с шансом 40%
	var has_ramp := rng.randf() < 0.40
	if has_ramp:
		var ramp_x: float = float([-6.0, 0.0, 6.0][rng.randi_range(0, 2)])
		var ramp_z := -rng.randf_range(25.0, 75.0)
		_build_jump_ramp(ramp_x, ramp_z)

	# Препятствия (блоки, остовы машин)
	var num_obstacles := rng.randi_range(1, 3)
	for i in range(num_obstacles):
		var lane_x: float = float([-8.0, -4.0, 0.0, 4.0, 8.0][rng.randi_range(0, 4)])
		var obs_z := -rng.randf_range(15.0, 85.0)
		var obs_type := rng.randi_range(0, 2)
		if obs_type == 0:
			_build_concrete_barrier(lane_x, obs_z)
		elif obs_type == 1:
			_build_wrecked_car(lane_x, obs_z, rng.randf_range(-0.5, 0.5))
		else:
			_build_hazard_barrels(lane_x, obs_z)

func _build_jump_ramp(x_pos: float, z_pos: float) -> void:
	var ramp_body := StaticBody3D.new()
	ramp_body.name = "JumpRamp"
	ramp_body.position = Vector3(x_pos, 0, z_pos)
	add_child(ramp_body)

	# Наклонный трамплин: угол подъема ~18 градусов
	var ramp_len: float = 8.0
	var ramp_height: float = 2.2
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(4.8, 0.4, ramp_len)
	col.shape = box_shape
	col.position = Vector3(0, ramp_height * 0.5, -ramp_len * 0.5)
	col.rotation_degrees = Vector3(15.0, 0, 0)
	ramp_body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.8, 0.4, ramp_len)
	bm.material = mat_ramp
	mesh_inst.mesh = bm
	mesh_inst.position = col.position
	mesh_inst.rotation_degrees = col.rotation_degrees
	ramp_body.add_child(mesh_inst)

	# Светящаяся стрелка ускорения на трамплине
	var arrow := MeshInstance3D.new()
	var arrow_bm := BoxMesh.new()
	arrow_bm.size = Vector3(1.6, 0.05, 3.5)
	arrow_bm.material = mat_ramp_arrow
	arrow.mesh = arrow_bm
	arrow.position = Vector3(0, ramp_height * 0.5 + 0.25, -ramp_len * 0.5)
	arrow.rotation_degrees = Vector3(15.0, 0, 0)
	ramp_body.add_child(arrow)

func _build_concrete_barrier(x_pos: float, z_pos: float) -> void:
	var body := StaticBody3D.new()
	body.name = "ConcreteBarrier"
	body.position = Vector3(x_pos, 0, z_pos)
	add_child(body)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 1.2, 1.0)
	col.shape = box
	col.position = Vector3(0, 0.6, 0)
	body.add_child(col)

	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.2, 1.2, 1.0)
	bm.material = mat_concrete_barrier
	m.mesh = bm
	m.position = col.position
	body.add_child(m)

func _build_wrecked_car(x_pos: float, z_pos: float, rot_y: float) -> void:
	var body := StaticBody3D.new()
	body.name = "WreckedCar"
	body.position = Vector3(x_pos, 0, z_pos)
	body.rotation = Vector3(0, rot_y, 0)
	add_child(body)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.2, 4.2)
	col.shape = box
	col.position = Vector3(0, 0.6, 0)
	body.add_child(col)

	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.1, 1.0, 4.0)
	bm.material = mat_wreck
	m.mesh = bm
	m.position = col.position
	body.add_child(m)

	# Дым от горящего остова
	var smoke := CPUParticles3D.new()
	smoke.position = Vector3(0, 1.1, 0)
	smoke.amount = 20
	smoke.lifetime = 1.0
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 20.0
	smoke.initial_velocity_min = 1.5
	smoke.initial_velocity_max = 3.0
	smoke.gravity = Vector3(0, 1.0, 0)
	var bm_part := BoxMesh.new()
	bm_part.size = Vector3(0.4, 0.4, 0.4)
	var mat_sm := StandardMaterial3D.new()
	mat_sm.albedo_color = Color(0.1, 0.1, 0.1, 0.7)
	mat_sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm_part.material = mat_sm
	smoke.mesh = bm_part
	body.add_child(smoke)

func _build_hazard_barrels(x_pos: float, z_pos: float) -> void:
	var body := StaticBody3D.new()
	body.name = "HazardBarrels"
	body.position = Vector3(x_pos, 0, z_pos)
	add_child(body)

	var offsets = [Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0), Vector3(0, 0, 0.7)]
	for off in offsets:
		var col := CollisionShape3D.new()
		var cyl_col := CylinderShape3D.new()
		cyl_col.radius = 0.45
		cyl_col.height = 1.1
		col.shape = cyl_col
		col.position = off + Vector3(0, 0.55, 0)
		body.add_child(col)

		var m := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.45
		bm.bottom_radius = 0.45
		bm.height = 1.1
		var b_mat := StandardMaterial3D.new()
		b_mat.albedo_color = Color(0.9, 0.2, 0.1) # Red explosive barrels
		b_mat.metallic = 0.4
		b_mat.roughness = 0.5
		bm.material = b_mat
		m.mesh = bm
		m.position = col.position
		body.add_child(m)

func _build_cyber_arch() -> void:
	var arch := Node3D.new()
	arch.name = "CyberArch"
	arch.position = Vector3(0, 0, -CHUNK_LENGTH * 0.5)
	add_child(arch)

	# Левая и правая колонны
	var bm_post := BoxMesh.new()
	bm_post.size = Vector3(1.2, 8.0, 1.2)
	bm_post.material = mat_guardrail

	var post_l := MeshInstance3D.new()
	post_l.mesh = bm_post
	post_l.position = Vector3(-ROAD_WIDTH * 0.5 - 0.2, 4.0, 0)
	arch.add_child(post_l)

	var post_r := MeshInstance3D.new()
	post_r.mesh = bm_post
	post_r.position = Vector3(ROAD_WIDTH * 0.5 + 0.2, 4.0, 0)
	arch.add_child(post_r)

	# Верхняя перекладина
	var bm_beam := BoxMesh.new()
	bm_beam.size = Vector3(ROAD_WIDTH + 2.0, 1.4, 1.2)
	bm_beam.material = mat_guardrail

	var beam := MeshInstance3D.new()
	beam.mesh = bm_beam
	beam.position = Vector3(0, 8.0, 0)
	arch.add_child(beam)

	# Неоновый дисплей / вывеска
	var bm_sign := BoxMesh.new()
	bm_sign.size = Vector3(12.0, 1.0, 0.15)
	bm_sign.material = mat_neon_rail
	var sign_m := MeshInstance3D.new()
	sign_m.mesh = bm_sign
	sign_m.position = Vector3(0, 8.0, -0.6)
	arch.add_child(sign_m)
