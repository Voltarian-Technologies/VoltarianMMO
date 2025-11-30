extends Control

const SERVER: String = "wss://ws.voltaccept.com"

@onready var _join_btn: Button = $Panel/VBoxContainer/HBoxContainer2/HBoxContainer/Join
@onready var _leave_btn: Button = $Panel/VBoxContainer/HBoxContainer2/HBoxContainer/Leave
@onready var _name_edit: LineEdit = $Panel/VBoxContainer/HBoxContainer/NameEdit
@onready var _game: Control = $Panel/VBoxContainer/Game

var ws: WebSocketPeer = WebSocketPeer.new()
var connected: bool = false
var my_id: String = ""
var os_username: String = ""
var display_name: String = ""


func _ready() -> void:
		$AcceptDialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		$AcceptDialog.get_label().vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		if OS.has_environment("USERNAME"):
				os_username = OS.get_environment("USERNAME")
				_name_edit.text = os_username
				_name_edit.placeholder_text = "Display Name (editable)"
		elif OS.has_environment("USER"):
				os_username = OS.get_environment("USER")
				_name_edit.text = os_username
				_name_edit.placeholder_text = "Display Name (editable)"
		
		if _game.has_signal("send_packet"):
				_game.send_packet.connect(_on_game_send_packet)


func _on_game_send_packet(packet: Dictionary) -> void:
		if connected and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				ws.send_text(JSON.stringify(packet))


func _process(delta: float) -> void:
		if not connected:
				return

		ws.poll()

		var state: int = ws.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
				_close_network()
				return

		while ws.get_available_packet_count() > 0:
				var msg: String = ws.get_packet().get_string_from_utf8()
				var data = JSON.parse_string(msg)
				if typeof(data) != TYPE_DICTIONARY:
						continue

				_handle_server_message(data)


func _handle_server_message(data: Dictionary) -> void:
		match data.get("type", ""):

				"init":
						my_id = data["id"]
						display_name = data.get("display_name", _name_edit.text)
						_name_edit.text = display_name
						print("[INIT] My UUID: ", my_id)
						print("[INIT] OS Username: ", os_username, " (permanent)")
						print("[INIT] Display Name: ", display_name, " (editable)")
						_game.my_id = my_id
						
						if data.has("position"):
							_game.set_my_position(Vector2(
								data["position"].get("x", 400),
								data["position"].get("y", _game.GROUND_Y)
							))

				"player_joined":
						_game.handle_network_message({"name": "%s joined" % data["name"]})

				"player_left":
						_game.handle_network_message({"name": "%s left" % data["name"]})
						if data.has("id"):
								_game.remove_player_sprite(data["id"])

				"player_name_changed":
						_game.handle_network_message({"name": "%s changed their name" % data["name"]})

				"player_list":
						_game.set_player_list(data["players"])

				"position_update":
						if data.has("player_id") and data.has("position"):
								_game.update_player_position(data["player_id"], data["position"])

				"action":
						var text: String = "%s: %s" % [
								data.get("player_name", "Unknown"),
								data.get("action", "unknown")
						]
						_game.handle_network_message({"name": text})

				"move":
						pass
				
				"error":
						print("[ERROR] Server error: ", data.get("message", "Unknown"))
						_close_network()

				_:
						print("[WARN] Unknown server message: ", data)


func start_game() -> void:
		_name_edit.editable = false
		_join_btn.hide()
		_leave_btn.show()
		_game.start()


func stop_game() -> void:
		_name_edit.editable = true
		_leave_btn.hide()
		_join_btn.show()
		_game.stop()


func _close_network() -> void:
		if connected:
				ws.close()
		connected = false
		stop_game()
		$AcceptDialog.popup_centered()
		$AcceptDialog.get_ok_button().grab_focus()


func _on_Leave() -> void:
		_close_network()


func _on_Join() -> void:
		var err: int = ws.connect_to_url(SERVER)
		if err != OK:
				print("Failed to connect to secure WebSocket!")
				return
		
		connected = true
		
		await get_tree().create_timer(0.5).timeout
		
		var state = ws.get_ready_state()
		if state != WebSocketPeer.STATE_OPEN:
				print("WebSocket not ready, waiting...")
				for i in range(10):
						ws.poll()
						await get_tree().create_timer(0.1).timeout
						if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
								break
		
		var packet: Dictionary = {
				"type": "join",
				"os_username": os_username,
				"display_name": _name_edit.text if _name_edit.text != "" else os_username
		}
		ws.send_text(JSON.stringify(packet))
		
		start_game()


func update_display_name(new_name: String) -> void:
		if connected and new_name != "":
				display_name = new_name
				var packet: Dictionary = {
						"type": "update_display_name",
						"display_name": new_name
				}
				ws.send_text(JSON.stringify(packet))
