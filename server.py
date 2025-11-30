import asyncio
import json
import websockets
import uuid
import traceback
import hashlib
import os

HOST = "localhost"
PORT = 8765
GROUND_Y = 300.0

connected_players = {}  # ws -> player_data
persistent_players = {}  # os_username -> {"uuid": str, "display_name": str, "position": dict}
PLAYERS_FILE = "players_data.json"


def load_persistent_data():
    """Load player data from file."""
    global persistent_players
    if os.path.exists(PLAYERS_FILE):
        try:
            with open(PLAYERS_FILE, "r") as f:
                persistent_players = json.load(f)
            print(f"[LOAD] Loaded {len(persistent_players)} players from {PLAYERS_FILE}")
        except Exception as e:
            print(f"[ERROR] Failed to load players file: {e}")


def save_persistent_data():
    """Save player data to file."""
    try:
        with open(PLAYERS_FILE, "w") as f:
            json.dump(persistent_players, f, indent=2)
    except Exception as e:
        print(f"[ERROR] Failed to save players file: {e}")


def get_or_create_player(os_username: str, display_name: str = None) -> dict:
    """Get or create a persistent player based on OS username."""
    if os_username not in persistent_players:
        # Generate a consistent UUID based on the OS username
        # Using UUID5 with a namespace ensures the same username always gets the same UUID
        namespace = uuid.UUID(
            '6ba7b810-9dad-11d1-80b4-00c04fd430c8')  # DNS namespace
        player_uuid = str(uuid.uuid5(namespace, os_username))

        persistent_players[os_username] = {
            "uuid": player_uuid,
            "display_name": display_name or os_username,
            "os_username": os_username,
            "position": {
                "x": 400.0,
                "y": 300.0
            }  # Start at center
        }
        print(f"[NEW PLAYER] Created {os_username} with UUID {player_uuid}")
        save_persistent_data()
    elif display_name and display_name != persistent_players[os_username]["display_name"]:
        # Update display name if provided
        persistent_players[os_username]["display_name"] = display_name
        print(f"[UPDATE] {os_username} display name -> {display_name}")
        save_persistent_data()

    return persistent_players[os_username]


def make_player_info(player_uuid: str) -> dict:
    """Create player info dict from UUID."""
    for os_username, data in persistent_players.items():
        if data["uuid"] == player_uuid:
            return {
                "id": player_uuid,
                "name": data["display_name"],
                "os_username": data["os_username"],
                "position": data["position"]
            }
    return {
        "id": player_uuid,
        "name": "Unknown",
        "os_username": "unknown",
        "position": {
            "x": 400,
            "y": 300
        }
    }


async def broadcast(packet, except_ws=None):
    """Send packet to all players except optional one."""
    message = json.dumps(packet)
    for ws, player_data in list(connected_players.items()):
        if ws is not except_ws:
            try:
                await ws.send(message)
            except:
                pass


async def send_player_list():
    """Sync full player list."""
    players = [
        make_player_info(data["uuid"]) for data in connected_players.values()
    ]
    await broadcast({"type": "player_list", "players": players})


async def handle_client(ws):
    player_data = None
    player_uuid = None

    print(f"[CONNECT] New connection")

    try:
        # Wait for initial join message with OS username
        async for raw in ws:
            try:
                data = json.loads(raw)
            except:
                print("[ERROR] Invalid JSON:", raw)
                continue

            typ = data.get("type")

            if typ == "join":
                os_username = data.get("os_username", "")
                display_name = data.get("display_name", "")

                if not os_username:
                    await ws.send(
                        json.dumps({
                            "type": "error",
                            "message": "OS username required"
                        }))
                    continue

                # Get or create persistent player
                player_data = get_or_create_player(os_username, display_name)
                player_uuid = player_data["uuid"]

                # Store connection
                connected_players[ws] = player_data

                print(
                    f"[JOIN] {display_name} ({os_username}) -> UUID {player_uuid}"
                )

                await ws.send(
                    json.dumps({
                        "type": "init",
                        "id": player_uuid,
                        "os_username": os_username,
                        "display_name": player_data["display_name"],
                        "position": player_data["position"]
                    }))

                # Notify others
                await broadcast(
                    {
                        "type": "player_joined",
                        "id": player_uuid,
                        "name": player_data["display_name"],
                        "position": player_data["position"]
                    },
                    except_ws=ws)

                await send_player_list()
                break  # Exit this loop and enter main message loop

        if player_data is None:
            return  # Client disconnected before joining

        # Main message loop
        async for raw in ws:
            try:
                data = json.loads(raw)
            except:
                print("[ERROR] Invalid JSON:", raw)
                continue

            typ = data.get("type")

            if typ == "update_display_name":
                new_display_name = data.get("display_name", "")
                if new_display_name:
                    player_data["display_name"] = new_display_name
                    print(
                        f"[NAME CHANGE] {player_data['os_username']} -> {new_display_name}"
                    )

                    await broadcast({
                        "type": "player_name_changed",
                        "id": player_uuid,
                        "name": new_display_name
                    })

                    await send_player_list()

            elif typ == "action":
                action = data.get("action")

                if action not in ("move_left", "move_right", "jump"):
                    await ws.send(
                        json.dumps({
                            "type": "action_rejected",
                            "reason": "invalid_action"
                        }))
                    continue

                pos = player_data["position"]
                if action == "move_left":
                    pos["x"] -= 50.0
                elif action == "move_right":
                    pos["x"] += 50.0
                elif action == "jump":
                    pos["y"] -= 150.0  # Jump up (negative Y is up in 2D)

                print(
                    f"[ACTION] {player_data['display_name']}: {action} -> {pos}"
                )

                # Log specifically for jump actions for easier debugging
                if action == "jump":
                    print(f"[JUMP] {player_data['display_name']} jumped to {pos}")

                # Broadcast position update to all clients
                await broadcast({
                    "type": "position_update",
                    "player_id": player_uuid,
                    "position": pos,
                    "action": action
                })

            elif typ == "position_update":
                x = data.get("x", player_data["position"]["x"])
                y = data.get("y", player_data["position"]["y"])

                player_data["position"]["x"] = x
                player_data["position"]["y"] = y

                # Broadcast to other clients
                await broadcast(
                    {
                        "type": "position_update",
                        "player_id": player_uuid,
                        "position": player_data["position"]
                    },
                    except_ws=ws)
                print(f"[POS UPDATE] {player_data['display_name']} -> x={x}, y={y}")

            else:
                print("[WARN] Unknown type:", typ)

    except websockets.ConnectionClosed:
        pass
    except Exception:
        traceback.print_exc()
    finally:
        if player_data:
            print(
                f"[DISCONNECT] {player_data['display_name']} ({player_data['os_username']})"
            )

            # Save player position; if disconnecting while in the air, clamp to ground
            try:
                if player_data.get("position") and player_data["position"].get("y") < GROUND_Y:
                    player_data["position"]["y"] = GROUND_Y
                    save_persistent_data()
            except Exception:
                pass

            # Remove from connected players
            if ws in connected_players:
                del connected_players[ws]

            # Check if player has any other active connections
            player_still_connected = any(
                data["uuid"] == player_uuid
                for data in connected_players.values())

            if not player_still_connected:
                await broadcast({
                    "type": "player_left",
                    "id": player_uuid,
                    "name": player_data["display_name"]
                })

                await send_player_list()


async def main():
    load_persistent_data()
    print(f"Starting server on ws://{HOST}:{PORT}")

    async with websockets.serve(handle_client, HOST, PORT):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
