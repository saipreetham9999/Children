# 🧠 PROJECT BRAIN — Complete Handoff Document

**Project Status**: Phase 4 Complete ✅ | Ready for Phase 5
**Last Updated**: February 15, 2025
**Branch**: `claude/understand-flutter-worker-app-bMsKG`

---

## 📋 Executive Summary

**BRAIN** is a local network intelligence system with:
- **Brain** = iPad (Python + Flask on port 8080)
- **Workers** = Android/iOS apps (Poco M2 Pro, iPhone, iPad)
- **Communication** = HTTP REST API + JoBus event bus
- **Intelligence** = Telegram bot + AI layer (pending)
- **Always On** = Pythonista on iPad, battery plugged in, screen on

**What's Built & Working**:
- ✅ Flask HTTP API (6 endpoints)
- ✅ JoBus event bus (async pub/sub)
- ✅ Connection lifecycle (connect/heartbeat/disconnect)
- ✅ Child registry (device profiles, capabilities)
- ✅ Event queue per child (MiniMessageRouter)
- ✅ Telegram bot (always listening, alerts only)
- ✅ Integration tests (pytest)

**What's Next**:
- 🔲 Flutter Worker app (partially done in `/lib/`)
- 🔲 AI layer (Sai Vision Engine)
- 🔲 Event logging and snapshots
- 🔲 Resilience (reconnect, fallback, health check)
- 🔲 Circuit breaker and retry logic

---

## 🏗️ Architecture Overview

### The Four Characters

| Owner | Responsibility | Files |
|-------|---|---|
| **Ara** | Brain core, infrastructure, connections | `core/`, `network/`, `children/` |
| **Jo** | Event bus, logging, circuit breaker | `bus/JoBus.py`, future logging |
| **Sai** | AI, vision, detection, models | `ai/` (not yet built) |
| **Mini** | Notifications, Telegram, message routing | `telegram/`, `notifications/` |

### Seven Golden Rules (Never Break These)

1. **Every class owns one job** — single responsibility
2. **Classes never import each other directly** — all via JoBus
3. **Everything talks through JoBus** — event-driven architecture
4. **`__init__` only sets up, never starts work** — delayed initialization
5. **`start()` and `stop()` on every class** — lifecycle management
6. **Every class implements AraService** — interface contract
7. **Depend on interface, never implementation** — loose coupling

---

## 📁 Folder Structure (Current)

```
brain/                                 ← Main project folder
├── main.py                            ← Entry point
├── run.py                             ← Runner script
├── supervisor.py                      ← Auto restart watchdog
│
├── brain/                             ← Flask app
│   ├── __init__.py                    ← Flask factory (create_app())
│   ├── brain.py                       ← Brain orchestrator (boots all services)
│   ├── routes.py                      ← HTTP endpoints (6 routes)
│   └── settings.py                    ← Config (tokens, chat ID)
│
├── bus/
│   └── JoBus.py                       ← Event bus (publish/subscribe)
│
├── core/                              ← Core services
│   ├── AraService.py                  ← Base interface
│   ├── AraSessionManager.py           ← Session lifecycle
│   └── (future) AraRetryManager.py
│   └── (future) AraWatchdog.py
│
├── network/                           ← Network layer
│   ├── AraConnectionManager.py        ← HTTP child connection handler
│   └── (future) AraHealthChecker.py
│   └── (future) AraReconnectManager.py
│   └── (future) AraFallbackHandler.py
│
├── children/                          ← Device registry
│   ├── AraChildManager.py             ← Child registry
│   ├── AraChildProfile.py             ← Device profile + capabilities
│   └── AraChildStatus.py              ← Device state tracker
│
├── notifications/                     ← Message routing
│   └── MiniMessageRouter.py           ← Per-child event queue
│
├── telegram/                          ← Telegram integration
│   ├── MiniTelegramBot.py             ← Bot listener (polling)
│   └── MiniTelegramCommand.py         ← Command handler (/status, /hello)
│
├── storage/                           ← (Future) Persistence
│   ├── (future) JoEventLogger.py
│   └── (future) SaiSnapshotManager.py
│
└── tests/
    ├── test_phase1_heart.py           ← Boot test
    ├── test_telegram_message.py       ← Telegram test
    └── test_integration.py            ← Full flow test (pytest)

children/                              ← Flutter Worker app
├── lib/
│   ├── main.dart                      ← Fixed: 415 error, proper JSON encoding
│   └── config.dart                    ← IP configuration
└── pubspec.yaml                       ← Dependencies
```

---

## 🔗 HTTP Endpoints (All Working)

### 1. Connect — Child registers with Brain

