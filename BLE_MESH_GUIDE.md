# ShaRogai BLE Mesh Chat — Complete Guide

## What We Built

### Children App (Flutter) — DONE

Two new services added, zero existing code broken:

| File | Purpose |
|------|---------|
| `ble_mesh_service.dart` | BLE 5 mesh network (scan, connect, relay, route) |
| `mesh_chat_transport.dart` | Glue: mesh ↔ chat UI ↔ Brain HTTP |

### How 10 Kids Connect (Step by Step)

```
STEP 1: Kid1 opens app, enters Brain IP, connects via WiFi
        → Kid1 becomes a "BRIDGE" (isBridge = true, hops = 0)
        → Kid1 starts BLE advertising: "SRG:Kid1:0:1"
                                         name:hops:bridge

STEP 2: Kid2 opens app, has NO WiFi to Brain
        → Kid2 BLE scan finds Kid1 advertising (hops=0, bridge=true)
        → Kid2 taps "Scan for Nearby Kids" on connect screen
        → Kid2 sees: "Kid1 ▓▓▓▓ 85% • 0 hops to Brain"
        → Kid2 taps "Join" → auto-connects BLE to Kid1
        → Kid2 hops = 1 (Kid1's hops + 1)
        → Kid2 starts advertising: "SRG:Kid2:1:0"

STEP 3: Kid3 is too far from Kid1, but close to Kid2
        → Kid3 scans, finds Kid2 (hops=1)
        → Kid3 joins Kid2 → hops = 2
        → Advertises: "SRG:Kid3:2:0"

STEP 4-10: Same pattern. Each kid joins nearest peer.
```

**Result: Chain**
```
Kid10 → Kid8 → Kid6 → Kid4 → Kid2 → Kid1(bridge) → Brain
  5 hops              3 hops         1 hop    WiFi     iPad
```

### What Happens Automatically

| Action | Auto? | How |
|--------|-------|-----|
| BLE scanning | YES | Every 30 seconds, scans for ShaRogai service UUID |
| Peer discovery | YES | Finds all nearby kids running the app |
| Routing updates | YES | Every 15 seconds, broadcasts hop count to peers |
| Best relay selection | YES | Picks peer with fewest hops + strongest signal |
| Message forwarding | YES | Receives mesh message → forwards to next hop |
| Duplicate filtering | YES | Tracks 500 message IDs, drops duplicates |
| Stale peer cleanup | YES | Removes peers not seen in 60 seconds |
| Bridge detection | YES | Checks if Brain URL works via HTTP on startup |

### What Requires User Action

| Action | Where | What user does |
|--------|-------|----------------|
| Initial connect | Connect Screen | Enter Brain IP OR tap "Scan for Nearby Kids" |
| Join a peer | Connect Screen | Tap "Join" next to a discovered peer |
| Send chat | Chat Screen | Type message, tap send (mesh routing is automatic) |

### BLE Connection — Both Sides Auto?

**Scanning (finding peers):** AUTOMATIC — runs every 30 seconds
**Connecting (establishing link):** SEMI-AUTO — user taps "Join" first time, then:
- Auto-reconnect is NOT built in (BLE connections drop when out of range)
- When a peer disconnects, the mesh finds the NEXT BEST relay automatically
- The `connectToBestRelay()` method can be called to auto-connect

**After first join:** Chat messages route automatically. No user action needed.

---

## What Brain Needs (iPad Server)

Brain needs 2 NEW API endpoints for mesh chat relay:

### Endpoint 1: POST /api/chat
Receives chat messages relayed through the mesh.

**Request:**
```json
{
  "from_device": "Kid5",
  "text": "Hello everyone!",
  "via_mesh": true,
  "hops": 3,
  "path": ["Kid5", "Kid3", "Kid1"]
}
```

**Response:**
```json
{
  "status": "ok",
  "response": "optional reply text from Brain"
}
```

### Endpoint 2: GET /api/chat/messages
Returns new chat messages for mesh broadcast.

**Response:**
```json
{
  "messages": [
    {
      "from": "Brain",
      "text": "Dinner in 10 minutes!",
      "timestamp": "2026-02-21T18:50:00Z"
    },
    {
      "from": "Kid2",
      "text": "On my way!",
      "timestamp": "2026-02-21T18:50:05Z"
    }
  ]
}
```

