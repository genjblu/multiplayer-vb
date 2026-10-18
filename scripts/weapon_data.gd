class_name WeaponData
extends Resource

@export var display_name: String = "Оружие"

@export_group("Стрельба")
@export var damage: int = 25
@export var pellets: int = 1
@export var max_ammo: int = 30
@export var reserve_ammo: int = 90
@export var recoil: float = 0.035
@export var fire_rate: float = 0.12
@export var reload_time: float = 1.2
@export_group("Дробовик")
@export var spread_degrees: float = 0.0
@export var max_range: float = 50.0
@export var falloff_start: float = 50.0
@export var min_damage_factor: float = 1.0

@export_group("Прицеливание и положение")
@export var ads_fov: float = 45.0
@export var hip_pos: Vector3 = Vector3(0.2, -0.2, -0.4)
@export var ads_pos: Vector3 = Vector3(0, -0.12, -0.35)
@export var ammo_3d_offset: Vector3 = Vector3(-0.06, 0.05, -0.18)
@export var ammo_3d_rotation_deg: Vector3 = Vector3.ZERO
@export var ammo_3d_font_size: int = 96
@export var ammo_3d_scale: float = 0.0005

@export_group("Модель")
@export var view_scene: PackedScene
@export var placeholder_size: Vector3 = Vector3(0.1, 0.1, 0.7)

enum CrosshairStyle { LINES, CIRCLE, DOT, NONE }

@export_group("Разброс (градусы)")
@export var base_spread_deg: float = 0.3
@export var move_spread_deg: float = 1.8
@export var sprint_spread_deg: float = 3.5
@export var air_spread_deg: float = 4.5
@export var slide_spread_deg: float = 2.5
@export var fire_spread_deg: float = 0.5
@export var fire_spread_max_deg: float = 4.0
@export var fire_recovery_deg_per_sec: float = 6.0
@export var ads_multiplier: float = 0.35
@export var crouch_multiplier: float = 0.6
@export var spread_smoothing: float = 12.0

@export_group("Прицел на экране")
@export var crosshair_style: CrosshairStyle = CrosshairStyle.LINES
@export var crosshair_color: Color = Color(1, 1, 1, 0.9)
@export var crosshair_hit_color: Color = Color(1, 0.2, 0.2, 1)
@export var crosshair_length: float = 10.0
@export var crosshair_thickness: float = 2.0
@export var crosshair_min_gap: float = 3.0
@export var crosshair_dot_size: float = 2.5
@export var crosshair_center_dot: bool = false
@export var crosshair_hide_in_ads: bool = false

# Возвращает словарь в том же формате, что и старый weapon_stats в player.gd
func to_stats() -> Dictionary:
	return {
		"name": display_name,
		"damage": damage,
		"pellets": pellets,
		"max_ammo": max_ammo,
		"reserve": reserve_ammo,
		"recoil": recoil,
		"ads_fov": ads_fov,
		"mesh_size": placeholder_size,
		"fire_rate": fire_rate,
		"reload_time": reload_time,
		"hip_pos": hip_pos,
		"ads_pos": ads_pos,
		"ammo_3d_offset": ammo_3d_offset,
		"ammo_3d_rotation_deg": ammo_3d_rotation_deg,
		"ammo_3d_font_size": ammo_3d_font_size,
		"ammo_3d_scale": ammo_3d_scale,
		"view_scene": view_scene,
		"spread_degrees": spread_degrees,
		"max_range": max_range,
		"falloff_start": falloff_start,
		"min_damage_factor": min_damage_factor
		
	}
