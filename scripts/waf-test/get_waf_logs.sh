#!/bin/bash
set -e

TARGET=$1

if [ "$TARGET" != "api" ] && [ "$TARGET" != "amplify" ]; then
  echo "Usage: ./get_waf_logs.sh [api|amplify]"
  exit 1
fi

if [ "$TARGET" = "api" ]; then
  LOG_GROUP="aws-waf-logs-api"
  # API Gateway WAF is regional
  REGION="ap-northeast-1"
else
  LOG_GROUP="aws-waf-logs-amplify"
  # Amplify WAF is always in us-east-1
  REGION="us-east-1"
fi

echo "=================================================="
echo "WAF ブロックログの取得 ($TARGET)"
echo "Log Group : $LOG_GROUP"
echo "Region    : $REGION"
echo "=================================================="

# Calculate timestamp for "10 minutes ago" in milliseconds
if date --version >/dev/null 2>&1; then
  # GNU date (Linux)
  START_TIME=$(date -d "10 minutes ago" +%s000)
else
  # BSD date (Mac)
  START_TIME=$(date -v-10M +%s000 2>/dev/null || echo $(($(date +%s)*1000 - 600000)))
fi

# Fetch logs and parse JSON with Python (to avoid jq dependency)
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --region "$REGION" \
  --start-time "$START_TIME" \
  --filter-pattern '{$.action = "BLOCK"}' \
  --query 'events[*].message' \
  --output text | python3 -c '
import sys, json, datetime
for line in sys.stdin:
    if not line.strip(): continue
    try:
        data = json.loads(line)
        ts = int(data.get("timestamp", 0)) / 1000
        dt = datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")
        ip = data.get("httpRequest", {}).get("clientIp", "unknown")
        uri = data.get("httpRequest", {}).get("uri", "unknown")
        rule = data.get("terminatingRuleId", "unknown")
        print(f"[{dt}] BLOCKED IP: {ip} | URI: {uri} | Rule: {rule}")
    except Exception as e:
        pass
'

echo "=================================================="
echo "取得完了。直近10分間のブロックログがない場合は何も表示されません。"
