#!/bin/bash
set -e

# CLOUDFRONT_URL が引数または環境変数で渡されていない場合は Terraform output から取得
if [ -z "$1" ] && [ -z "$CLOUDFRONT_URL" ]; then
  echo "Fetching CLOUDFRONT_URL from Terraform..."
  cd ../../terraform/app
  CLOUDFRONT_URL=$(terraform output -raw cloudfront_domain)
  cd ../../scripts/waf-test
else
  CLOUDFRONT_URL=${1:-$CLOUDFRONT_URL}
fi

if [ -z "$CLOUDFRONT_URL" ] || [[ "$CLOUDFRONT_URL" == *"Error"* ]]; then
  echo "Error: CLOUDFRONT_URL could not be determined."
  echo "Usage: ./test_cloudfront_waf.sh [CLOUDFRONT_URL]"
  exit 1
fi

echo "=================================================="
echo "🚀 CloudFront WAF レート制限テストを開始します"
echo "URL: $CLOUDFRONT_URL"
echo "制限: 100回 / 5分間"
echo "=================================================="

for i in {1..120}
do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$CLOUDFRONT_URL")
  echo "リクエスト $i: HTTP Status $STATUS"
  
  if [ "$STATUS" = "403" ]; then
    echo "🚨 WAF によってアクセスがブロックされました (403 Forbidden)"
    echo "テストを終了します。CloudWatch Logs (aws-waf-logs-cloudfront) を確認してください。"
    exit 0
  fi
  
  sleep 0.1
done

echo "⚠️ 120回リクエストを送信しましたが、ブロックされませんでした。"
echo "WAFの設定、またはネットワークの経路を確認してください。"
