# ShaRogai Children App

Flutter app that runs on each child's phone/tablet. Connects to the Brain (iPad) for monitoring, chat, and parental controls. Children without WiFi relay through nearby kids using BLE 5 mesh.

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Kid 10  │BLE │  Kid 7   │BLE │  Kid 3   │BLE │  Kid 1   │WiFi  ┌───────┐
│ (phone)  ├───>│ (phone)  ├───>│ (phone)  ├───>│ (phone)  ├─────>│ BRAIN │
│ hops: 4  │    │ hops: 3  │    │ hops: 2  │    │ bridge   │      │ (iPad)│
└──────────┘    └──────────┘    └──────────┘    └──────────┘      └───────┘
```

---

## Quick Start

### 1. Start Brain Server (iPad)

Brain must be running first. It serves the API on port `8080`.

### 2. Install on Children's Devices

```bash
flutter pub get
flutter run
```

### 3. Connect Each Child

**Option A — WiFi to Brain (bridge device):**
1. Open app → enter Brain IP (e.g. `192.168.0.183`)
2. Tap "CONNECT & CHECK"
3. Register device name → done
4. This device becomes a **bridge** (relays for other kids)

**Option B — No WiFi, connect via BLE mesh:**
1. Open app → can't reach Brain? Scroll down
2. Tap "Scan for Nearby Kids"
3. See list of nearby children with signal strength
4. Tap "Join" on the best peer (fewest hops, strongest signal)
5. Register device name → done
6. Chat messages relay through the mesh to reach Brain

---

## All Features

### Chat (Text + Voice)
- Group chat between all children
- Voice-to-text input
- Signal strength per message
- Transport indicator: `☁️` HTTP, `📡` Bluetooth, `🔗` Mesh
- Sync status: sent vs pending

### BLE 5 Mesh Network (NEW)
- 10 kids form a relay chain for text chat
- Auto-scan for nearby ShaRogai nodes (every 30s)
- Multi-hop routing with TTL (max 10 hops)
- Bridge detection (who has WiFi to Brain)
- Best relay auto-selection
- Duplicate message filtering (500 IDs tracked)
- Loop prevention via path tracking
- Routing broadcasts every 15s

### Motion Detection
- On-device camera frame comparison
- Pixel-diff threshold (15%)
- Reports to Brain via WiFi when triggered

### Voice Detection
- Speech-to-text with continuous listening
- Text-to-speech for commands from Brain
- Voice chat messages

### Media Playback
- Remote play/pause/stop from Brain
- Volume control (0-100%)
- Supports audio URLs

### Parental Controls
- Screen time limits (1h/2h/3h/4h)
- Bedtime mode with time ranges
- Content filtering (off/moderate/strict)
- App blocking/allow-listing
- Web filtering with blocked sites
- Policy violation tracking

### Device Monitoring
- Battery level + state
- OS type + version
- Network type
- App usage tracking
- Location sharing
- Connected children dashboard

### Signal Tracking
- HTTP latency monitoring
- Bluetooth RSSI tracking
- Auto-switch between transports
- Signal bars display

---

## How BLE Mesh Scanning Works

### What Each Device Does

Every child's device acts as BOTH:
- **Central** (scans for other devices)
- **Peripheral** (advertises so others can find it)

### Scan Process

```
Every 30 seconds:
  1. FlutterBluePlus.startScan(
       timeout: 15 seconds,
       withServices: [ShaRogai UUID]     ← only finds our app
     )

  2. For each discovered device:
     - Read advertisement name: "SRG:Kid3:2:0"
                                     │    │ │
                                     │    │ └─ 0=not bridge, 1=bridge
                                     │    └─── hops to Brain
                                     └──────── device name

     - Record: deviceId, rssi, hopsToBrain, isBridge

  3. Update best relay:
     - Sort peers by: fewest hops first, then strongest RSSI
     - bestRelay = first peer with hops < 99

  4. Clean stale peers (not seen in 60s)
