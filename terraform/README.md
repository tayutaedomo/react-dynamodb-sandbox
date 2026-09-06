# Terraform (IaC)

## 1. 概要 (Overview)
AWS 上にインフラストラクチャを構築するための Terraform コード群です。
本プロジェクトでは、インフラの変更頻度（ライフサイクル）に合わせてディレクトリを分割し、用途に応じたデプロイ戦略を使い分けています。

---

## 2. ディレクトリ構成 (Directory Structure)

```text
terraform/
├── README.md
├── ecr/                 # コンテナレジストリ構築用（初回に一度だけ実行し、以後は原則として変更しない基盤）
└── app/                 # アプリケーション基盤用リソース群（開発の進行に合わせて頻繁に変更・適用される）
    ├── main.tf          # インフラ全体のリソース定義 (Cognito, API GW, DynamoDB, Lambda等)
    ├── outputs.tf       # apply 実行後に出力される変数の定義
    ├── variables.tf     # 外部から注入可能な変数の定義
    └── hook/            # Cognito イベントフック用 Lambda スクリプト
        ├── main.py      # トリガー実行される軽量な Python コード本体
        └── test_main.py # 上記スクリプトの単体テスト
```

### `app/hook/` ディレクトリについて
ここには、AWS Cognito などのイベントをトリガーにしてバックグラウンドで発火する「インフラ連動型の超軽量スクリプト」を配置しています。
バックエンド API (`/backend`) のように独立したアプリケーションとして切り出すまでもない、インフラ間の「糊（グルー）」となるような処理（初期ユーザーレコードの作成など）を記述します。

---

## 3. アーキテクチャとデプロイ戦略 (Lambda Deployment Strategies)

本プロジェクトでは、用途に応じて2つの異なる Lambda デプロイ戦略を使い分けています。
この設計により、開発体験と運用効率の最適化を図っています。

### A. バックエンド API 用 Lambda (`package_type = "Image"`)
* **用途**: FastAPI アプリケーション (`backend/` ディレクトリ)
* **特徴**: FastAPI や PynamoDB などの多数のサードパーティライブラリに依存するため、Docker コンテナとしてビルドし、AWS ECR にプッシュしたイメージの URI を参照してデプロイします。
* **更新方法**: コード変更時は `scripts/deploy.sh` (`build_and_push.sh` 相当) を実行して ECR を更新した後、`terraform apply` を行います。

### B. Cognito トリガー用 Lambda (`data "archive_file"`)
* **用途**: Cognito のイベントフック用スクリプト (`terraform/app/hook/` ディレクトリ)
* **特徴**: 外部ライブラリを一切持たず、AWS 環境標準の `boto3` のみで動作する超軽量スクリプトです。コンテナ化のオーバーヘッドを避けるため、Terraform 自身が直接 ZIP 化してアップロードします。
* **更新方法**: スクリプトを変更して `terraform apply` を実行するだけです。Terraform がスクリプトのハッシュ (`source_code_hash`) を計算し、差分がある場合のみ自動で再デプロイを行います。
  *(※ ローカルに生成される `.zip` ファイルは一時的なアーティファクトであるため、Gitの管理対象外です)*

---

## 4. デプロイ（環境構築）の実行手順

AWS Lambda (コンテナイメージ) をデプロイするためには「ECRにイメージが存在すること」が前提となるため、以下の順序で実行する必要があります。

### 前提: 認証について
このプロジェクトの Terraform 実行は、手元の `aws sso login` や AWS CLI のプロファイルに依存します。認証情報を Terraform のコード内には保持しません。

### Step 1: ECR リポジトリの作成
最初に、Docker イメージの保存先である ECR を作成します。
```bash
cd ecr
terraform init
terraform apply
```

### Step 2: Docker イメージのビルドと Push
ECR が作成されたら、バックエンドのコードを Docker コンテナとしてビルドし、ECR に Push します。
```bash
cd ../../backend
scripts/deploy.sh
```

### Step 3: アプリケーション基盤の作成
イメージがアップロードされたら、メインのアプリケーション基盤を作成します。ここでのデプロイ時に、`hook/` 配下のスクリプトも同時に ZIP 化され AWS にアップロードされます。
```bash
cd ../terraform/app
terraform init
terraform apply
```

---

## 5. デプロイの動作確認（正常性の判断基準）

デプロイ完了後、API Gateway のエンドポイントに対して疎通確認を行います。

1. 以下のコマンドで、構築された API のベース URL を確認します。
   ```bash
   terraform output api_endpoint
   ```
2. 出力された URL に `/api/health` を付与してアクセスします。
   ```bash
   curl <api_endpoint>/api/health
   ```
3. **【成功の基準】**
   レスポンスとして `{"status":"ok","message":"Backend is running"}` が返ってくれば、AWS 上へのインフラ構築・アプリのデプロイはすべて正常に完了しています。
