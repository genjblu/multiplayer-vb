class_name MenuBackground
extends Node3D

@onready var camera: MenuCamera = $MenuCamera
@onready var robots_container: Node3D = $Robots

var waypoints: Array[Vector3] = [
	Vector3(0.0, 0.6, 0.0),
	Vector3(6.5, 0.6, 6.5),
	Vector3(-6.5, 0.6, -6.5),
	Vector3(7.5, 0.6, -7.0),
	Vector3(-7.5, 0.6, 7.0),
	Vector3(0.0, 0.6, 9.5),
	Vector3(0.0, 0.6, -9.5),
	Vector3(10.0, 0.6, 0.0),
	Vector3(-10.0, 0.6, 0.0),
	Vector3(4.0, 4.2, 12.0),
	Vector3(-4.0, 4.2, -12.0),
	Vector3(12.0, 4.2, 4.0),
	Vector3(-12.0, 4.2, -4.0)
]

func _ready() -> void:
	if not camera:
		camera = find_child("MenuCamera", true, false) as MenuCamera
	if camera:
		camera.make_current()

	_setup_robots()

func _setup_robots() -> void:
	var bots: Array[MenuRobot] = []
	for child in robots_container.get_children():
		if child is MenuRobot:
			bots.append(child)
			child.add_to_group("menu_robots")

	for bot in bots:
		bot.all_bots = bots
		bot.waypoints = waypoints
