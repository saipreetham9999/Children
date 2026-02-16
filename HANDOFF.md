# 🎯 FLUTTER WORKER APP — Complete Handoff Document

**Project**: BRAIN — Local Network Intelligence System
**Component**: Worker App (Flutter)
**Status**: Phase 2 — Device Connection ✅
**Last Updated**: 2025-02-15

---

## 📱 What This App Does

The Flutter Worker App is a **client device** that:

1. **Registers with Brain** (Python/Flask server on iPad Air)
2. **Sends heartbeats every 5 seconds** with:
   - Battery level
   - GPS location (latitude, longitude)
   - Timestamp
   - Device metadata (model, type)
3. **Listens for events** (alerts, commands from Brain/other workers)
4. **Runs in background** (foreground service on Android, background on iOS)

**Device Supported**:
- Android phones/tablets (tested: Poco M2 Pro)
- iOS phones/tablets (iPhone, iPad)

---

## 🏗️ Architecture

### Connection Flow
```
┌──────────────────────────────────────────────────────────┐
│ 1. Worker App Starts (main.dart:onStart)                 │
│    ├─ Request permissions (location, camera, notif)      │
│    ├─ Get device info (name, type, model)                │
│    └─ Start background service                           │
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│ 2. Register with Brain (POST /api/connect)               │
│    {                                                      │
│      "device_name": "Poco M2 Pro",                       │
│      "device_type": "android",                           │
│      "capabilities": ["camera", "location", "battery"],  │
│      "token": null                                       │
│    }                                                      │
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│ 3. Brain Responds (200 OK)                               │
│    ├─ Creates session for device                         │
│    ├─ Publishes "child.connected" event                  │
│    └─ Creates event queue for this device                │
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│ 4. Send Heartbeats Every 5 Seconds (Timer.periodic)      │
│    POST /api/heartbeat with JSON body + headers          │
│    {                                                      │
│      "deviceId": "Poco-M2-Pro",                          │
│      "battery": 87,                                      │
│      "location": "12.9716,77.5946",                      │
│      "timestamp": "2025-02-15T10:30:45.123Z"             │
│    }                                                      │
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│ 5. Poll for Events (Future: POST /api/events)            │
│    Get messages from Brain/other workers                 │
│    Clear queue after reading                             │
└──────────────────────────────────────────────────────────┘
```

---

## 📂 File Structure

```
lib/
├── main.dart           ← Main app, background service, heartbeat logic
├── config.dart         ← Configuration (IP, port, device ID, intervals)
└── pubspec.yaml        ← Dependencies
```

### Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_background_service` | ^5.0.0 | Run app in background |
| `http` | ^1.2.0 | HTTP requests to Brain |
| `battery_plus` | ^6.0.0 | Get device battery level |
| `geolocator` | ^12.0.0 | Get GPS location |
| `device_info_plus` | ^10.1.0 | Get device model/info |
| `permission_handler` | ^11.3.0 | Request permissions |
| `camera` | ^0.11.0+1 | (Placeholder for Phase 5 AI) |

---

## 🔧 Configuration (config.dart)

```dart
class Config {
  static const String brainIp = "192.168.0.183";     // Brain iPad IP
  static const int port = 8080;                      // Flask port
  static const String baseUrl = "http://$brainIp:$port/api";
  static const String deviceId = "Poco-M2-Pro";      // Device identifier
  static const int heartbeatInterval = 5;             // Seconds between heartbeats
}
```

**TO CHANGE IP FOR YOUR SETUP:**
1. Find Brain iPad's IP (Settings → Wi-Fi)
2. Edit `config.dart` line 2: `brainIp = "YOUR_IP_HERE"`
3. Rebuild and reinstall app

---

## 🚀 What Happens at Each Stage

### 1. App Launch (main.dart:main)
```dart
void main() async {
  // Initialize Flutter bindings
  // Request location, camera, notification permissions
  // Initialize background service
  // Launch UI
}
```

### 2. Background Service Initialization (main.dart:initializeService)
```dart
await service.configure(
  androidConfiguration: ...,  // Foreground service for Android
  iosConfiguration: ...,      // Background task for iOS
);
service.startService();       // Start immediately
```

### 3. Service Starts (main.dart:onStart)
When service starts:
1. **Get device info** (model, type)
2. **POST to /api/connect** with device identity
   - This registers the device with Brain
   - Brain creates a session + event queue
3. **Start Timer.periodic** every 5 seconds
   - Get battery level
   - Get GPS location (with 10s timeout)
   - Send POST to /api/heartbeat with JSON body
   - Log response status

---

## 🐛 Previous Issues & Fixes

### Issue #1: HTTP 415 (Unsupported Media Type)
**Root Cause**: Sending `body: data.toString()` instead of JSON
```dart
// ❌ WRONG (old code)
body: data.toString()  // Sends "{deviceId: Poco-M2-Pro, ...}"

// ✅ FIXED (new code)
headers: {"Content-Type": "application/json"},
body: jsonEncode(heartbeatData)  // Sends valid JSON
```

### Issue #2: No Device Registration
**Root Cause**: Skipped `/api/connect` call
```dart
// ✅ FIXED
// Now sends device identity first:
POST /api/connect with device_name, device_type, capabilities
// Brain registers device and creates event queue
```

