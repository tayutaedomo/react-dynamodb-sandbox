# Terraform (IaC)

## 概要
AWS 上にインフラストラクチャを構築するための Terraform コード群です。
Cognito User Pool、API Gateway、Lambda、DynamoDB などのリソースを管理します。

## 認証について
このプロジェクトの Terraform 実行は、手元の `aws sso login` や AWS CLI のプロファイルに依存します。認証情報を Terraform のコード内には保持しません。

## 実行手順
(Terraformの初期化、デプロイ手順などは、環境構築後に記載します)
