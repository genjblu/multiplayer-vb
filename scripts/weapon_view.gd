class_name WeaponView
extends Node3D

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

var _queued: StringName = &""

func _ready() -> void:
	if animation_player == null:
		animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not cast_shadows:
		_disable_shadows(self)
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
		if animation_player.has_animation("draw"):
			_start(&"draw")
		elif animation_player.has_animation("idle"):
			animation_player.play("idle")

func play_fire() -> void:
	_request(&"fire")

func play_reload() -> void:
	_request(&"reload")

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