### Issue #3: Hardcoded Device ID
**Root Cause**: Used fixed string "Poco-M2-Pro"
```dart
// ✅ FIXED
// Now uses device_info_plus to get actual device model
final android = await deviceInfo.androidInfo;
deviceName = android.model;  // Gets real device name
```

---

## 📡 HTTP Endpoints Called

| Endpoint | Method | Purpose | Status |
|----------|--------|---------|--------|
| `/api/connect` | POST | Register device with Brain | ✅ Working |
| `/api/heartbeat` | POST | Send battery + location every 5s | ✅ Working |
| `/api/events` | GET | Poll for alerts/commands | ⏳ Future |
| `/api/disconnect` | POST | Clean exit (optional) | ⏳ Future |
| `/api/status` | GET | Check if Brain is online | ✅ Working (UI) |

---

## 📊 Heartbeat Payload Example

```json
{
  "deviceId": "Poco-M2-Pro",
  "battery": 87,
  "location": "12.9716,77.5946",
  "timestamp": "2025-02-15T10:30:45.123Z"
}
```

**Sent as**: `Content-Type: application/json`
**Interval**: Every 5 seconds
**Expected Response**: HTTP 200 OK

---

## 🔄 How Brain Processes Heartbeats

1. **POST /api/heartbeat** received by Brain (Flask)
2. Brain reads payload and updates device session
3. Brain publishes to JoBus: `child.report.received` event
4. Other workers can see this device is alive via `/api/events` queue
5. Phase 5 (AI) will process location + battery data

---

## 🎯 Next Phases

### Phase 5 — AI Layer (Not Yet Implemented)
- **What**: Sai vision engine analyzes camera frames
- **Where**: Brain (iPad runs CoreML models)
- **Worker App Role**: Send camera frames via POST to Brain
- **Future Endpoint**: `POST /api/report` (with image data)

### Phase 6 — Event Polling (Partial)
- Worker polls `GET /api/events` to receive alerts from Brain
- Example: Fire alarm detected → Alert sent to all workers

### Phase 7 — Settings Screen (UI)
- Let user change device zones, sensitivity
- Change Brain IP without rebuild

### Phase 8 — Offline Fallback
- If Brain unreachable, fall back to local logic
- Cache events locally until Brain is back

---

## 🛠️ Testing the App

### 1. Verify Brain is Running
```bash
# On Brain iPad (Pythonista)
# Brain should be running on port 8080

# From your computer:
curl http://[BRAIN_IP]:8080/api/status
# Should return: {"children": [...]}
```

### 2. Run Flutter App
```bash
flutter build apk              # Build for Android
flutter install                # Install on device
# OR
flutter run                    # Debug mode
```

### 3. Check Logs in Logcat/Console
```bash
# Filter for "Heartbeat" or "Connect"
# You should see:
# - "Connecting to Brain..."
# - "Connect response: 200 - ..."
# - "Heartbeat sent: 200" (every 5 seconds)
```

### 4. Verify on Brain
```bash
# In Brain logs, you should see:
# 1. POST /api/connect with device identity
# 2. POST /api/heartbeat every 5 seconds
# 3. Device appears in /api/status response
```

---

## ⚠️ Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| 415 Unsupported Media Type | Bad JSON format | Ensure `jsonEncode()` + proper headers |
| Connection refused | Wrong IP | Edit config.dart with correct Brain IP |
| Heartbeat stops after 30s | Location timeout | Allowed — falls back to "unknown" |
| Brain not in /api/status | Not registered | Check `/api/connect` was called (see logs) |
| Permission denied (location) | No permission | App shows permission dialog at start |
| Background service stops | Android kills it | Foreground service prevents this |

---

## 🔐 Security Notes

1. **No encryption** (Phase 8 will add TLS)
2. **No authentication** (token field is null)
3. **HTTP only** (not HTTPS — safe on local network)
4. **Permissions requested**: location, camera, notification
5. **Location data** sent every 5 seconds (check privacy laws)

---

## 📝 Code Owner

- **Ara** (AraConnectionManager) ← Owns HTTP connection layer
- **Jo** (JoBus) ← Event pub/sub
- **Mini** (MiniMessageRouter) ← Event queuing for this device
- **Sai** (Future) ← Will own AI analysis of heartbeat frames

---

## 🎓 How Another Claude Agent Should Understand This

> "The Flutter Worker App is a background service that wakes up, registers itself with the Brain server, and then every 5 seconds collects device metrics (battery, location) and sends them to Brain via HTTP. It uses proper JSON encoding and Content-Type headers to avoid 415 errors. Once the app is running, check logs to see 'Heartbeat sent: 200' every 5 seconds. If that's working, the AI layer (Phase 5) can start processing."

---

## 📞 Contact / Questions

- **Brain Python code**: Check `/brain` directory in parent repo
- **Test coverage**: `/tests` directory in parent repo
- **Telegram bot**: Runs on Brain, receives alerts only
- **Git repo**: `saipreetham9999/Children`

---

**Status**: Ready for Phase 5 (AI Layer integration)
