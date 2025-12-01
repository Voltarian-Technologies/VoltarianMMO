extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $Label

var is_moving: bool = false
var is_jumping: bool = false
var is_falling: bool = false

func _process(delta: float) -> void:
	update_animation()

func set_player_name(new_name: String) -> void:
	label.text = new_name

func update_animation() -> void:
	if is_falling:
		animated_sprite.play("fall")
	elif is_jumping:
		animated_sprite.play("jump")
	elif is_moving:
		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")

func set_color(color: Color) -> void:
	# This function is for distinguishing the local player
	# animated_sprite.modulate = color
	pass

func face_left(face: bool) -> void:
	animated_sprite.flip_h = face
