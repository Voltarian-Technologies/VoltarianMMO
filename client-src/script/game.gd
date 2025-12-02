extends Control

signal send_packet(packet: Dictionary)

@onready var _list: ItemList = $HBoxContainer/VBoxContainer/ItemList
@onready var _action: Button = $HBoxContainer/VBoxContainer/Action
@onready var _canvas: Control = $HBoxContainer/GameCanvas

var players: Array = []
var my_id: String = ""
var player_nodes: Dictionary = {}
var my_position: Vector2 = Vector2(400, 300)
var velocity_y: float = 0.0
var is_jumping: bool = false
var is_moving_left: bool = false
var is_moving_right: bool = false
var last_sent_position: Vector2 = Vector2.ZERO
var _space_was_pressed: bool = false
var horizontal_velocity: float = 0.0
var jump_boost_velocity: float = 0.0 # New: Stores horizontal velocity at jump start
var is_boost_jumping: bool = false # New: True when in a boosted jump

const GRAVITY: float = 600.0
var GROUND_Y: float = 300.0 # updated dynamically from canvas size
const MOVE_SPEED: float = 200.0
const JUMP_VELOCITY: float = -350.0
const POSITION_SEND_THRESHOLD: float = 5.0

var MAP_WIDTH: float
const MAP_HEIGHT: float = 800.0
const CAMERA_EDGE_THRESHOLD: float = 200.0
const ACCELERATION: float = 800.0
const FRICTION: float = 1000.0
const MAX_SPEED: float = 200.0
const TURN_THRESHOLD: float = 50.0

var camera_offset: Vector2 = Vector2.ZERO
var canvas_center: Vector2 = Vector2(400, 300)
const SPRITE_HALF_HEIGHT: float = 25.0
const SPRITE_HALF_WIDTH: float = 25.0


func _ready() -> void:
		if not _canvas:
				_canvas = Control.new()
				_canvas.custom_minimum_size = Vector2(800, 600)
				_canvas.clip_contents = true
				$HBoxContainer.add_child(_canvas)

		# set canvas-based ground and center at startup
		if _canvas:
			canvas_center = _canvas.size / 2.0
			GROUND_Y = _canvas.size.y - SPRITE_HALF_HEIGHT
			# Ensure player starts on the ground
			my_position.y = GROUND_Y


func _input(event: InputEvent) -> void:
		if event is InputEventKey:
				if event.keycode == KEY_A:
						is_moving_left = event.pressed
				elif event.keycode == KEY_D:
						is_moving_right = event.pressed
				elif event.keycode == KEY_SPACE and event.pressed:
						action_jump()


