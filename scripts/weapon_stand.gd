class_name WeaponStand
extends Area3D

enum StandType { PISTOL = 0, ASSAULT = 1, SHOTGUN = 2, SNIPER = 3, AMMO_REFILL = 4 }

@export var stand_type: StandType = StandType.ASSAULT
@export var weapon_name: String = "АК-74"

@onready var label: Label3D = $Label3D
@onready var model_holder: Node3D = $ModelHolder

var _player_in_range: CharacterBody3D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_label()

func _process(delta: float) -> void:
	if model_holder:
		model_holder.rotate_y(delta * 1.2)

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_E and not event.echo):
		_interact(_player_in_range)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("players") or body.name == "1" or body.has_method("refill_ammo"):
		_player_in_range = body as CharacterBody3D
		# Автоматическое взаимодействие при входе в зону, либо подсказка
		_interact(_player_in_range)

func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null

func _interact(player: CharacterBody3D) -> void:
	if not is_instance_valid(player):
		return
	if stand_type == StandType.AMMO_REFILL:
		if player.has_method("refill_ammo"):
			player.refill_ammo()
		_show_feedback("Боеприпасы пополнены! (Full Ammo)")
	else:
		if player.has_method("switch_weapon_by_index"):
			player.switch_weapon_by_index(stand_type as int)
		if player.has_method("refill_ammo"):
			player.refill_ammo()
		_show_feedback("Взято: %s" % weapon_name)

func _update_label() -> void:
	if not label:
		return
	if stand_type == StandType.AMMO_REFILL:
		label.text = "📦 Ящик патронов\n[Подойти / E]"
		label.modulate = Color(0.2, 0.9, 0.4)
	else:
		label.text = "🔫 %s\n[Подойти / E]" % weapon_name
		label.modulate = Color(0.3, 0.8, 1.0)

func _show_feedback(msg: String) -> void:
	if not label:
		return
	var orig_text := label.text
	var orig_mod := label.modulate
	label.text = "✓ " + msg
	label.modulate = Color(0.3, 1.0, 0.4)
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_callback(func():
		if is_instance_valid(label):
			label.text = orig_text
			label.modulate = orig_mod
	)
