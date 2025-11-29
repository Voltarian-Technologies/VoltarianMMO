import asyncio
import json
import websockets
import uuid

connected_players = {}   # player_id -> websocket
player_names = {}        # player_id -> name
player_positions = {}    # player_id -> {x,y}


async def send_to_all(packet, except_ws=None):
    """Send packet to all players except optional one."""
    message = json.dumps(packet)
    for pid, ws in connected_players.items():
        if ws != except_ws:
            try:
                await ws.send(message)
            except:
                pass


async def handle_client(ws):
    # Assign unique ID
    player_id = str(uuid.uuid4())
    connected_players[player_id] = ws
    player_positions[player_id] = {"x": 0, "y": 0}

    print(f"[JOIN] Player {player_id}")

    # Send initial ID to client
    await ws.send(json.dumps({
        "type": "init",
        "id": player_id
    }))

    try:
        async for msg in ws:
            data = json.loads(msg)

            if data["type"] == "join":
                # Player sent name
                player_names[player_id] = data["name"]
                print(f"[NAME] {player_id} is {data['name']}")

                # Tell other players about new player
                await send_to_all({
                    "type": "player_joined",
                    "id": player_id,
                    "name": data["name"],
                    "pos": player_positions[player_id]
                }, except_ws=ws)

                # Send all existing players to new player
                for pid in connected_players:
                    if pid == player_id:
                        continue
                    await ws.send(json.dumps({
                        "type": "player_joined",
                        "id": pid,
                        "name": player_names.get(pid, "Player"),
                        "pos": player_positions[pid]
                    }))

            elif data["type"] == "move":
                # Update and broadcast movement
                player_positions[player_id] = {"x": data["x"], "y": data["y"]}

                await send_to_all({
                    "type": "move",
                    "id": player_id,
                    "x": data["x"],
                    "y": data["y"]
                }, except_ws=ws)

    except websockets.ConnectionClosed:
        print(f"[QUIT] Player {player_id} disconnected")

    finally:
        # Remove player
        del connected_players[player_id]
        del player_positions[player_id]
        name = player_names.get(player_id, "Player")
        if player_id in player_names:
            del player_names[player_id]

        # Notify others
        await send_to_all({
            "type": "player_left",
            "id": player_id,
            "name": name
        })


async def main():
    async with websockets.serve(handle_client, "localhost", 8765):
        print("Multiplayer WebSocket server running on ws://localhost:8765")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
