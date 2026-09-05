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
}

# -------------------------------------------------------------
# Phase 1: Cognito (Authentication)
# -------------------------------------------------------------

resource "aws_cognito_user_pool" "main" {
  name = "react-dynamodb-sandbox-pool"

  alias_attributes = []

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "react-dynamodb-sandbox-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}


# -------------------------------------------------------------
# Phase 2: Lambda & API Gateway (Backend)
# -------------------------------------------------------------

data "aws_caller_identity" "current" {}

# Lambda 実行用 IAM ロール
resource "aws_iam_role" "lambda_exec" {
  name = "react-dynamodb-sandbox-lambda-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# CloudWatch Logs への書き込み権限を付与
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda 関数 (コンテナイメージ)
resource "aws_lambda_function" "backend" {
  function_name = "react-dynamodb-sandbox-backend"
  role          = aws_iam_role.lambda_exec.arn

  # 先ほどスクリプトで Push したイメージの URI を指定
  package_type = "Image"
  image_uri    = "${data.aws_caller_identity.current.account_id}.dkr.ecr.ap-northeast-1.amazonaws.com/react-dynamodb-sandbox-backend:latest"

  # スクリプトで linux/arm64 としてビルドしたため必須
  architectures = ["arm64"]

  timeout     = 30
  memory_size = 256
}

# API Gateway (HTTP API)
resource "aws_apigatewayv2_api" "backend" {
  name          = "react-dynamodb-sandbox-api"
  protocol_type = "HTTP"

  # フロントエンドからのリクエストを許可する CORS 設定
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["*"]
    allow_headers = ["*"]
  }
}

# Lambda への統合設定
resource "aws_apigatewayv2_integration" "backend" {
  api_id           = aws_apigatewayv2_api.backend.id
  integration_type = "AWS_PROXY"

  integration_method     = "POST"
  integration_uri        = aws_lambda_function.backend.invoke_arn
  payload_format_version = "2.0"
}

# ルーティング設定 (すべてのパスを Lambda に流す)
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.backend.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.backend.id}"
}

# ステージ設定
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.backend.id
  name        = "$default"
  auto_deploy = true
}

# API Gateway から Lambda を呼び出す権限
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.backend.execution_arn}/*/*"
}
