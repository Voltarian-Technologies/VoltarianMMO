extends Control

const _crown: Texture2D = preload("res://img/crown.png")

@onready var _list: ItemList = $HBoxContainer/VBoxContainer/ItemList
@onready var _action: Button = $HBoxContainer/VBoxContainer/Action

var players: Array = []             # array of dictionaries {id:String, name:String}
var turn_index: int = 0
var my_id: String = ""


func start() -> void:
	_list.clear()
	players.clear()
	turn_index = 0
	_action.disabled = true


func stop() -> void:
	_list.clear()
	players.clear()
	turn_index = 0
	_action.disabled = true


func set_player_list(player_array: Array, new_turn_index: int) -> void:
	players = player_array
	turn_index = new_turn_index
	_list.clear()
	for p in players:
		_list.add_item(p["name"])
	_update_turn_icons()


func _update_turn_icons() -> void:
	for i in range(players.size()):
		if i == turn_index:
			_list.set_item_icon(i, _crown)
		else:
			_list.set_item_icon(i, null)

	if players.size() > 0:
		var current_id: String = players[turn_index]["id"]
		_action.disabled = (current_id != my_id)


func set_turn_over_network(new_index: int) -> void:
	turn_index = new_index
	_update_turn_icons()


func handle_network_message(msg: Dictionary) -> void:
	$HBoxContainer/RichTextLabel.add_text(str(msg["name"]) + "\n")


func _on_Action_pressed() -> void:
	var packet: Dictionary = {
		"type": "action",
		"action": "roll"
	}
	get_tree().root.get_node("Main").ws.send_text(JSON.stringify(packet))