```http
POST /api/connect
Content-Type: application/json

{
  "device_name": "Poco M2 Pro",
  "device_type": "android",
  "capabilities": ["camera", "screen", "audio"],
  "token": null
}

Response: 200 OK
{
  "status": "connected",
  "session_id": "uuid-here",
  "device_id": "poco-001"
}
```

**Flow**:
- Child sends identity
- Brain creates session (AraSessionManager)
- Brain registers child (AraChildManager)
- JoBus publishes `child.connection.requested`
- MiniMessageRouter creates queue for this child

---

### 2. Status — Get all connected children

```http
GET /api/status

Response: 200 OK
{
  "status": "online",
  "children": [
    {
      "device_name": "Poco M2 Pro",
      "device_type": "android",
      "capabilities": ["camera", "screen", "audio"]
    },
    {
      "device_name": "iPhone 14",
      "device_type": "ios",
      "capabilities": ["camera", "screen", "audio", "haptic"]
    }
  ]
}
```

---

### 3. Heartbeat — Child keeps alive

```http
POST /api/heartbeat
Content-Type: application/json

{
  "device_name": "Poco M2 Pro"
}

Response: 200 OK
{
  "status": "ok"
}
```

**Rule**: Child sends every 5 seconds. Brain tracks last heartbeat. If no heartbeat for 30 seconds → mark lost.

---

### 4. Events — Child polls for messages

```http
GET /api/events?device_name=Poco M2 Pro

Response: 200 OK
{
  "status": "ok",
  "events": [
    {
      "type": "child_connected",
      "device_name": "iPhone 14",
      "timestamp": "2025-02-15T10:30:45Z"
    },
    {
      "type": "alert",
      "severity": "high",
      "message": "Person detected in zone 1",
      "timestamp": "2025-02-15T10:31:00Z"
    }
  ]
}
```

**How It Works**:
1. Brain puts messages in queue for each child (MiniMessageRouter)
2. Child polls `/api/events` every 2 seconds
3. Brain returns pending messages
4. Queue clears after delivery

---

### 5. Disconnect — Child cleanly exits

```http
POST /api/disconnect
Content-Type: application/json

{
  "device_name": "Poco M2 Pro"
}

Response: 200 OK
{
  "status": "disconnected"
}
```

**Flow**:
- Child gracefully leaves
- Brain removes session
- Brain publishes `child.disconnected` to JoBus
- Other children notified via event queue

---

### 6. Report — Child sends data/frames

```http
POST /api/report
Content-Type: application/json

{
  "device_name": "Poco M2 Pro",
  "type": "frame",
  "data": "base64-encoded-image-or-json"
}

Response: 200 OK
{
  "status": "received"
}
```

**Future**: AI layer will subscribe to `child.report.received` and process frames.

---

## 🚌 JoBus Events — What Flows Where

### Published Events

| Event | Published By | Subscribers |
|-------|---|---|
| `child.connection.requested` | AraConnectionManager | AraSessionManager, AraChildManager |
| `session.created` | AraSessionManager | MiniMessageRouter, (future: logging) |
| `child.heartbeat` | AraConnectionManager | (future: health monitoring) |
| `child.disconnected` | AraConnectionManager | MiniMessageRouter, (future: logging) |
| `child.report.received` | routes.py | (future: SaiVisionEngine) |
| `alert.triggered` | (future: SaiAlertRules) | MiniTelegramCommand, MiniMessageRouter |
| `telegram.command` | MiniTelegramBot | MiniTelegramCommand |

### Example Flow: Child Connects

```
1. Poco sends POST /api/connect
   └── AraConnectionManager.handle_connect()
       └── JoBus.publish("child.connection.requested", identity)

2. Subscribers react:
   a) AraSessionManager.start() listens
      └── creates session record
      └── JoBus.publish("session.created", session_data)

   b) AraChildManager.start() listens
      └── registers child in registry

   c) MiniMessageRouter.start() listens (to session.created)
      └── creates event queue for this child

3. Other children poll /api/events
   └── MiniMessageRouter returns pending events
   └── Poco M2 Pro sees "iPhone 14 connected"
```

---

## 🔔 Telegram Integration

### What Telegram Receives

```
Only these messages:

1. Brain boot:
   "🟢 Brain Online"

2. Commands:
   /status      → "🧠 Brain Status: Online\n🔗 Connected Children: 2\n..."
   /hello       → "Hello there! How can I help you?"
   /children    → (future) list all devices

3. Alerts (future):
   "🚨 ALERT: Person detected in zone 1"
   "📸 [snapshot attached]"
```

### What Telegram NEVER Receives

