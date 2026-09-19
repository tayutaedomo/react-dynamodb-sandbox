#!/bin/bash
set -e

# API_URL が引数または環境変数で渡されていない場合は Terraform output から取得
if [ -z "$1" ] && [ -z "$API_URL" ]; then
  echo "Fetching API_URL from Terraform..."
  cd ../../terraform/app
  API_ENDPOINT=$(terraform output -raw api_endpoint)
  cd ../../scripts/waf-test
  API_URL="${API_ENDPOINT}/api/health"
else
  API_URL=${1:-$API_URL}
fi

if [ -z "$API_URL" ] || [[ "$API_URL" == *"Error"* ]]; then
  echo "Error: API_URL could not be determined."
  echo "Usage: ./test_api_waf.sh [API_URL]"
  exit 1
fi

echo "=================================================="
echo "🚀 API Gateway WAF レート制限テストを開始します"
echo "URL: $API_URL"
echo "制限: 100回 / 5分間"
echo "=================================================="

for i in {1..120}
do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL")
  echo "リクエスト $i: HTTP Status $STATUS"
  
  if [ "$STATUS" = "403" ]; then
    echo "🚨 WAF によってアクセスがブロックされました (403 Forbidden)"
    echo "テストを終了します。CloudWatch Logs (aws-waf-logs-api) を確認してください。"
    exit 0
  fi
  
  sleep 0.1
done

echo "⚠️ 120回リクエストを送信しましたが、ブロックされませんでした。"
echo "WAFの設定、またはネットワークの経路を確認してください。"
