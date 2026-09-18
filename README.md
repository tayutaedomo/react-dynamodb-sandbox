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

## 検証・実装したこと

1. **インフラの Terraform コード化とディレクトリ分割**
   - ライフサイクルの異なるリソース（ECRなどの共通基盤レイヤーと、API Gateway / Lambda などのアプリケーションレイヤー）を別ディレクトリに分割して管理する手法を検証。
2. **FastAPI のサーバーレス稼働と Cognito 連携**
   - `AWS Lambda Web Adapter` を用いて、FastAPI アプリケーションを Docker イメージとして Lambda 上で稼働させることに成功。
   - Cognito が発行する JWT（RS256）を FastAPI 側で検証し、リクエスト元のユーザー (sub) を特定するセキュアな認可フローを実装。
3. **PynamoDB を用いた DynamoDB 操作**
   - Python 向けの NoSQL ORM である `PynamoDB` を導入し、Cognito の `sub` を主キー (Partition Key) としたユーザープロフィールの CRUD 処理を構築。
4. **Cognito トリガーの仕様発見と遅延初期化 (Lazy Initialization)**
   - Cognito の PostConfirmation トリガーは、「管理者向け API (`AdminCreateUser` 等) を用いた場合は発火しない」という AWS の仕様（落とし穴）を実際のデプロイを通じて発見。
   - 代替案として、バックエンド API 初回呼び出し時に DynamoDB に初期レコードを作成する「遅延初期化パターン」を採用し、ADR (アーキテクチャ決定記録) として文書化。
5. **堅牢なテスト・ピラミッドの構築**
   - **Backend**: `pytest` を用い、FastAPI の `Depends` (依存性注入) をオーバーライドすることで Cognito 認証をバイパスするテスト手法を確立。
   - **Frontend**: `vitest` を用いた UI の単体テスト。
   - **E2E**: `Playwright` を導入し、実際の AWS 環境（Cognito, API Gateway, DynamoDB）を貫通する結合テストを構築。Lambda のコールドスタートも考慮したタイムアウト設計を検証。
6. **AI エージェント (Antigravity) との協調ルールの整備**
   - `AGENTS.md` を作成し、AI に対する厳格なルール（勝手な git commit の禁止、テスト・Lint の義務化、ADR 草案の自発的作成）を定義。
   - Git フックを用いたコミットの物理的ブロック機構も備え、人間と AI が安全にペアプログラミングできる土台を構築。
