# 🚀 Worker App — Motion Detection Transmitter

**Worker** is a Flutter app for Poco M2 Pro that connects to the Brain (iPad) server and continuously monitors for motion, sending frames to the Brain for AI processing.

## 📋 Architecture Overview

```
Worker (Poco M2 Pro)
├── Phase MVP: Connect + Register + Status
├── Phase 2.1: Manual photo capture button
├── Phase 2.2: On-device motion detection
└── Phase 2.3: Continuous background monitoring
```

## 🎯 Features

### Phase MVP — Foundation
- ✅ **Connect Screen** — Enter Brain IP, verify connection
- ✅ **Register Screen** — Auto-detect device info, register with Brain
- ✅ **Main Screen** — Status indicator, alert log, sync time

### Phase 2.1 — Manual Photo
- ✅ **Take Photo Button** — Capture frame, send to Brain
- ✅ **Frame Compression** — Reduce size for transmission

### Phase 2.2 — Smart Detection
- ✅ **On-Device Motion Detection** — Compare frames, only send candidates
- ✅ **Configurable Threshold** — Motion sensitivity setting

### Phase 2.3 — Always On
- ✅ **Background Service** — Continuous monitoring
- ✅ **Foreground Notification** — App visible, not killed by OS
- ✅ **Auto-Restart** — Heartbeat every 5s, events every 2s

## 📁 File Structure

```
lib/
├── main.dart                          ← Entry point, routing
├── config.dart                        ← Constants & settings
│
├── models/
│   ├── device_model.dart              ← Device identity
│   └── alert_model.dart               ← Alert data structure
│
├── services/
│   ├── brain_service.dart             ← HTTP calls to Brain
│   ├── frame_service.dart             ← Camera capture
│   ├── motion_detector.dart           ← On-device motion detection
│   └── background_service.dart        ← Phase 2.3: Background task
│
├── screens/
│   ├── connect_screen.dart            ← Phase MVP: IP entry
│   ├── register_screen.dart           ← Phase MVP: Registration
│   └── main_screen.dart               ← Phase MVP/2.1/2.2/2.3: Status + alerts
│
└── widgets/
    ├── status_indicator.dart          ← Green/red dot
    └── alert_card.dart                ← Alert display
```

## 🔄 How It Works

### Phase MVP Flow

```
1. User opens app
   ↓
2. Enter Brain IP (e.g., 192.168.1.100)
   ↓
3. App connects to http://192.168.1.100:8080/api/status
   ↓
4. If online → navigate to Register
   ↓
5. App detects device name, type, OS automatically
   ↓
6. User clicks "Register with Brain"
   ↓
7. POST /api/connect with device info
   ↓
8. Navigate to Main screen
```

### Phase 2.1 Feature

```
User clicks "Take Photo"
   ↓
App captures camera frame
   ↓
Compress to 60% quality
   ↓
POST /api/report with frame data
   ↓
Brain receives → AI processes → sends alert back
   ↓
Show result in alert log
```

### Phase 2.2 Feature (Smart Mode)

```
Background service starts every 2 seconds
   ↓
Capture frame from camera
   ↓
WMotionDetector compares with previous frame
   ↓
If motion > threshold (15% pixel change)
   ├── Compress frame
   └── POST /api/report to Brain
   ↓
If no motion
   └── Discard silently
   ↓
Every 5 seconds: Send heartbeat + poll events
   ↓
Update status in notification
```

### Phase 2.3 Feature (Continuous)

```
App starts
   ↓
Initialize background service (Android foreground mode)
   ↓
Loop every 1 second (infinite)
   ├── Capture frame every 2 seconds
   ├── Motion detect every 2 seconds
   ├── Send frame if motion every 2 seconds
   ├── Heartbeat every 5 seconds
   ├── Poll /api/events every 5 seconds
   └── Update foreground notification status
   ↓
Runs even if app minimized (foreground service)
   ↓
Battery: ~8-10% per hour
```

## 🎬 Motion Detection Algorithm

```
Frame 1 → stored as baseline (no motion detection yet)
   ↓
Frame 2 → compared with Frame 1
   ├── For each pixel in frame:
   │   ├── Get RGB values from current
   │   ├── Get RGB values from previous
   │   ├── If any channel differs by > 30 → count as changed pixel
   │   └── Calculate total changed pixels / total pixels
   │
   ├── If motion% > threshold (15%)
   │   └── Mark as "motion detected"
   │   └── Send to Brain
   │
   └── If motion% <= threshold
       └── Discard silently
   ↓
Frame 3 → compared with Frame 2 (now the baseline)
```

**Tuning Motion Detection**:
- Lower threshold = more sensitive (send more frames)
- Higher threshold = less sensitive (send fewer frames)
- Default: 15% → balanced for general motion

## 📱 User Journey

### Day 1: First Setup

```
1. Open Worker app
2. Enter Brain IP: "192.168.1.100"
3. Click "Check & Connect"
   → Brain Online ✓
4. App auto-fills device name: "Poco M2 Pro"
5. Click "Register with Brain"
   → Connected!
6. Main screen shows:
   - Status: 🟢 Online
   - Last Sync: 10:30:45
   - Alerts: 0
```

### Day 2: Motion Detection