```

### Routing Updates (Every 15 Seconds)

```
Each connected peer receives:
{
  "name": "Kid3",
  "hops": 2,
  "bridge": false,
  "peers": 3
}

This lets the whole mesh know the shortest path to Brain.
When a shorter path appears, routing updates automatically.
```

### Connection Lifecycle

```
DISCOVER → CONNECT → EXCHANGE → RELAY → DISCONNECT → RE-DISCOVER

1. DISCOVER: BLE scan finds peer advertising ShaRogai UUID
2. CONNECT:  User taps "Join" (or connectToBestRelay() called)
   - BLE connect with 15s timeout
   - Request MTU 512 for larger messages
   - Discover GATT services
   - Subscribe to message + routing characteristics
3. EXCHANGE: Send/receive mesh messages via BLE writes
4. RELAY:    Forward messages toward Brain (or away from it)
5. DISCONNECT: Peer goes out of range
   - connectionState listener fires
   - Peer marked as disconnected
   - _updateBestRelay() finds next best peer
6. RE-DISCOVER: Next scan cycle (30s) finds new peers
```

---

## What Brain Needs To Do

Brain already has these endpoints working:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/status` | GET | Check if Brain is alive |
| `/api/connect` | POST | Register a child device |
| `/api/heartbeat` | POST | Keep-alive from children |
| `/api/events` | GET | Poll for alerts/commands |
| `/api/report` | POST | Send frame/audio/text |
| `/api/disconnect` | POST | Clean disconnect |

### Brain Needs 2 NEW Endpoints

#### `POST /api/chat` — Receive mesh chat

Bridge devices relay chat messages from the mesh to Brain via this endpoint.

**Request body:**
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

If `response` is included, it gets sent back through the mesh to the originating device.

#### `GET /api/chat/messages` — Send messages to mesh

Bridge devices poll this every 5 seconds. Any messages returned get broadcast to all children via mesh.

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

**Important:** Return messages once only. Bridge polls every 5s — if you return the same messages again, they'll be broadcast again (though dedup on devices will catch most duplicates).

### Brain Implementation Example (Python)

