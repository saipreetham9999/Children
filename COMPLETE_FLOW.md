# 🔄 ShaRogai Complete Data Flow Guide

## 📊 Full Flow: Motion → Report → Brain

```
┌─────────────────────────────────────────────────────────────┐
│ SHAROGAI APP (Poco M2 Pro - Android)                        │
└─────────────────────────────────────────────────────────────┘

1️⃣  EVERY 1 SECOND
   └─ Background service loop runs
   └─ Log: [BG-Loop] Starting...

2️⃣  EVERY 2 SECONDS (Frame Capture)
   ├─ Log: [BG-Loop] 📸 Capture cycle starting...
   ├─ Capture frame from camera
   │  └─ Log: [BG-Loop] ✅ Frame captured: 15234 bytes
   ├─ Compress frame (JPEG 60% quality)
   │  └─ Log: [BG-Loop] ✅ Compressed: 8234 bytes
   ├─ Compare with previous frame (Motion detection)
   │  ├─ If motion > 15%
   │  │  ├─ Log: [BG-Loop] Motion detected: true
   │  │  ├─ Log: [BG-Loop] 🔥 MOTION FOUND!
   │  │  ├─ Encode to base64
   │  │  ├─ Call: POST /api/report
   │  │  │   └─ Logs: [SendFrame] ✅ SUCCESS
   │  │  └─ Increment motion counter
   │  └─ If no motion
   │     ├─ Log: [BG-Loop] Motion detected: false
   │     └─ Log: [BG-Loop] No motion, frame discarded

3️⃣  EVERY 5 SECONDS (Heartbeat)
   ├─ Log: [BG-Loop] 💓 Heartbeat cycle...
   ├─ Send: POST /api/heartbeat
   │  └─ Log: [SendFrame] ✅ Heartbeat OK
   ├─ Poll: GET /api/events
   │  └─ Log: [BG-Loop] 🔔 Got 2 events (or No events)
   └─ Update notification:
      └─ "🟢 Online • Frames: 5/12 (41.7%)"

4️⃣  BRAIN RECEIVES
   ├─ POST /api/report arrives
   ├─ Flask logs: [BrainRoutes] 📸 Report endpoint hit!
   ├─ Brain publishes: "child.report.received"
   └─ AI processes frame (future)

┌─────────────────────────────────────────────────────────────┐
│ EXPECTED LOG OUTPUT (flutter run)                           │
└─────────────────────────────────────────────────────────────┘

[ShaRogai] Background service initialized
[ShaRogai] Camera initialized
[BG-Loop] 📸 Capture cycle starting...
[BG-Loop] Capturing frame...
[BG-Loop] ✅ Frame captured: 15234 bytes
[BG-Loop] Compressing frame...
[BG-Loop] ✅ Compressed: 8234 bytes
[BG-Loop] Detecting motion...
[BG-Loop] Motion detected: false
[BG-Loop] No motion, frame discarded
[BG-Loop] 📸 Capture cycle starting...  (2s later)
[BG-Loop] ✅ Frame captured: 15245 bytes
[BG-Loop] ✅ Compressed: 8245 bytes
[BG-Loop] 🔥 MOTION FOUND!
[BG-Loop] Sending frame to Brain...
[SendFrame] Starting... frame size: 8245 bytes
[SendFrame] URL: http://192.168.1.100:8080/api/report
[SendFrame] Device: Poco M2 Pro
[SendFrame] Base64 encoded size: 11000 characters
[SendFrame] Sending POST request...
[SendFrame] Response status: 200
[SendFrame] ✅ SUCCESS: Frame sent (8245 bytes)
[BG-Loop] ✅ Frame sent to Brain
[BG-Loop] 💓 Heartbeat cycle...   (5s later)
[WBrain] Heartbeat OK
[BG-Loop] ✅ Heartbeat sent
[BG-Loop] 📬 Polling events...
[WBrain] Got 1 events
[BG-Loop] 🔔 Got 1 events
[BG-Loop] ✅ Notification updated
```

---

## ✅ What You Should See

### **If Everything Works**
```
✅ [BG-Loop] ✅ Frame captured: XXX bytes
✅ [BG-Loop] 🔥 MOTION FOUND!
✅ [SendFrame] ✅ SUCCESS: Frame sent
✅ Notification shows: "Frames: 5/10"
```

### **If Motion Not Detected**
```
❌ [BG-Loop] Motion detected: false
❌ [BG-Loop] No motion, frame discarded
(This is OK - means no motion in frame)
```

