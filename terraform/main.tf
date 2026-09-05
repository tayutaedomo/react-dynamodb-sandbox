terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
  # 認証情報はコード内に持たず、実行時の AWS_PROFILE 等に依存します。
}

resource "aws_cognito_user_pool" "main" {
  name = "react-dynamodb-sandbox-pool"

  # Username (任意の文字列ID) によるログインを想定
  alias_attributes = []

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  # ユーザー自身のサインアップを許可せず、管理者(AWSコンソール)からの作成のみ許可
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "react-dynamodb-sandbox-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # React(SPA)から直接利用するため、シークレットは不要
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}