```python
from flask import Flask, request, jsonify
from datetime import datetime
from collections import deque

app = Flask(__name__)

# ── Existing endpoints (already working) ──────────────────
connected_devices = {}
pending_events = {}

@app.route('/api/status', methods=['GET'])
def status():
    return jsonify({
        'status': 'online',
        'connected_devices': len(connected_devices),
        'devices': list(connected_devices.keys())
    })

@app.route('/api/connect', methods=['POST'])
def connect():
    data = request.json
    name = data.get('device_name', 'unknown')
    connected_devices[name] = {
        **data,
        'connected_at': datetime.now().isoformat(),
        'via_mesh': data.get('via_mesh', False)
    }
    print(f"[Brain] Device connected: {name}")
    return jsonify({'status': 'connected', 'device_name': name})

@app.route('/api/heartbeat', methods=['POST'])
def heartbeat():
    data = request.json
    name = data.get('device_name', 'unknown')
    via_mesh = data.get('via_mesh', False)
    if name in connected_devices:
        connected_devices[name]['last_heartbeat'] = datetime.now().isoformat()
        connected_devices[name]['via_mesh'] = via_mesh
    return jsonify({'status': 'ok'})

@app.route('/api/events', methods=['GET'])
def events():
    name = request.args.get('device_name', '')
    device_events = pending_events.pop(name, [])
    return jsonify({'events': device_events})

@app.route('/api/report', methods=['POST'])
def report():
    data = request.json
    report_type = data.get('type', 'unknown')
    device = data.get('device_name', 'unknown')
    print(f"[Brain] Report from {device}: {report_type}")
    return jsonify({'status': 'received'})

@app.route('/api/disconnect', methods=['POST'])
def disconnect():
    data = request.json
    name = data.get('device_name', 'unknown')
    connected_devices.pop(name, None)
    print(f"[Brain] Device disconnected: {name}")
    return jsonify({'status': 'disconnected'})

# ── NEW: Chat endpoints for BLE mesh ─────────────────────
chat_outbox = deque(maxlen=100)     # Messages to broadcast to mesh
chat_history = deque(maxlen=500)    # Full chat log

@app.route('/api/chat', methods=['POST'])
def receive_chat():
    """Receive a chat message relayed through the mesh."""
    data = request.json
    msg = {
        'from': data.get('from_device', 'Unknown'),
        'text': data.get('text', ''),
        'via_mesh': data.get('via_mesh', False),
        'hops': data.get('hops', 0),
        'path': data.get('path', []),
        'timestamp': datetime.now().isoformat()
    }

    chat_history.append(msg)
    # Also add to outbox so other children see it
    chat_outbox.append(msg)

    print(f"[Chat] {msg['from']}: {msg['text']} "
          f"({'mesh ' + str(msg['hops']) + ' hops' if msg['via_mesh'] else 'direct'})")

    return jsonify({'status': 'ok'})

@app.route('/api/chat/messages', methods=['GET'])
def get_chat_messages():
    """Return pending messages for mesh broadcast. Clears after reading."""
    msgs = list(chat_outbox)
    chat_outbox.clear()
    return jsonify({'messages': msgs})

@app.route('/api/chat/send', methods=['POST'])
def send_chat():
    """Brain sends a message to all children (parent types on iPad)."""
    data = request.json
    msg = {
        'from': 'Brain',
        'text': data.get('text', ''),
        'timestamp': datetime.now().isoformat()
    }
    chat_history.append(msg)
    chat_outbox.append(msg)
    print(f"[Chat] Brain: {msg['text']}")
    return jsonify({'status': 'sent'})

@app.route('/api/chat/history', methods=['GET'])
def chat_history_endpoint():
    """Get recent chat history (for Brain UI)."""
    limit = int(request.args.get('limit', 50))
    msgs = list(chat_history)[-limit:]
    return jsonify({'messages': msgs, 'total': len(chat_history)})

if __name__ == '__main__':
    print("[Brain] Starting on port 8080...")
    app.run(host='0.0.0.0', port=8080, debug=True)
```

---

## Message Flow: Kid Sends Chat

```
Kid5 types "hello" and taps Send
         │
         ▼
┌─ Chat Screen ────────────────────────┐
│ meshTransport.sendChat("hello")      │
│   ↓                                  │
│ meshService.sendChatMessage("hello") │
│   ↓                                  │
│ Wraps in MeshMessage:                │
│  { id: "17088..._Kid5",             │
│    from: "Kid5",                     │
│    type: "chat",                     │
│    payload: {"text":"hello"},        │
│    ttl: 10,                          │
│    path: ["Kid5"] }                  │
│   ↓                                  │
│ Not a bridge → send to bestRelay     │
└──────────────────────────────────────┘
         │ BLE write to Kid3
         ▼
┌─ Kid3 (relay) ───────────────────────┐
│ _handleIncomingData()                │
│  - Not duplicate? ✓                  │
│  - TTL > 0? ✓ (9 remaining)         │
│  - type == 'chat':                   │
│    → onMessageReceived (show locally)│
│    → Not bridge → _forwardMessage    │
│    → Decrement TTL, add to path      │
└──────────────────────────────────────┘
         │ BLE write to Kid1
         ▼
┌─ Kid1 (bridge) ──────────────────────┐
│ _handleIncomingData()                │
│  - type == 'chat':                   │
│    → onMessageReceived (show locally)│
│    → IS bridge → onRelayRequest      │
│   ↓                                  │
│ _handleRelayRequest()                │
│  - HTTP POST /api/chat               │
│    { from_device: "Kid5",            │
│      text: "hello",                  │
│      via_mesh: true,                 │
│      hops: 3,                        │
│      path: ["Kid5","Kid3","Kid1"] }  │
└──────────────────────────────────────┘
         │ HTTP
         ▼
┌─ Brain (iPad) ───────────────────────┐
│ Receives chat, stores in history     │
│ Adds to outbox for broadcast         │
│ Returns { status: "ok" }             │
└──────────────────────────────────────┘
```

