# WAF レート制限テストスクリプト

このディレクトリには、AWS WAF の「レートベースルール（Rate-based rules）」の挙動を検証するためのスクリプトが含まれています。

## 概要

本プロジェクトでは、脆弱性スキャンや DDoS 攻撃対策として、同一 IP アドレスから直近 5分間に **100回以上** のリクエストがあった場合、自動的にアクセスをブロック（`HTTP 403 Forbidden`）する WAF レート制限を導入しています。

WAF は以下の2箇所にアタッチされており、それぞれの防御層を個別にテストできます。

1. **Amplify Hosting (フロントエンド)**: `test_amplify_waf.sh`
2. **API Gateway (バックエンド)**: `test_api_waf.sh`

## 前提条件

- Terraform によるインフラ構築 (`terraform apply`) が完了していること
- `aws-cli` および `terraform` コマンドが実行可能であること (Terraform の出力から URL を自動取得するため)
- 実行環境 (ローカル PC) からインターネット経由で対象の URL にアクセス可能であること

## 使用方法

### 1. API Gateway 側の WAF テスト
バックエンド API に対するレート制限をテストします。

```bash
cd scripts/waf-test
./test_api_waf.sh
```
※ 引数で任意の URL を指定することも可能です: `./test_api_waf.sh https://example.com/api/health`

### 2. Amplify Hosting 側の WAF テスト
フロントエンド（静的サイト配信）に対するレート制限をテストします。

```bash
cd scripts/waf-test
./test_amplify_waf.sh
```

## 挙動の確認

1. スクリプトを実行すると、1秒間に約10回のペースで `curl` による連続リクエストが送信されます。
2. 最初は `HTTP Status 200` が返ってきます。
3. リクエスト回数が 100回 を超えたあたりで、AWS WAF が異常を検知し、ステータスが **`HTTP Status 403`** に切り替わります。
4. スクリプトは 403 を検知すると自動的にテストを終了します。

## テスト後のログ確認

WAF によってブロックされたリクエストの詳細（アクセス元の IP、ユーザーエージェント、マッチしたルールなど）は、AWS マネジメントコンソールの **CloudWatch Logs** に記録されます。

- **API Gateway のブロックログ**: `aws-waf-logs-api` ロググループ
- **Amplify Hosting のブロックログ**: `aws-waf-logs-amplify` ロググループ (※ 米国東部 `us-east-1` リージョン)

## ブロックの解除について

WAF のレート制限は「直近 5分間の累計リクエスト数」で評価されます。
スクリプト実行により 403 でブロックされた場合でも、**アクセスを停止して 5分程度 放置すれば、自動的に制限が解除され、再び 200 OK でアクセスできるようになります。** 手動での解除作業は不要です。

### 3. WAF ブロックログの確認 (CLI)
AWS コンソールを開かずに、コマンドラインから直近10分間の WAF ブロックログ（`BLOCK` アクション）を確認するスクリプトです。

**API Gateway のブロックログを確認:**
```bash
./get_waf_logs.sh api
```

**Amplify Hosting のブロックログを確認:**
```bash
./get_waf_logs.sh amplify
```
出力例:
`[2024-03-20 12:34:56] BLOCKED IP: 192.0.2.1 | URI: /api/health | Rule: rate-limit`