### **If Frame Capture Fails**
```
❌ [BG-Loop] ❌ Frame error: Camera not initialized
→ Check camera permissions
```

### **If Frame Not Sent**
```
❌ [SendFrame] ❌ ERROR: Connection refused
→ Check Brain IP
→ Check WiFi
```

---

## 🧪 Quick Test Sequence

### **On Poco with ShaRogai App**
```bash
1. Open app
2. Connect to Brain (192.168.1.100)
3. Register device
4. Sit back and watch flutter run console

Wait 2-3 seconds...
↓
🔥 Wave hand in front of camera
↓
Look for:
[BG-Loop] 🔥 MOTION FOUND!
[SendFrame] ✅ SUCCESS
↓
Check Telegram group for alert
```

### **On Laptop (Verify Endpoint)**
```bash
# While app is running, send test frame
curl -X POST http://192.168.1.100:8080/api/report \
  -H "Content-Type: application/json" \
  -d '{
    "device_name":"Test",
    "type":"frame",
    "data":"base64string"
  }'

# Should get: {"status":"received"}
```

---

## 📊 Motion Detection Stats

**Shown in notification every 5 seconds**:
```
Frames: 5/12 (41.7%)
   ↓
   Frames sent to Brain: 5
   Total frames processed: 12
   Detection rate: 41.7%
```

**Interpretation**:
- `5/12` = Out of 12 frames captured, 5 had motion
- `41.7%` = About 42% of frames showed motion
- If this is 0%: No motion was detected (sensor might be wrong)
- If this is 100%: Everything looks like motion (threshold too low)

---

## 🔧 Troubleshooting with Logs

| Log Message | Meaning | Fix |
|-------------|---------|-----|
| `Frame captured: 0 bytes` | Camera returned empty | Permissions issue |
| `Motion detected: false` | No motion in frame | Normal if camera still |
| `Connection refused` | Brain unreachable | Check IP |
| `TimeoutException` | Brain too slow | Check iPad CPU |
| `Response status: 500` | Brain error | Check /api/report on iPad |

---

## 📋 Data Being Sent

### **Every 2 seconds (if motion)**:
```json
POST /api/report
{
  "device_name": "Poco M2 Pro",
  "type": "frame",
  "frame_type": "jpeg",
  "data": "base64_encoded_image_8KB"
}
```

### **Every 5 seconds**:
```json
POST /api/heartbeat
{
  "device_name": "Poco M2 Pro"
}

GET /api/events?device_name=Poco M2 Pro
← Returns: {"events": [...]}
```

---

## 💾 Data Size Reference

| Item | Size | Impact |
|------|------|--------|
| Raw frame | 15-20 KB | Before compression |
| Compressed frame | 8-10 KB | After JPEG 60% |
| Base64 encoded | 11-14 KB | For transmission |
| Per hour (1 alert/min) | ~0.7 MB | Very small |
| Per hour (continuous) | ~35-40 MB | Needs monitoring |

**Tip**: Motion detection keeps data small by only sending when motion detected!

---

## 🎯 Expected Performance

| Metric | Expected | Notes |
|--------|----------|-------|
| Frame capture | ~200ms | Camera latency |
| Motion detection | ~100ms | Pixel comparison |
| Compression | ~50ms | JPEG encoding |
| Network send | ~500ms | HTTP POST |
| Total per frame | ~1 second | Fits in 2-second cycle |
| Heartbeat | <50ms | Very fast |
| Battery drain | 8-10%/hr | Continuous capture |

---

## 📱 Real-World Example

```
10:00:00 - App starts, registers with Brain
10:00:05 - ✅ Heartbeat sent, events polled
10:00:10 - 🔥 Motion detected! Frame sent
          - [BG-Loop] 🔥 MOTION FOUND!
          - [SendFrame] ✅ SUCCESS
          - Brain receives frame
          - Brain AI processes (future)
          - Alert generated
          - Telegram notified
10:00:12 - [BG-Loop] Motion detected: false
10:00:14 - [BG-Loop] Motion detected: false
10:00:15 - 💓 Heartbeat, poll events
          - ✅ Got 1 alert
          - Poco main screen shows alert
10:00:20 - 🔥 Motion detected! Frame sent
```

---

**Now build and test!** 🚀

With all this logging, you'll see EXACTLY where the flow breaks (if it does).
