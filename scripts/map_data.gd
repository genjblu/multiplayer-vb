class_name MapData
extends Resource

@export var id: String = "arena"
@export var display_name: String = "Арена"
@export_multiline var description: String = "Стандартная тренировочная арена для ближнего боя."
@export var preview_texture: Texture2D = null
@export_file("*.tscn") var scene_path: String = "res://scenes/arena.tscn"
@export var supported_modes: Array[String] = ["ffa", "2v2", "3v3v3", "4v4"]