## Message Flow: Brain Broadcasts to Mesh

```
Brain has messages in outbox
         │
         ▼
┌─ Kid1 (bridge) ──────────────────────┐
│ _pollBrainForChat() every 5s         │
│  - GET /api/chat/messages            │
│  - Gets: [{ from:"Kid2", text:"yo" }]│
│   ↓                                  │
│ Creates MeshMessage:                 │
│  { type: "chat_broadcast",           │
│    from: "Kid2",                     │
│    to: "all" }                       │
│   ↓                                  │
│ sendMessage → sends to all peers     │
└──────────────────────────────────────┘
         │ BLE write to Kid3, Kid2, ...
         ▼
┌─ Kid3 (relay) ───────────────────────┐
│ type == 'chat_broadcast':            │
│  → Show locally in chat              │
│  → Forward to all OTHER peers        │
│    (excludes Kid1 who sent it)       │
│    (excludes anyone already in path) │
└──────────────────────────────────────┘
         │ BLE to Kid5, Kid7, ...
         ▼
  Every kid in mesh sees the message
```

---

## Coverage Estimates

| Scenario | Per Hop | 10 Kids Chain |
|----------|---------|---------------|
| BLE 5 Long Range (open field) | ~200m | ~2km |
| BLE 5 Long Range (walls, people) | ~50-80m | ~500-800m |
| BLE 5 Regular (indoor) | ~30-50m | ~300-500m |
| BLE 4.2 fallback | ~10-20m | ~100-200m |

---

## Project Structure

```
lib/
├── main.dart                          # App bootstrap, providers, routing
├── config.dart                        # Configuration
│
├── models/
│   ├── chat_message.dart              # Chat message (sender, text, signal, transport)
│   ├── device_model.dart              # Device info (name, type, OS, capabilities)
│   └── alert_model.dart               # Alert/event from Brain
│
├── services/
│   ├── brain_service.dart             # HTTP API to Brain (/connect, /heartbeat, /events, /report)
│   ├── chat_service.dart              # In-memory group chat (200 messages, sync timer)
│   ├── ble_mesh_service.dart          # BLE 5 mesh network (scan, connect, route, relay)
│   ├── mesh_chat_transport.dart       # Glue: mesh ↔ chat ↔ Brain HTTP
│   ├── bluetooth_connectivity.dart    # General BLE device discovery + RSSI
│   ├── signal_strength_tracker.dart   # HTTP latency + BLE RSSI monitoring
│   ├── voice_service.dart             # Speech-to-text + text-to-speech
│   ├── frame_service.dart             # Camera frame capture + JPEG compression
│   ├── motion_detector.dart           # Pixel-diff motion detection
│   ├── background_service.dart        # Android/iOS background heartbeat
│   ├── media_playback_controller.dart # Audio playback (just_audio)
│   ├── speaker_controller.dart        # System volume control
│   ├── ios_child_control.dart         # iOS Screen Time + content filter
│   ├── child_os_monitor.dart          # Device monitoring (battery, apps, location)
│   ├── device_policy_service.dart     # Policy enforcement (screen time, bedtime, web)
│   └── ios_audio_session.dart         # iOS audio session native bridge
│
├── screens/
│   ├── connect_screen.dart            # Brain IP entry + BLE mesh join
│   ├── register_screen.dart           # Device registration
│   ├── main_screen.dart               # Dashboard (toggles, status, alerts)
│   ├── chat_screen.dart               # Group chat with mesh status bar
│   ├── child_control_screen.dart      # Parental controls UI
│   ├── ipad_chat_screen.dart          # iPad-optimized chat layout
│   └── transition_screen.dart         # Loading transition
│
└── widgets/
    ├── status_indicator.dart          # Status display widget
    └── alert_card.dart                # Alert card widget
```

---

## Providers (main.dart)