func _process(delta: float) -> void:
		var old_position = my_position

		# recompute view metrics and ground from canvas, this supports window resizing
		var view_width: float = 800.0
		var view_height: float = 600.0
		if _canvas:
			view_width = _canvas.size.x
			view_height = _canvas.size.y
			canvas_center = _canvas.size / 2.0
			GROUND_Y = view_height - SPRITE_HALF_HEIGHT
			MAP_WIDTH = view_width
		
		var input_direction: float = 0.0
		if not is_boost_jumping: # Only process input if not boost jumping
			if is_moving_right:
				input_direction += 1.0
			if is_moving_left:
				input_direction -= 1.0

		if is_boost_jumping: # If boost jumping, maintain boost velocity
			horizontal_velocity = jump_boost_velocity
		elif input_direction != 0: # Normal movement with input
			horizontal_velocity = move_toward(horizontal_velocity, input_direction * MAX_SPEED, ACCELERATION * delta)
		elif not is_jumping: # Apply friction only if not jumping and no input
			horizontal_velocity = move_toward(horizontal_velocity, 0, FRICTION * delta)

		# Apply horizontal velocity
		my_position.x += horizontal_velocity * delta
		my_position.x = clamp(my_position.x, SPRITE_HALF_WIDTH, MAP_WIDTH - SPRITE_HALF_WIDTH)
		
		# If the player is above the ground, make sure gravity applies so
		# a reconnected player that was in the air will fall back down.
		if my_position.y < GROUND_Y or is_jumping or velocity_y != 0.0:
				velocity_y += GRAVITY * delta
				my_position.y += velocity_y * delta
				
				if my_position.y >= GROUND_Y:
						my_position.y = GROUND_Y
						velocity_y = 0.0
						is_jumping = false
						is_boost_jumping = false # Reset boost jumping flag on landing
		
		if player_nodes.has(my_id):
				player_nodes[my_id]["target_pos"] = my_position
		
		if my_position.distance_to(last_sent_position) > POSITION_SEND_THRESHOLD:
				_send_position_update()
				last_sent_position = my_position

		# Global Space key check to trigger jump even when UI has focus
		var space_pressed: bool = Input.is_key_pressed(KEY_SPACE)
		if space_pressed and not _space_was_pressed:
			# just pressed
			action_jump()
			# notify network about the action if this is the player's jump
			if my_id != "":
				_emit_packet({"type": "action", "action": "jump"})
		_space_was_pressed = space_pressed
		

		
		for player_id in player_nodes:
				var node_data = player_nodes[player_id]
				var player_node = node_data.node

				if not is_instance_valid(player_node):
						continue

				var screen_pos = node_data["target_pos"] - camera_offset
				var target_sprite_pos = Vector2(screen_pos.x - SPRITE_HALF_HEIGHT, screen_pos.y - SPRITE_HALF_HEIGHT)
				
				if player_id == my_id:
						player_node.position = target_sprite_pos
				else:
						player_node.position = player_node.position.lerp(target_sprite_pos, delta * 10.0)

				# Update animation based on received animation_id
				var received_animation_id = node_data["animation_id"]

				player_node.is_moving = false
				player_node.is_jumping = false
				player_node.is_falling = false
				player_node.is_turning = false

				if received_animation_id == "run":
						player_node.is_moving = true
				elif received_animation_id == "jump":
						player_node.is_jumping = true
				elif received_animation_id == "fall":
						player_node.is_falling = true
				elif received_animation_id == "turn_around":
						player_node.is_turning = true
				
				# Face direction based on velocity for other players, if not turning.
				# This helps smooth out movement even with interpolated positions.
				var velocity = (node_data["target_pos"] - node_data["last_pos"]) / delta
				node_data["last_pos"] = node_data["target_pos"]
				if not player_node.is_turning:
					if velocity.x < 0:
							player_node.face_left(true)
					elif velocity.x > 0:
							player_node.face_left(false)

				if player_id == my_id:
						var player_node_local = player_node # Renamed for clarity within this scope
						
						# Determine if player is currently 'moving' (either by input or by sliding)
						player_node_local.is_moving = input_direction != 0 or abs(horizontal_velocity) > 1.0
						player_node_local.is_jumping = is_jumping
						player_node_local.is_falling = my_position.y < GROUND_Y and velocity_y > 0
						
						# Turn-around logic
						var should_turn = false
						if input_direction == 1.0 and horizontal_velocity < -TURN_THRESHOLD: # Moving left, wants to go right
							should_turn = true
						elif input_direction == -1.0 and horizontal_velocity > TURN_THRESHOLD: # Moving right, wants to go left
							should_turn = true

						if should_turn and not player_node_local.is_turning:
							player_node_local.turn_around()

						# Face direction logic (only if not turning)
						if not player_node_local.is_turning:
							if horizontal_velocity < 0: # If moving left or sliding left
								player_node_local.face_left(true)
							elif horizontal_velocity > 0: # If moving right or sliding right
								player_node_local.face_left(false)


func start() -> void:
		if _list:
				_list.clear()
		players.clear()
		if _action:
				_action.disabled = false
		# Reset movement state on start
		is_moving_left = false
		is_moving_right = false
		is_jumping = false
		velocity_y = 0.0
		horizontal_velocity = 0.0
		last_sent_position = my_position
		_space_was_pressed = false


func stop() -> void:
		if _list:
				_list.clear()
		players.clear()
		if _action:
				_action.disabled = true
		for player_id in player_nodes:
				remove_player_sprite(player_id)
		player_nodes.clear()
		# Reset movement state on stop to avoid carrying it over when reconnecting
		is_moving_left = false
		is_moving_right = false
		is_jumping = false
		velocity_y = 0.0
		horizontal_velocity = 0.0
		_space_was_pressed = false


func set_player_list(player_array: Array) -> void:
		players = player_array
		if _list:
				_list.clear()
		for p in players:
				if _list:
						_list.add_item(p["name"])
						var idx = _list.item_count - 1
						_list.set_item_tooltip(idx, "UUID: " + p["id"] + "\nOS User: " + p.get("os_username", "unknown"))
				
				if not player_nodes.has(p["id"]):
					create_player_sprite(p["id"], p["name"], p.get("position", {"x": 400, "y": GROUND_Y}))
				else:
						update_player_label(p["id"], p["name"])


const PLAYER_SCENE = preload("res://scene/player.tscn")


