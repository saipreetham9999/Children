# 🚀 BRAIN Project — Quick Start for Next Agent

## What Is This Project?

Local network intelligence system:
- **Brain** = iPad running Python + Flask
- **Workers** = Android/iOS apps (Poco M2 Pro, iPhone, iPad)
- **Communication** = HTTP REST API + Event Bus
- **Smarts** = Telegram bot + AI layer (not yet built)

## Current State

### ✅ What Works
- Flask HTTP API (6 endpoints, all tested)
- JoBus event bus (async pub/sub)
- Child registration and tracking
- Per-child event queue and polling
- Telegram bot integration
- Integration tests (pytest)

### 🔲 What's Missing
- Flutter Worker UI (screens)
- AI vision engine (Phase 5)
- Event logging (Phase 6)
- Resilience & reconnect (Phase 7)
- Circuit breaker & watchdog (Phase 8)

## File You Must Read First

```
/home/user/Children/BRAIN_PROJECT_HANDOFF.md
```

This document has everything. Read it completely before touching code.

## The 6 HTTP Endpoints

```
POST /api/connect      ← child registers
GET  /api/status       ← list all children
POST /api/heartbeat    ← child stays alive
GET  /api/events       ← child polls for alerts
POST /api/disconnect   ← child cleanly exits
POST /api/report       ← child sends data
```

Test them:
```bash
curl -X POST http://192.168.1.183:8080/api/connect \
  -H "Content-Type: application/json" \
  -d '{"device_name": "Test", "device_type": "test", "capabilities": []}'
```

## Run Tests

```bash
# Brain must be running on iPad first
pytest tests/test_integration.py -v
```

## Golden Rules (Never Break)

1. Every class owns one job
2. Classes never import each other directly (use JoBus)
3. Everything talks through JoBus
4. `__init__` only sets up, never starts
5. Every class has `start()` and `stop()`
6. Every class implements `AraService`
7. Depend on interface, never implementation

## Directory Structure

```
brain/
├── brain.py              ← main orchestrator
├── routes.py             ← HTTP endpoints
├── brain/
│   ├── __init__.py       ← Flask factory
│   └── settings.py       ← config
├── core/                 ← core services
├── network/              ← connection handlers
├── children/             ← device registry
├── notifications/        ← message routing
├── telegram/             ← Telegram bot
├── bus/                  ← event bus
└── tests/                ← pytest files

children/                 ← Flutter Worker app
├── lib/
│   ├── main.dart         ← Fixed: proper JSON encoding
│   └── config.dart       ← Brain IP config
└── pubspec.yaml
```

## What To Build Next

### Option 1: Flutter Worker Screens (Priority)
Build the 3 screens in `/home/user/Children/lib/`:
1. Connect (QR or manual IP)
2. Live (feed, status, alerts)
3. Settings (zones, sensitivity)

### Option 2: AI Layer (Phase 5)
Implement YOLOv8 Nano on iPad:
- `ai/sai_vision_engine.py`
- Receive frames, run inference, send alerts

### Option 3: Resilience (Phase 7)
Add reconnect logic:
- `network/ara_reconnect_manager.py`
- Child drops → rejoin → restore session

## Key Constraints

- ✅ Flask on 8080 (locked in)
- ✅ HTTP polling (WebSocket failed on iOS)
- ✅ No FastAPI (not on Pythonista)
- ✅ No async (Flask threading only)
- ✅ Manual validation (no Pydantic)

## Test Everything

```bash
# Unit test
pytest tests/test_phase1_heart.py

# Full integration (Brain must run on iPad)
pytest tests/test_integration.py -v

# Manual endpoint test
curl http://192.168.1.183:8080/api/status

# Manual Telegram test
Send /status to Telegram group
```

## Important Links

- **Full handoff**: `BRAIN_PROJECT_HANDOFF.md`
- **Main orchestrator**: `brain/brain.py`
- **HTTP routes**: `brain/routes.py`
- **Event bus**: `bus/JoBus.py`
- **Connection handler**: `network/AraConnectionManager.py`
- **Message router**: `notifications/MiniMessageRouter.py`
- **Tests**: `tests/test_integration.py`

## One-Liner Summary

> iPad Python server manages Android/iOS worker apps via HTTP API, routes events through JoBus bus, broadcasts alerts via Telegram, ready for AI layer.

---

**Next agent**: Read `BRAIN_PROJECT_HANDOFF.md` first, then pick Phase 5/6/7/8 to implement.