| Provider | Service | Purpose |
|----------|---------|---------|
| `WChatService` | chat_service.dart | Message storage + sync |
| `WSignalStrengthTracker` | signal_strength_tracker.dart | Signal quality |
| `WSpeakerController` | speaker_controller.dart | Volume control |
| `WBluetoothConnectivity` | bluetooth_connectivity.dart | BLE device discovery |
| `WMediaPlaybackController` | media_playback_controller.dart | Audio playback |
| `WiOSChildControl` | ios_child_control.dart | Parental controls |
| `WChildOSMonitor` | child_os_monitor.dart | Device monitoring |
| `WDevicePolicyService` | device_policy_service.dart | Policy enforcement |
| `WBleMeshService` | ble_mesh_service.dart | BLE mesh network |
| `WMeshChatTransport` | mesh_chat_transport.dart | Mesh-to-chat bridge |

---

## Boot Sequence

```
1. Request permissions (camera, mic, location, bluetooth)
2. Initialize ChatService (sync timer starts)
3. Initialize SignalStrengthTracker
4. Initialize BackgroundService (foreground service)
5. Initialize SpeakerController (system volume)
6. Initialize MediaPlaybackController (just_audio)
7. Initialize BluetoothConnectivity (adapter state listener)
8. Initialize iOS ChildControl (Screen Time)
9. Initialize ChildOSMonitor
10. Initialize DevicePolicyService (default policies)
11. Initialize VoiceService (TTS + STT)
12. Initialize BLE Mesh:
    - Create WBleMeshService
    - Create WMeshChatTransport (wires mesh ↔ chat ↔ signal)
    - Detect bridge capability (can reach Brain via HTTP?)
    - Start BLE scanning for ShaRogai peers
    - Start routing broadcasts
    - If bridge: start Brain chat polling
    - If not bridge: start mesh heartbeat relay
13. Show app UI
```

---

## Brain API Reference

| Method | Endpoint | Body | Response | Used By |
|--------|----------|------|----------|---------|
| GET | `/api/status` | — | `{status, connected_devices, devices}` | ConnectScreen, MeshChatTransport |
| POST | `/api/connect` | `{device_name, device_type, os_version, ...}` | `{status, device_name}` | RegisterScreen, mesh relay |
| POST | `/api/heartbeat` | `{device_name, via_mesh?}` | `{status}` | MainScreen, mesh relay |
| GET | `/api/events` | `?device_name=X` | `{events: [...]}` | MainScreen |
| POST | `/api/report` | `{device_name, type, data, context}` | `{status}` | MainScreen (frame/audio) |
| POST | `/api/disconnect` | `{device_name}` | `{status}` | MainScreen |
| **POST** | **`/api/chat`** | `{from_device, text, via_mesh, hops, path}` | `{status, response?}` | **MeshChatTransport (bridge relay)** |
| **GET** | **`/api/chat/messages`** | — | `{messages: [...]}` | **MeshChatTransport (bridge poll)** |
| **POST** | **`/api/chat/send`** | `{text}` | `{status}` | **Brain UI (parent sends message)** |
| **GET** | **`/api/chat/history`** | `?limit=50` | `{messages, total}` | **Brain UI (view chat log)** |

**Bold = NEW** endpoints Brain needs to add.

---

## Dependencies

```yaml
flutter_blue_plus: ^1.34.0       # BLE scanning, connection, GATT
provider: ^6.1.2                  # State management
http: ^1.2.2                      # HTTP requests to Brain
shared_preferences: ^2.3.2       # Local storage (brain_url, device_name)
camera: ^0.11.0+1                # Frame capture
image: ^4.3.0                    # Image compression
just_audio: ^0.9.40              # Audio playback
flutter_tts: ^4.2.2              # Text-to-speech
speech_to_text: ^7.0.0           # Voice recognition
permission_handler: ^11.3.1      # Runtime permissions
device_info_plus: ^11.1.0        # Device info
battery_plus: ^6.1.0             # Battery monitoring
flutter_background_service: ^5.0.0  # Background tasks
volume_controller: ^2.0.3        # System volume
intl: ^0.20.1                    # Date formatting
```
