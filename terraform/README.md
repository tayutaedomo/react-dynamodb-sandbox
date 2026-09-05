# Terraform (IaC)

## 概要
AWS 上にインフラストラクチャを構築するための Terraform コード群です。
本プロジェクトでは、インフラのライフサイクル（変更頻度）に合わせてディレクトリを分割して管理しています。

* **`ecr/`**: AWS ECR リポジトリの構築用（初回に一度だけ実行し、以後は原則として変更しない基盤）
* **`app/`**: Cognito, Lambda, API Gateway, DynamoDB などのアプリケーション用リソース群（開発の進行に合わせて頻繁に変更・適用される）

## 認証について
このプロジェクトの Terraform 実行は、手元の `aws sso login` や AWS CLI のプロファイルに依存します。認証情報を Terraform のコード内には保持しません。

## デプロイ（環境構築）の実行手順

AWS Lambda (コンテナイメージ) をデプロイするためには「ECRにイメージが存在すること」が前提となるため、以下の順序で実行する必要があります。

### 1. ECR リポジトリの作成
最初に、Docker イメージの保存先である ECR を作成します。
```bash
cd ecr
terraform init
terraform apply
```

### 2. Docker イメージのビルドと Push
ECR が作成されたら、バックエンドのコードを Docker コンテナとしてビルドし、ECR に Push します。
```bash
cd ../../backend
scripts/deploy.sh
```

### 3. アプリケーション基盤の作成
イメージがアップロードされたら、メインのアプリケーション基盤を作成します。
```bash
cd ../terraform/app
terraform init
terraform apply
```
