# Backend (FastAPI)

## 概要
Python 3.13 と FastAPI を用いて構築されたバックエンド API サーバーです。
フロントエンドから送信された Cognito の JWT トークンを検証し、認証済みユーザーのデータを操作する API を提供します。
AWS Lambda Web Adapter を利用しており、ローカルでの動作と同じコードのまま AWS Lambda 上で稼働します。

パッケージ管理には `uv` を使用し、依存関係は `pyproject.toml` および `uv.lock` で管理されています。

## ローカル開発での実行手順
```bash
uv run uvicorn app.main:app --reload
```
※ 起動後、`http://localhost:8000/api/health` 等で確認できます。

## AWS へのデプロイ手順

本プロジェクトでは、AWS Lambda に Docker コンテナイメージとしてデプロイします。
デプロイを簡略化するため、`deploy.sh` スクリプトを用意しています。

### 初回デプロイ（またはインフラ構築時）の流れ
※インフラの作成手順は `terraform/README.md` を参照してください。
1. `terraform/ecr` で ECR リポジトリを作成
2. `scripts/deploy.sh` を実行してイメージを ECR に Push
3. `terraform/app` で Lambda 関数を作成

### 2回目以降のデプロイ（コード更新時）
アプリケーションの Python コードを修正した場合は、Terraform を実行する必要はありません。以下のスクリプトを叩くだけで、ビルド・Push・Lambdaの更新までが自動で行われます。

```bash
scripts/deploy.sh
```

### デプロイ後の動作確認（正常性の判断基準）
デプロイが成功したかどうかは、API Gateway の Health Check エンドポイントを叩くことで確認できます。

1. API Gateway のエンドポイント URL を取得する
   ```bash
   cd terraform/app
   terraform output api_endpoint
   ```
2. 取得した URL の末尾に `/api/health` を付けて `curl` コマンドを実行する
   ```bash
   curl <取得したURL>/api/health
   ```
3. **【成功の基準】**
   以下のような JSON が返ってくれば、コンテナが Lambda 上で正常に起動し、API Gateway と通信できている証拠（完全成功）です。
   ```json
   {"status":"ok","message":"Backend is running"}
   ```
   ※ もし `{"message":"Internal Server Error"}` などが返ってくる場合は、コンテナの起動失敗や権限エラーが疑われます。AWS Lambda の CloudWatch Logs を確認してください。
