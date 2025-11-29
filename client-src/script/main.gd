extends Control

const SERVER = "wss://ws.voltaccept.com"

@onready var _join_btn = $Panel/VBoxContainer/HBoxContainer2/HBoxContainer/Join
@onready var _leave_btn = $Panel/VBoxContainer/HBoxContainer2/HBoxContainer/Leave
@onready var _name_edit = $Panel/VBoxContainer/HBoxContainer/NameEdit
@onready var _game = $Panel/VBoxContainer/Game

var ws := WebSocketPeer.new()
var connected = false


func _ready():
	$AcceptDialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$AcceptDialog.get_label().vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	if OS.has_environment("USERNAME"):
		_name_edit.text = OS.get_environment("USERNAME")


func _process(delta):
	if not connected:
		return

	ws.poll()

	while ws.get_available_packet_count() > 0:
		var msg = ws.get_packet().get_string_from_utf8()
		var data = JSON.parse_string(msg)

		if typeof(data) == TYPE_DICTIONARY:
			_game.handle_network_message(data)


func start_game():
	_name_edit.editable = false
	_join_btn.hide()
	_leave_btn.show()
	_game.start()


func stop_game():
	_name_edit.editable = true
	_leave_btn.hide()
	_join_btn.show()
	_game.stop()


func _close_network():
	stop_game()
	connected = false
	ws.close()
	$AcceptDialog.popup_centered()
	$AcceptDialog.get_ok_button().grab_focus()


func _on_Leave():
	_close_network()


func _on_Join() -> void:
	var err = ws.connect_to_url(SERVER)
	if err != OK:
		print("Failed to connect!")
		return

	connected = true
	start_game()

	# Send login message
	var packet = {
		"type": "join",
		"name": _name_edit.text
	}
	ws.send_text(JSON.stringify(packet))
