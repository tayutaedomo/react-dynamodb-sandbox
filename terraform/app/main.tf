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

  lambda_config {
    post_confirmation = aws_lambda_function.cognito_hook.arn
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
data "aws_region" "current" {}

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
  image_uri    = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/react-dynamodb-sandbox-backend:latest"

  # スクリプトで linux/arm64 としてビルドしたため必須
  architectures = ["arm64"]

  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      COGNITO_REGION       = data.aws_region.current.name
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.main.id
      DYNAMODB_TABLE_NAME  = aws_dynamodb_table.profiles.name
    }
  }
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

# -------------------------------------------------------------
# Phase 3: DynamoDB (Database)
# -------------------------------------------------------------

resource "aws_dynamodb_table" "profiles" {
  name         = "react-dynamodb-sandbox-profiles"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }
}

# Lambda 用の DynamoDB アクセス権限ポリシー
resource "aws_iam_policy" "lambda_dynamodb" {
  name        = "react-dynamodb-sandbox-lambda-dynamodb"
  description = "Allow Lambda to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.profiles.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

# -------------------------------------------------------------
# Phase 4: Cognito Post-Confirmation Hook (Lambda)
# -------------------------------------------------------------

data "archive_file" "cognito_hook" {
  type        = "zip"
  source_dir  = "${path.module}/hook"
  output_path = "${path.module}/hook.zip"
}

resource "aws_iam_role" "cognito_hook_exec" {
  name = "react-dynamodb-sandbox-cognito-hook-exec"
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

resource "aws_iam_role_policy_attachment" "cognito_hook_basic" {
  role       = aws_iam_role.cognito_hook_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "cognito_hook_dynamodb" {
  role       = aws_iam_role.cognito_hook_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

resource "aws_lambda_function" "cognito_hook" {
  function_name    = "react-dynamodb-sandbox-cognito-hook"
  role             = aws_iam_role.cognito_hook_exec.arn
  handler          = "main.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.cognito_hook.output_path
  source_code_hash = data.archive_file.cognito_hook.output_base64sha256
  
  # For simple scripts on Lambda without external dependencies, arm64 or x86_64 works fine.
  architectures = ["arm64"]

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.profiles.name
    }
  }
}

resource "aws_lambda_permission" "cognito_hook" {
  statement_id  = "AllowExecutionFromCognito"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cognito_hook.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}
