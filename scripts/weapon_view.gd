class_name WeaponView
extends Node3D

# Если пусто, AnimationPlayer ищется среди дочерних узлов
@export var animation_player: AnimationPlayer
@export var cast_shadows: bool = false

func _ready() -> void:
	if animation_player == null:
		animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not cast_shadows:
		_disable_shadows(self)
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	if not _play("draw"):
		_play("idle")

func play_fire() -> void:
	_play("fire")

func play_reload() -> void:
	_play("reload")

func _play(anim_name: StringName) -> bool:
	if animation_player == null or not animation_player.has_animation(anim_name):
		return false
	animation_player.play(anim_name)
	return true

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != &"idle":
		_play("idle")

func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)
