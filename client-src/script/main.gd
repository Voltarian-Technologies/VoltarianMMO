extends Control

# Use your secure WebSocket server
const SERVER: String = "wss://ws.voltaccept.com"

@onready var _join_btn: Button = $Panel/VBoxContainer/HBoxContainer2/HBoxContainer/Join
@onready var _leave_btn: Button = $Panel/VBoxContainer/HBoxContainer2/HBoxContainer/Leave
@onready var _name_edit: LineEdit = $Panel/VBoxContainer/HBoxContainer/NameEdit
@onready var _game: Control = $Panel/VBoxContainer/Game

var ws: WebSocketPeer = WebSocketPeer.new()
var connected: bool = false
var my_id: String = ""


func _ready() -> void:
	$AcceptDialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$AcceptDialog.get_label().vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	if OS.has_environment("USERNAME"):
		_name_edit.text = OS.get_environment("USERNAME")


func _process(delta: float) -> void:
	if not connected:
		return

	ws.poll()

	# detect disconnect
	var state: int = ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		_close_network()
		return

	while ws.get_available_packet_count() > 0:
		var msg: String = ws.get_packet().get_string_from_utf8()
		var data: Dictionary = JSON.parse_string(msg)
		if typeof(data) != TYPE_DICTIONARY:
			continue

		_handle_server_message(data)


func _handle_server_message(data: Dictionary) -> void:
	match data.get("type", ""):

		"init":
			my_id = data["id"]
			print("[INIT] My ID: ", my_id)
			var packet: Dictionary = {
				"type": "join",
				"name": _name_edit.text
			}
			ws.send_text(JSON.stringify(packet))

		"player_joined":
			_game.handle_network_message({"name": "%s joined" % data["name"]})

		"player_left":
			_game.handle_network_message({"name": "%s left" % data["name"]})

		"player_list":
			_game.set_player_list(data["players"], data["turn_index"])

		"turn_update":
			_game.set_turn_over_network(data["turn_index"])

		"action":
			var text: String = "%s: %s (%d)" % [
				data["player_name"],
				data["action"],
				data["value"]
			]
			_game.handle_network_message({"name": text})

		"move":
			pass  # optional movement handling

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
	start_game()