func create_player_sprite(player_id: String, player_name: String, pos: Dictionary) -> void:
		if not _canvas:
				return

		var player_node = PLAYER_SCENE.instantiate()
		# It's important to add the node to the scene tree BEFORE trying to access its
		# children via @onready vars, otherwise they will be null.
		_canvas.add_child(player_node)

		var world_pos = Vector2(pos.get("x", 400), pos.get("y", GROUND_Y))
		var screen_pos = world_pos - camera_offset
		player_node.position = Vector2(screen_pos.x - SPRITE_HALF_HEIGHT, screen_pos.y - SPRITE_HALF_HEIGHT)
		
		player_node.set_player_name(player_name)
		
		if player_id == my_id:
				player_node.set_color(Color(0.2, 0.8, 0.2))
		else:
				player_node.set_color(Color(1, 1, 1)) # Other players are not tinted
		
		player_nodes[player_id] = {
				"node": player_node,
				"target_pos": world_pos,
				"last_pos": world_pos,
				"animation_id": "idle" # Initialize animation_id
		}
		
		print("[GAME] Created sprite for player: ", player_name, " at ", world_pos)


func update_player_position(player_id: String, pos: Dictionary) -> void:
		if player_nodes.has(player_id):
				var new_pos = Vector2(pos.get("x", 400), pos.get("y", GROUND_Y))
				player_nodes[player_id].target_pos = new_pos


func update_player_label(player_id: String, player_name: String) -> void:
		if player_nodes.has(player_id):
				player_nodes[player_id].node.set_player_name(player_name)


func remove_player_sprite(player_id: String) -> void:
		if player_nodes.has(player_id):
				player_nodes[player_id].node.queue_free()
				player_nodes.erase(player_id)


func handle_network_message(msg: Dictionary) -> void:
		var type = msg.get("type")

		if type == "player_list":
				set_player_list(msg["players"])
				# Update local player's position if it's the first time receiving player_list
				if my_id == "" and not msg["players"].is_empty():
					my_id = msg["players"][0]["id"] # Assuming first player in list is local player for now
					set_my_position(Vector2(msg["players"][0]["position"]["x"], msg["players"][0]["position"]["y"]))
					print("[GAME] My ID set to: ", my_id)
		elif type == "init":
				my_id = msg["id"]
				set_my_position(Vector2(msg["position"]["x"], msg["position"]["y"]))
				print("[GAME] Initialized with ID: ", my_id)
		elif type == "player_joined":
				# No need to add here, player_list will handle it
				pass
		elif type == "player_left":
				remove_player_sprite(msg["id"])
		elif type == "player_name_changed":
				update_player_label(msg["id"], msg["name"])
		elif type == "position_update":
				var player_id = msg["player_id"]
				var new_pos = msg["position"]
				var animation_id = msg.get("animation_id", "idle") # Get animation_id

				if player_nodes.has(player_id):
						player_nodes[player_id].target_pos = Vector2(new_pos["x"], new_pos["y"])
						player_nodes[player_id]["animation_id"] = animation_id # Update animation_id
		elif has_node("HBoxContainer/RichTextLabel"):
				$HBoxContainer/RichTextLabel.add_text(str(msg["name"]) + "\n")


func _emit_packet(packet: Dictionary) -> void:
		send_packet.emit(packet)


func action_jump() -> void:
		if not is_jumping and my_position.y >= GROUND_Y:
			velocity_y = JUMP_VELOCITY
			is_jumping = true
			is_boost_jumping = true # Set boost jumping flag
			jump_boost_velocity = horizontal_velocity # Store current horizontal velocity
			# Notify server of action so other clients are aware
			var packet: Dictionary = {
				"type": "action",
				"action": "jump"
			}
			_emit_packet(packet)


func get_local_animation_id() -> String:
		if not player_nodes.has(my_id) or not player_nodes[my_id].has("node"):
			return "idle" # Return default if player node not yet available

		var player_node_local = player_nodes[my_id].node # Get local player node

		if player_node_local.is_turning:
			return "turn_around"
		elif player_node_local.is_falling:
			return "fall"
		elif player_node_local.is_jumping:
			return "jump"
		elif player_node_local.is_moving:
			return "run"
		else:
			return "idle"

func _send_position_update() -> void:
		var packet: Dictionary = {
				"type": "position_update",
				"x": my_position.x,
				"y": my_position.y,
				"animation_id": get_local_animation_id() # Include current animation
		}
		_emit_packet(packet)


func _on_Action_pressed() -> void:
		action_jump()
		# also notify the server about the action when the UI button was used
		if my_id != "":
			_emit_packet({"type": "action", "action": "jump"})


func set_my_position(pos: Vector2) -> void:
	my_position = pos
	# Reset horizontal movement flags to avoid being stuck if reconnecting while pressing keys
	is_moving_left = false
	is_moving_right = false
	last_sent_position = my_position
	# Make sure local player sprite interpolation updates to new position
	if player_nodes.has(my_id):
		player_nodes[my_id]["target_pos"] = my_position
	# Apply proper state for reconnects: if player is above ground, ensure gravity will apply
	if my_position.y < GROUND_Y:
		is_jumping = true
		# starting falling from rest
		velocity_y = 0.0
	else:
		is_jumping = false
		velocity_y = 0.0
