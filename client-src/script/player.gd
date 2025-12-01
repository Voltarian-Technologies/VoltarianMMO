extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $Label

var is_moving: bool = false
var is_jumping: bool = false
var is_falling: bool = false
var is_turning: bool = false # New: For turn-around animation

func _ready() -> void: # New: Connect animation_finished signal
	animated_sprite.animation_finished.connect(_on_animation_finished)

func _process(delta: float) -> void:
	update_animation()

func set_player_name(new_name: String) -> void:
	label.text = new_name

func update_animation() -> void:
	if is_turning: # New: Highest priority for turning
		animated_sprite.play("turn_around")
	elif is_falling:
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
	# Only flip if not currently turning
	if not is_turning: # New: Prevent flipping during turn animation
		animated_sprite.flip_h = face

func turn_around() -> void: # New: Function to initiate turn animation
	if not is_turning:
		is_turning = true
		animated_sprite.play("turn_around")

func _on_animation_finished() -> void: # New: Signal handler for animation end
	if animated_sprite.animation == "turn_around":
		is_turning = false
		# The actual flip_h will be handled by game.gd or next face_left call
		# after is_turning becomes false.
