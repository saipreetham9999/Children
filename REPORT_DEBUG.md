# 🔍 ShaRogai /api/report Debug Guide

**Problem**: Photos captured but `/api/report` not being hit

---

## ✅ Step 1: Test from Laptop (Verify Endpoint Works)

```bash
# On your Windows/Mac laptop (NOT on Poco or iPad)

# Test 1: Simple curl
curl -X POST http://192.168.1.100:8080/api/report \
  -H "Content-Type: application/json" \
  -d '{"device_name":"Test","type":"test","data":"hello"}'

# Expected response:
# {"status":"received"}  ← means endpoint works!
```

---

## ✅ Step 2: Check Flutter Logs (Find the Error)

```bash
# Run app on Poco with logs visible
flutter run

# When you take photo, look for:
# [SendFrame] Starting... frame size: XXXX bytes
# [SendFrame] URL: http://192.168.1.100:8080/api/report
# [SendFrame] Device: Poco M2 Pro
# [SendFrame] Sending POST request...

# If you see ERROR messages:
# - Copy them
# - They tell you exactly what's wrong
```

---

## 🔧 Common Issues & Fixes

### **Issue 1: "Connection refused"**
```
[SendFrame] ERROR: Connection refused

Fix:
1. Check iPhone/iPad IP is correct (192.168.1.100)
2. Verify Brain is running on iPad
3. Check both on same WiFi
```

### **Issue 2: "TimeoutException"**
```
[SendFrame] ERROR: TimeoutException: timed out...

Fix:
1. Increase timeout in brain_service.dart (done: 15 seconds)
2. Check WiFi signal strength
3. Brain might be too slow - check iPad
```

### **Issue 3: "Base64 encoding failed"**
```
[SendFrame] ERROR: Frame bytes empty!

Fix:
1. Camera might not be initialized
2. Photo button not actually captured
3. Check camera permissions
```

### **Issue 4: "Response status: 500"**
```
[SendFrame] Response status: 500
[SendFrame] Response body: {'error': '...'}

Fix:
1. Copy the exact error message
2. Your Brain side has a bug
3. Check /api/report endpoint on iPad
```

---

## 🔄 Quick Debug Sequence

### **On Laptop:**
```bash
# 1. Test endpoint works
curl http://192.168.1.100:8080/api/status

# If yes, continue...
# 2. Test report endpoint
curl -X POST http://192.168.1.100:8080/api/report \
  -H "Content-Type: application/json" \
  -d '{"device_name":"Test","type":"frame","data":"base64string"}'
```

### **On iPad (Brain):**
```bash
# In Pythonista console, check logs:
# Look for: [BrainRoutes] Report endpoint hit!
# This confirms Flask received the request
```

### **On Poco (ShaRogai):**
```bash
# 1. Open app
# 2. Connect to Brain IP
# 3. Take photo (button)
# 4. Look at flutter run output for [SendFrame] logs
# 5. Copy any ERROR messages
```

---

## 📋 What to Check

| Check | Command | Expected |
|-------|---------|----------|
| Brain online | `curl http://IP:8080/api/status` | `200 OK` |
| Endpoint works | `curl -X POST http://IP:8080/api/report ...` | `200 OK` |
| WiFi same | iPad & Poco same SSID | Yes ✅ |
| Flask started | Pythonista logs | "BRAIN ONLINE" |

---

## 🎯 If Still Not Working

1. **Take a photo on Poco**
2. **Watch flutter run output** (look for [SendFrame] logs)
3. **Copy the ERROR message**
4. **Send me the error**

With the detailed logging I added, the error will tell exactly what's wrong!

---

## 📁 Files Updated

- `lib/services/brain_service.dart` — Enhanced logging ✅
- `IMPROVED_ROUTES.py` — Better Flask endpoint (copy to iPad)
- `DEBUG_TEST.py` — Full test suite
- `TEST_REPORT.sh` — Quick curl test

---

**Next**: Build again with `flutter build apk --release` and test!
