#!/usr/bin/env python3
"""
ShaRogai Debug Test - Test /api/report endpoint
Run this to verify Brain is receiving frames from Poco
"""

import requests
import base64
import json
import sys
import time
from PIL import Image
import io

# Configuration
BRAIN_IP = input("Enter Brain IP (e.g., 192.168.1.100): ").strip() or "192.168.1.100"
BRAIN_PORT = 8080
BRAIN_URL = f"http://{BRAIN_IP}:{BRAIN_PORT}"
DEVICE_NAME = "DebugTester"

print(f"\n🧠 ShaRogai Debug Test")
print(f"Brain URL: {BRAIN_URL}")
print(f"Device Name: {DEVICE_NAME}")
print("-" * 50)


def test_status():
    """Test 1: Check if Brain is online"""
    print("\n1️⃣  Testing /api/status...")
    try:
        response = requests.get(f"{BRAIN_URL}/api/status", timeout=5)
        print(f"   Status: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"   ✅ Brain is ONLINE")
            print(f"   Connected children: {len(data['children'])}")
            for child in data['children']:
                print(f"      - {child['device_name']} ({child['device_type']})")
            return True
        else:
            print(f"   ❌ Status code: {response.status_code}")
            return False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False


def test_connect():
    """Test 2: Connect as debug device"""
    print("\n2️⃣  Testing /api/connect...")
    try:
        payload = {
            "device_name": DEVICE_NAME,
            "device_type": "debug",
            "capabilities": ["camera"],
        }
        response = requests.post(
            f"{BRAIN_URL}/api/connect",
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=5
        )
        print(f"   Status: {response.status_code}")
        print(f"   Response: {response.json()}")

        if response.status_code == 200:
            print(f"   ✅ Connected as {DEVICE_NAME}")
            return True
        else:
            print(f"   ❌ Connect failed")
            return False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False


def create_test_frame():
    """Create a simple test image (100x100 red square)"""
    img = Image.new('RGB', (100, 100), color='red')
    img_bytes = io.BytesIO()
    img.save(img_bytes, format='JPEG')
    return img_bytes.getvalue()


def test_report_simple():
    """Test 3: Send simple text report"""
    print("\n3️⃣  Testing /api/report (simple)...")
    try:
        payload = {
            "device_name": DEVICE_NAME,
            "type": "test",
            "data": "Hello Brain!"
        }
        response = requests.post(
            f"{BRAIN_URL}/api/report",
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=5
        )
        print(f"   Status: {response.status_code}")
        print(f"   Response: {response.json()}")

        if response.status_code == 200:
            print(f"   ✅ Simple report sent")
            return True
        else:
            print(f"   ❌ Report failed")
            return False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False


def test_report_frame():
    """Test 4: Send frame report"""
    print("\n4️⃣  Testing /api/report (frame)...")
    try:
        # Create test frame
        print("   Creating test frame...")
        frame_bytes = create_test_frame()
        frame_base64 = base64.b64encode(frame_bytes).decode('utf-8')

        payload = {
            "device_name": DEVICE_NAME,
            "type": "frame",
            "frame_type": "jpeg",
            "data": frame_base64
        }

        print(f"   Frame size: {len(frame_bytes)} bytes")
        print(f"   Base64 size: {len(frame_base64)} characters")
        print(f"   Sending frame...")

        response = requests.post(
            f"{BRAIN_URL}/api/report",
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=10
        )

        print(f"   Status: {response.statusCode}")
        print(f"   Response: {response.json()}")

        if response.status_code == 200:
            print(f"   ✅ Frame sent successfully!")
            return True
        else:
            print(f"   ❌ Frame send failed")
            return False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        print(f"   Error type: {type(e).__name__}")
        return False


def test_heartbeat():
    """Test 5: Send heartbeat"""
    print("\n5️⃣  Testing /api/heartbeat...")
    try:
        payload = {"device_name": DEVICE_NAME}
        response = requests.post(
            f"{BRAIN_URL}/api/heartbeat",
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=5
        )
        print(f"   Status: {response.status_code}")

        if response.status_code == 200:
            print(f"   ✅ Heartbeat sent")
            return True
        else:
            print(f"   ❌ Heartbeat failed")
            return False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False


def test_events():
    """Test 6: Poll for events"""
    print("\n6️⃣  Testing /api/events...")
    try:
        response = requests.get(
            f"{BRAIN_URL}/api/events?device_name={DEVICE_NAME}",
            timeout=5
        )
        print(f"   Status: {response.status_code}")
        data = response.json()
        print(f"   Events: {len(data.get('events', []))}")

        if response.status_code == 200:
            print(f"   ✅ Events polled")
            return True
        else:
            print(f"   ❌ Events failed")
            return False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False


def main():
    """Run all tests"""
    print("\n" + "=" * 50)
    print("🧠 SHAROGAI DEBUG TEST SUITE")
    print("=" * 50)

    results = []

    # Test sequence
    results.append(("Status", test_status()))
    if not results[-1][1]:
        print("\n❌ Brain is not reachable. Stopping.")
        return

    time.sleep(1)
    results.append(("Connect", test_connect()))

    time.sleep(1)
    results.append(("Simple Report", test_report_simple()))

    time.sleep(1)
    results.append(("Frame Report", test_report_frame()))

    time.sleep(1)
    results.append(("Heartbeat", test_heartbeat()))

    time.sleep(1)
    results.append(("Events", test_events()))

    # Summary
    print("\n" + "=" * 50)
    print("📊 TEST SUMMARY")
    print("=" * 50)

    for name, passed in results:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"{name:20} {status}")

    passed_count = sum(1 for _, p in results if p)
    total_count = len(results)
    print(f"\nTotal: {passed_count}/{total_count} passed")

    if passed_count == total_count:
        print("\n🎉 ALL TESTS PASSED! ShaRogai is working!")
    else:
        print("\n⚠️  Some tests failed. Check logs on Brain (iPad).")

    print("=" * 50)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⏹️  Test cancelled")
    except Exception as e:
        print(f"\n\n❌ Fatal error: {e}")
