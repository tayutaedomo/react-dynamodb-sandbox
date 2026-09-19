#!/bin/bash
set -e

# AMPLIFY_URL が引数または環境変数で渡されていない場合は Terraform output から取得
if [ -z "$1" ] && [ -z "$AMPLIFY_URL" ]; then
  echo "Fetching AMPLIFY_URL from Terraform..."
  cd ../../terraform/app
  AMPLIFY_URL=$(terraform output -raw amplify_app_url)
  cd ../../scripts/waf-test
else
  AMPLIFY_URL=${1:-$AMPLIFY_URL}
fi

if [ -z "$AMPLIFY_URL" ] || [[ "$AMPLIFY_URL" == *"Error"* ]]; then
  echo "Error: AMPLIFY_URL could not be determined."
  echo "Usage: ./test_amplify_waf.sh [AMPLIFY_URL]"
  exit 1
fi

echo "=================================================="
echo "🚀 Amplify Hosting WAF レート制限テストを開始します"
echo "URL: $AMPLIFY_URL"
echo "制限: 100回 / 5分間"
echo "=================================================="

for i in {1..120}
do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$AMPLIFY_URL")
  echo "リクエスト $i: HTTP Status $STATUS"
  
  if [ "$STATUS" = "403" ]; then
    echo "🚨 WAF によってアクセスがブロックされました (403 Forbidden)"
    echo "テストを終了します。CloudWatch Logs (aws-waf-logs-amplify) を確認してください。"
    exit 0
  fi
  
  sleep 0.1
done

echo "⚠️ 120回リクエストを送信しましたが、ブロックされませんでした。"
echo "WAFの設定、またはネットワークの経路を確認してください。"