- ❌ Connect/disconnect noise
- ❌ Heartbeat activity
- ❌ Internal logs
- ❌ Raw debug output

**Implementation**: MiniTelegramCommand subscribes only to `alert.triggered` and `telegram.command`.

---

## ✅ What Is Built and Working

### Phase 1 — Heart

- ✅ JoBus (publish/subscribe)
- ✅ AraService (base interface)
- ✅ Config management
- ✅ main.py boots everything

**Test**: `pytest tests/test_phase1_heart.py`

### Phase 2 — Spine

- ✅ HTTP endpoints (Flask on 8080)
- ✅ Child registration (AraChildManager)
- ✅ Session lifecycle (AraSessionManager)
- ✅ Connection handler (AraConnectionManager)
- ✅ Device profiles (AraChildProfile)

**Test**: `pytest tests/test_integration.py -v`

### Phase 3 — Telegram

- ✅ MiniTelegramBot (always listening via polling)
- ✅ MiniTelegramCommand (/status, /hello)
- ✅ Sends "Brain Online" on boot
- ✅ Receives and broadcasts commands

**Test**: Manual — send /status in Telegram group

### Phase 4 — Event Queue

- ✅ MiniMessageRouter (per-child queue)
- ✅ /api/events endpoint
- ✅ Events queue and deliver correctly
- ✅ Queue clears after delivery

**Test**: `pytest tests/test_integration.py::TestEventQueue -v`

---

## 🔲 What Is NOT Built Yet

### Phase 5 — AI Layer

```python
ai/
├── sai_vision_engine.py      ← YOLOv8 Nano inference on iPad
├── sai_model_store.py        ← Load CoreML models
├── sai_tier_manager.py       ← Tier 1 iPad, Tier 2 iPhone helper
└── sai_alert_rules.py        ← Detection policies, confidence thresholds
```

**What It Does**:
- Receives frame from `child.report.received`
- Runs inference (person detection, zones, anomaly)
- Returns decision object:
  ```json
  {
    "person_present": true,
    "count": 1,
    "zone": 2,
    "motion_level": "medium",
    "anomaly": false,
    "confidence": 0.91,
    "processed_by": "ipad_local"
  }
  ```
- Publishes `alert.triggered` if confidence > 0.7

### Phase 6 — Memory

```python
storage/
├── jo_event_logger.py        ← Log all events
└── sai_snapshot_manager.py   ← Save frame on anomaly
```

### Phase 7 — Resilience

```python
network/
├── ara_health_checker.py     ← Monitor service health
├── ara_reconnect_manager.py  ← Child drop → rejoin → restore session
└── ara_fallback_handler.py   ← WiFi fallback logic
```

### Phase 8 — Shields

```python
core/
├── ara_retry_manager.py      ← Exponential backoff on network calls
└── ara_watchdog.py           ← Auto restart services
storage/
└── jo_circuit_breaker.py     ← Stop calling failed services
```

---

## 📱 Flutter Worker App (Partially Built)

### Current Status

**Location**: `/home/user/Children/lib/`

**Files**:
- ✅ `main.dart` — Fixed! HTTP 415 error resolved, proper JSON encoding
- ✅ `config.dart` — Brain IP configuration
- ❌ `pubspec.yaml` — Dependencies added

**What's Fixed**:
```dart
// ❌ OLD (caused HTTP 415)
body: data.toString()

// ✅ NEW (proper JSON)
headers: {"Content-Type": "application/json"},
body: jsonEncode(heartbeatData)
```

**What's Working**:
- Starts background service on app launch
- Requests permissions (location, camera, notification)
- Registers with Brain via `/api/connect`
- Sends heartbeats every 5 seconds to `/api/heartbeat`
- Gets device info (model, OS type) automatically

**What's Missing**:
- Screen 1: Connect (QR scan or manual IP)
- Screen 2: Live (feed, status, alerts)
- Screen 3: Settings (zones, sensitivity)
- Polling `/api/events` for alerts

### Screens to Build

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   CONNECT       │ →  │    LIVE         │ →  │  SETTINGS       │
│                 │    │                 │    │                 │
│ QR Scan         │    │ Camera feed     │    │ Sensitivity     │
│ or              │    │ Status dot      │    │ Zones           │
│ Manual IP       │    │ Alert log       │    │ Camera select   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

## 🧪 How to Test Everything

### 1. Start Brain (on iPad)

```bash
# On iPad Pythonista
python main.py
# Should print:
# 🧠 BRAIN BOOTING...
# 🟢 BRAIN ONLINE
# [MiniTelegramBot] Started...
```

### 2. Run Integration Tests

