# サーバーレス認証・業務API プロトタイプ

このプロジェクトは、React、AWS Cognito、FastAPI、DynamoDB を組み合わせたサーバーレス・アーキテクチャのプロトタイプです。

## プロジェクト概要
ユーザー管理・アカウント運用は「AWS マネジメントコンソール」を活用して最小限に抑え、認証されたユーザーが業務データ（CRUD）を安全に操作できる縦串の疎通を最優先としています。

### 採用技術スタック
- **Frontend**: React (TypeScript, Vite), AWS Amplify SDK
- **Backend**: Python 3.12+, FastAPI
- **Backend Runtime**: AWS Lambda (AWS Lambda Web Adapter) + Amazon API Gateway
- **Database**: Amazon DynamoDB
- **Auth**: Amazon Cognito User Pool
- **IaC**: Terraform

## ディレクトリ構成
- `docs/`: 追加の説明事項、ADR (Architecture Decision Records) などのドキュメント
- `frontend/`: React (Vite) を用いたフロントエンド・アプリケーション
- `backend/`: FastAPI を用いたバックエンド・アプリケーション
- `terraform/`: AWSリソースをプロビジョニングするためのTerraform設定
