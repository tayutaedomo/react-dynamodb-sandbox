# デプロイメントガイド (Deployment Guide)

このドキュメントは、本システム全体（インフラ、バックエンド、フロントエンド）のデプロイ手順と、コンポーネント間の依存関係についてまとめたものです。

---

## 1. 全体アーキテクチャと依存関係

本システムのデプロイは、以下の4つの要素で構成されています。
これらは順番通りに実行しないと、後続のデプロイが失敗する（または古いコードが参照される）可能性があります。

1. **ECR (Elastic Container Registry)**: バックエンドのコンテナイメージの保管庫。最初に存在している必要があります。
2. **Backend**: FastAPIのアプリケーション。Dockerイメージとしてビルドされ、ECRにPushされます。
3. **App Infrastructure (Terraform)**: Lambda、API Gateway、Cognito、DynamoDB、Amplifyの「枠」など。LambdaはECRの最新イメージを参照します。
4. **Frontend**: Reactアプリケーション。Terraformで作られたAmplifyの枠に対して、ソースコードを流し込みます。

---

## 2. 初回構築手順 (ゼロからの立ち上げ)

新しい環境を作る場合や、完全にゼロからデプロイする場合は、**必ず以下の1〜4の順番**で実行してください。

### 前提条件 (Prerequisites)
実行前に以下の準備が整っていることを確認してください。
1. **AWS認証**: `aws sso login --profile <プロファイル名>` などでログイン済であること。
2. **AWSプロファイル設定**: `direnv` などを利用して、`AWS_PROFILE` 環境変数がターミナルにセットされていること。
3. **Docker**: バックエンドのビルドに必要な Docker デーモンが起動していること。
4. **Node.js**: フロントエンドのビルドに必要な Node.js / npm がインストールされていること。

### Step 1: 共通インフラ (ECR) のプロビジョニング
バックエンドのイメージのアップロード先を作成します。
```bash
cd terraform/ecr
terraform init
terraform apply
```

### Step 2: バックエンドのビルドとPush
FastAPIアプリケーションをDockerコンテナとしてビルドし、Step 1で作成したECRにPushします。
```bash
cd backend
# ログインとPushを行うスクリプトを実行 (環境に合わせて変更)
./scripts/build_and_push.sh
```

### Step 3: アプリケーションインフラのプロビジョニング
API Gateway, Cognito, DynamoDB, Lambda, Amplify App を作成します。
*(※ LambdaはこのタイミングでECRの最新イメージを読み込んで展開されます)*
```bash
cd terraform/app
terraform init
terraform apply
```

### Step 4: フロントエンドのデプロイ
Terraformが作成したAmplifyに対して、Reactアプリをビルドしてアップロードします。
```bash
cd frontend
./deploy.sh
```

---

## 3. 日常的なデプロイフロー (運用時)

どこを変更したかによって、必要な手順が異なります。

### パターンA: フロントエンド (React) だけを変更した場合
UIの変更など、フロントエンドのみの修正であれば、フロントエンドのデプロイだけで完結します。
```bash
cd frontend
./deploy.sh
```

### パターンB: バックエンド (FastAPI) だけを変更した場合
バックエンドのコードを変更した場合は、**イメージのPushと、TerraformのApplyの両方**が必要です。
(※ PushしただけではLambdaは自動更新されないため)
```bash
# 1. イメージのビルドとPush
cd backend
./scripts/build_and_push.sh

# 2. Lambdaに最新イメージを反映させる
cd terraform/app
terraform apply
```

### パターンC: インフラ (Terraform) を変更した場合
テーブルの追加や環境変数の変更などは、該当するTerraformディレクトリでApplyを実行します。
（※フロントエンド向けの環境変数を変更した場合は、環境変数を反映させるためにStep 4 のフロントエンドの再デプロイも必要になります）