```
1. App running in background
2. Motion detected at 10:31:20
   → Frame sent to Brain
   → AI says: "Person detected"
3. Alert appears: "Person detected" (high severity)
4. User opens app
   → See alert in log
5. Click "Take Photo" for manual capture
   → Another frame sent
```

### Day 3: Monitoring

```
1. App still running in background
2. Notification shows:
   "Worker - Online • Frames sent: 23"
3. No motion for 1 hour → no frames sent
4. User checks status
   → Last Sync: 2 minutes ago
   → 23 frames sent today
5. Battery: 60% (started at 100% this morning)
```

## 🔧 Configuration

Edit `lib/config.dart` to tune behavior:

```dart
// How sensitive is motion detection? (0.0 = very sensitive, 1.0 = not sensitive)
static const double motionThresholdDefault = 0.15;

// How often capture frames? (ms)
static const int captureIntervalMs = 2000; // Every 2 seconds

// Compression quality (higher = better quality, more data)
static const int frameCompressionQuality = 60;

// Heartbeat & polling (adjust based on battery life)
static const int heartbeatIntervalSeconds = 5;
static const int eventPollIntervalSeconds = 2;
```

## 🔌 Brain API Integration

Worker uses these Brain endpoints:

| Endpoint | Method | Use | Phase |
|----------|--------|-----|-------|
| `/api/connect` | POST | Register device | MVP |
| `/api/status` | GET | Check Brain online | MVP |
| `/api/heartbeat` | POST | Keep alive | MVP |
| `/api/events` | GET | Poll for alerts | MVP |
| `/api/report` | POST | Send frames | 2.1+ |
| `/api/disconnect` | POST | Cleanup | Future |

## ⚙️ Background Service Details

### Android (Primary)

```dart
FlutterBackgroundService
├── Foreground Service (notification always visible)
├── Auto-start on boot
├── Periodic task (every 1 second)
└── High priority to avoid killing by OS
```

**Battery Impact**:
- Foreground mode: OS allocates foreground power budget
- ~8-10% per hour (high, but acceptable for security camera)

### iOS

```dart
FlutterBackgroundService
├── Background modes: background fetch
├── Limited execution time
└── May be suspended by OS
```

**Note**: iOS limits background execution. Consider:
- Increasing capture interval (e.g., 5s)
- Reducing motion detection frequency
- Using other iOS background modes (location tracking, VoIP)

## 🚨 Error Handling

| Error | Behavior |
|-------|----------|
| Brain unreachable | Status = 🔴 Offline, local alerts only |
| Camera error | Take photo disabled, background paused |
| Low motion frames | Continue polling, no frames sent |
| Permission denied | Request again, function disabled |
| Background killed | Auto-restart on next heartbeat |

## 📊 Performance

Expected performance on Poco M2 Pro (Snapdragon 720G):

| Operation | Time | Notes |
|-----------|------|-------|
| Frame capture | ~200ms | Camera latency |
| Motion detection | ~300ms | Image comparison |
| Frame compression | ~100ms | JPEG encoding |
| HTTP send | ~500ms | Network latency |
| Total per frame | ~1.1s | Fast enough for 2s intervals |

**CPU Usage**: ~15-20% during capture cycles, ~2-3% idle
**RAM Usage**: ~60-80MB during operation
**Battery**: 8-10% per hour (motion detection + transmission)

## 🧪 Testing

### Manual Test

```bash
# 1. Run on device
flutter run

# 2. Enter Brain IP
# 3. Register device
# 4. Watch status screen
# 5. Watch Brain logs for incoming events
# 6. Send heartbeat: grep "Heartbeat" logs
# 7. Capture frame: click button
# 8. Check Brain received frame
```

### Automated Test

```bash
# Run integration tests (future)
flutter test
```

## 📈 Future Improvements

- [ ] Settings screen (motion threshold, interval tuning)
- [ ] Video recording (not just frames)
- [ ] Local frame storage (backup)
- [ ] Battery optimization (adaptive intervals)
- [ ] Tensorflow Lite on-device ML (faster motion detection)
- [ ] WiFi failover (switch to hotspot)
- [ ] UI notification for each alert
- [ ] Offline mode (queue frames, sync when online)

## 🐛 Known Issues

1. **iOS Background Limitation** — May be suspended by OS after 10-15 minutes
   - Workaround: Use location tracking + VoIP background modes

2. **Camera Warm-Up** — First frame slow on cold start
   - Impact: ~500ms delay, acceptable

3. **High Battery Drain** — Foreground service + continuous capture
   - Impact: 8-10% per hour (design trade-off for reliability)
   - Mitigation: User can disable background mode from notification

4. **No Persistent Storage** — Frames sent but not stored locally
   - By design: Heavy device storage required
   - Brain keeps history instead

## 📞 Support

Issues or questions? Check:
1. Brain is running: `curl http://[ip]:8080/api/status`
2. Worker connected: Check Brain `/api/status` → see worker device
3. Events flowing: Worker `/api/events` → should see alerts
4. Logs: `adb logcat -s flutter` (Android)

---

**Status**: Ready for testing ✅
**Last Updated**: 2026-02-15
**Version**: 1.0.0 (MVP + Phases 2.1, 2.2, 2.3)