### Existing Endpoints (No Changes Needed)

| Endpoint | Status |
|----------|--------|
| POST /api/connect | WORKS — mesh devices send registration via relay |
| GET /api/status | WORKS — used to detect bridge capability |
| POST /api/heartbeat | WORKS — mesh devices send heartbeat via relay |
| GET /api/events | WORKS — unchanged |
| POST /api/report | WORKS — unchanged (motion/voice stay on WiFi) |

### Brain Implementation (Python Flask example)

```python
from flask import Flask, request, jsonify
from datetime import datetime

app = Flask(__name__)
chat_messages = []  # In-memory store

@app.route('/api/chat', methods=['POST'])
def receive_chat():
    data = request.json
    msg = {
        'from': data.get('from_device', 'Unknown'),
        'text': data.get('text', ''),
        'via_mesh': data.get('via_mesh', False),
        'hops': data.get('hops', 0),
        'path': data.get('path', []),
        'timestamp': datetime.now().isoformat()
    }
    chat_messages.append(msg)
    print(f"[Chat] {msg['from']}: {msg['text']} ({msg['hops']} hops)")
    return jsonify({'status': 'ok'})

@app.route('/api/chat/messages', methods=['GET'])
def get_chat_messages():
    # Return and clear (bridge polls every 5s)
    msgs = list(chat_messages)
    chat_messages.clear()
    return jsonify({'messages': msgs})
```

---

## Message Flow Diagram

```
┌─────────────────────────────────────────────────────┐
│                    SENDING A CHAT                     │
│                                                       │
│  Kid5 types "hello"                                   │
│    ↓                                                  │
│  Chat Screen → MeshChatTransport.sendChat("hello")    │
│    ↓                                                  │
│  MeshChatTransport → BleMeshService.sendChatMessage() │
│    ↓                                                  │
│  BleMeshService wraps in MeshMessage:                 │
│    { from: "Kid5", type: "chat",                      │
│      payload: {"text":"hello"}, ttl: 10 }             │
│    ↓                                                  │
│  Sends to best relay (Kid3) via BLE write             │
│    ↓                                                  │
│  Kid3 receives → not bridge → forwards to Kid1        │
│    ↓                                                  │
│  Kid1 receives → IS bridge → HTTP POST /api/chat      │
│    ↓                                                  │
│  Brain receives and stores message                    │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                  RECEIVING A CHAT                     │
│                                                       │
│  Brain has new message from Kid2                      │
│    ↓                                                  │
│  Kid1 (bridge) polls GET /api/chat/messages           │
│    ↓                                                  │
│  Gets: [{ from: "Kid2", text: "hey" }]                │
│    ↓                                                  │
│  Kid1 creates MeshMessage type: "chat_broadcast"      │
│    ↓                                                  │
│  Sends to all connected peers via BLE                 │
│    ↓                                                  │
│  Each peer forwards to THEIR peers (flood)            │
│    ↓                                                  │
│  Every kid receives → MeshChatTransport converts      │
│  to WChatMessage → ChatService.addMessage()           │
│    ↓                                                  │
│  Chat Screen shows the message                        │
└─────────────────────────────────────────────────────┘
```

## Coverage Estimates

| Scenario | Per Hop | 10 Kids Chain |
|----------|---------|---------------|
| BLE 5 Long Range (open field) | ~200m | ~2km |
| BLE 5 Long Range (walls/people) | ~50-80m | ~500-800m |
| BLE 5 Regular (indoor) | ~30-50m | ~300-500m |
| BLE 4.2 fallback | ~10-20m | ~100-200m |

## Files Changed Summary

| File | Change Type | Lines |
|------|-------------|-------|
| `lib/services/ble_mesh_service.dart` | NEW | 833 |
| `lib/services/mesh_chat_transport.dart` | NEW | 355 |
| `lib/main.dart` | ADDITIVE | +15 |
| `lib/models/chat_message.dart` | ADDITIVE | +2 |
| `lib/screens/chat_screen.dart` | ADDITIVE | +60 |
| `lib/screens/connect_screen.dart` | ADDITIVE | +83 |

**Existing services untouched:** chat_service, bluetooth_connectivity, signal_strength_tracker, brain_service, voice_service, frame_service, motion_detector, background_service, speaker_controller, media_playback_controller, ios_child_control, child_os_monitor, device_policy_service
