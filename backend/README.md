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
