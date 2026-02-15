#!/bin/bash

# Quick test for /api/report endpoint
# Usage: ./TEST_REPORT.sh 192.168.1.100

BRAIN_IP="${1:-192.168.1.100}"
BRAIN_URL="http://$BRAIN_IP:8080"

echo "🧠 Testing ShaRogai /api/report endpoint"
echo "Brain URL: $BRAIN_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test 1: Check if Brain is online
echo -e "\n1️⃣  Checking if Brain is online..."
curl -s "$BRAIN_URL/api/status" | python3 -m json.tool
if [ $? -eq 0 ]; then
    echo "✅ Brain is reachable"
else
    echo "❌ Brain is not reachable at $BRAIN_URL"
    exit 1
fi

# Test 2: Send simple report
echo -e "\n2️⃣  Sending simple report to /api/report..."
curl -X POST "$BRAIN_URL/api/report" \
  -H "Content-Type: application/json" \
  -d '{
    "device_name": "Poco-Debug",
    "type": "test",
    "data": "Hello from test"
  }' \
  -v

echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "If you see 200 status code above, /api/report is working! ✅"
echo "If not, check Brain logs on iPad"