```bash
# On your development machine (PyCharm)
pytest tests/test_integration.py -v

# Tests cover:
# - Brain reachable ✅
# - Connect / status / heartbeat ✅
# - Disconnect ✅
# - Event queue (two devices trigger events) ✅
# - Queue clears after poll ✅
# - Report accepted ✅
```

### 3. Test Endpoints with curl

```bash
# 1. Connect
curl -X POST http://192.168.1.183:8080/api/connect \
  -H "Content-Type: application/json" \
  -d '{"device_name": "Poco", "device_type": "android", "capabilities": ["camera"]}'

# 2. Status
curl http://192.168.1.183:8080/api/status

# 3. Heartbeat
curl -X POST http://192.168.1.183:8080/api/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"device_name": "Poco"}'

# 4. Events (Poco polls this every 2s)
curl "http://192.168.1.183:8080/api/events?device_name=Poco"

# 5. Disconnect
curl -X POST http://192.168.1.183:8080/api/disconnect \
  -H "Content-Type: application/json" \
  -d '{"device_name": "Poco"}'
```

### 4. Test in Telegram

Send `/status` in your Telegram group where the bot is. Brain should reply with connected children.

---

## 🎯 Next Steps for Next Agent

### Priority 1: Stable Flutter App

Build the three screens for Worker app in `/home/user/Children/lib/`:

```
1. Connect Screen
   ├── QR scanner (scan QR from Brain iPad)
   ├── Manual IP entry (fallback)
   └── Submit → hits /api/connect, saves Brain IP

2. Live Screen
   ├── Connection status (dot: green/red/yellow)
   ├── Polling /api/events every 2s
   ├── Display alerts when received
   └── Show last sync time

3. Settings Screen
   ├── Zone definitions
   ├── Sensitivity slider
   ├── Camera selection
   └── Delete app data button
```

### Priority 2: Add AI Layer (Phase 5)

```python
ai/sai_vision_engine.py
├── load YOLOv8 Nano model on iPad
├── receive frame from child.report.received
├── run inference
└── publish alert.triggered if confidence > 0.7
```

### Priority 3: Add Resilience (Phase 7)

```python
network/ara_reconnect_manager.py
├── Track child timeouts
├── Attempt reconnect every 5 seconds
├── Restore session if rejoins within 5 minutes
└── Clean up old sessions after 5 minutes
```

---

## 🔑 Key Facts to Remember

1. **Flask runs on 8080** — Do not change
2. **WebSocket failed on iPad** — HTTP polling works perfectly
3. **Pythonista limitation** — No FastAPI, no Pydantic, manual validation only
4. **No async in Brain** — Flask threading model only
5. **JoBus is the backbone** — Everything goes through it
6. **Telegram is read-only** — Bot only polls, never pushes
7. **Every service must implement AraService** — start(), stop(), status()
8. **No direct imports** — All communication through JoBus

---

## 📞 Troubleshooting

| Problem | Solution |
|---------|----------|
| HTTP 415 (Unsupported Media Type) | Check `Content-Type: application/json` header and `jsonEncode()` body |
| Brain not reachable | Check iPad IP in config, verify WiFi connection |
| Poco not registering | Check /api/status endpoint, verify device_name sent |
| Events not flowing | Check MiniMessageRouter queue creation, verify /api/events polling |
| Telegram bot silent | Check TELEGRAM_TOKEN, TELEGRAM_CHAT_ID in settings.py, verify polling running |
| Tests fail with timeout | Brain must be running on iPad first before pytest |

---

## 📚 References

- **Main entry**: `brain/main.py` → `brain/brain.py` → `brain/routes.py`
- **Event flow**: `bus/JoBus.py` (publish/subscribe)
- **Connection lifecycle**: `network/AraConnectionManager.py`
- **Child registry**: `children/AraChildManager.py`
- **Message routing**: `notifications/MiniMessageRouter.py`
- **Tests**: `tests/test_integration.py`

---

## ✨ Summary for Any Claude Agent

> **The BRAIN project is a local network intelligence system where an iPad (Python + Flask) acts as a server, managing multiple Worker devices (Android/iOS apps) that send sensor data and receive alerts. The system is built on a JoBus event bus, uses HTTP REST API for communication, and integrates with Telegram for external notifications. Phases 1-4 are complete with working endpoints and event routing. Next steps are: (1) Build Flutter UI screens for Worker app, (2) Implement AI vision layer on iPad, (3) Add resilience and failover logic.**

---

**Last Updated**: 2025-02-15 by Claude
**Status**: Ready for Phase 5 implementation
**Contact**: Review `brain/brain.py` for architecture understanding
