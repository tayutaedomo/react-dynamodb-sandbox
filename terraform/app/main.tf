terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


# AWSの仕様上、Amplify 向けの WAF (CloudFront互換) は必ず us-east-1 に作成する必要があるため、
# マルチリージョンデプロイ用のエイリアスプロバイダを定義しています。
provider "aws" {
  region = "us-east-1"
  alias  = "us_east_1"
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

# 【重要】Lambda の CloudWatch ロググループの事前作成について
# Lambda はアタッチ設定がなくても、`/aws/lambda/関数名` と完全一致する
# ロググループが事前に存在すれば、自動的にそれを認識してログを書き込みます。
# ここで明示的に定義しておかないと、Lambda が永久保存設定のロググループを
# 勝手に作成してしまい、terraform destroy 時に削除漏れ（孤立）が発生します。
resource "aws_cloudwatch_log_group" "backend_lambda" {
  name              = "/aws/lambda/react-dynamodb-sandbox-backend"
  retention_in_days = 14
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
      # フロントエンドのURLを動的に注入（手動デプロイ構成のため循環依存は発生しない）
      FRONTEND_URL = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.frontend.id}.amplifyapp.com,https://${aws_cloudfront_distribution.spa.domain_name}"
    }
  }
}

# API Gateway (REST API)
# ※ HTTP API (v2) は安価ですが AWS WAF に非対応のため、
# WAF によるレート制限等の保護を行う目的で REST API (v1) を採用しています。
resource "aws_api_gateway_rest_api" "backend" {
  name = "react-dynamodb-sandbox-api"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.backend.id
  parent_id   = aws_api_gateway_rest_api.backend.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.backend.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.backend.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.backend.invoke_arn
}

resource "aws_api_gateway_deployment" "backend" {
  depends_on = [
    aws_api_gateway_integration.lambda,
  ]
  rest_api_id = aws_api_gateway_rest_api.backend.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "default" {
  deployment_id = aws_api_gateway_deployment.backend.id
  rest_api_id   = aws_api_gateway_rest_api.backend.id
  stage_name    = "default"
}

# API Gateway から Lambda を呼び出す権限
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.backend.execution_arn}/*/*"
}

# -------------------------------------------------------------
# Phase 2.5: AWS WAF (Rate-based rules & CloudWatch Logs)
# -------------------------------------------------------------

# CloudWatch Logs for WAF (API Gateway)
resource "aws_cloudwatch_log_group" "waf_api" {
  name              = "aws-waf-logs-api"
  retention_in_days = 14
}

# AWS WAF for API Gateway (Regional)
resource "aws_wafv2_web_acl" "api" {
  name        = "react-dynamodb-sandbox-api-waf"
  description = "WAF for API Gateway"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "api-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "api-waf"
    sampled_requests_enabled   = true
  }
}

# Enable WAF Logging for API Gateway
resource "aws_wafv2_web_acl_logging_configuration" "api" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_api.arn]
  resource_arn            = aws_wafv2_web_acl.api.arn
}

# Attach WAF to API Gateway
resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_api_gateway_stage.default.arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}

# CloudWatch Logs for WAF (Amplify)
# Amplify Hosting 標準のアクセスログは2週間で消失してしまうため、
# ログ保持期間の制限を回避する目的で WAF トラフィックログを CloudWatch に長期保存します。 - created in global region? No, cloudwatch logs must be in the same region as the resource. Wait, for GLOBAL WAF, the logs must be in us-east-1.
resource "aws_cloudwatch_log_group" "waf_amplify" {
  provider          = aws.us_east_1
  name              = "aws-waf-logs-amplify"
  retention_in_days = 90 # 長期保存
}

# AWS WAF for Amplify (Global)
# Amplify Hosting の前段に配置する WAF。CloudFront 互換のスコープ (CLOUDFRONT) を指定し、
# provider = aws.us_east_1 によってバージニア北部リージョンに作成します。
resource "aws_wafv2_web_acl" "amplify" {
  provider    = aws.us_east_1
  name        = "react-dynamodb-sandbox-amplify-waf"
  description = "WAF for Amplify Hosting"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "amplify-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "amplify-waf"
    sampled_requests_enabled   = true
  }
}

# Enable WAF Logging for Amplify
resource "aws_wafv2_web_acl_logging_configuration" "amplify" {
  provider                = aws.us_east_1
  log_destination_configs = [aws_cloudwatch_log_group.waf_amplify.arn]
  resource_arn            = aws_wafv2_web_acl.amplify.arn
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

# 【重要】Lambda の CloudWatch ロググループの事前作成について
# Lambda はアタッチ設定がなくても、`/aws/lambda/関数名` と完全一致する
# ロググループが事前に存在すれば、自動的にそれを認識してログを書き込みます。
# ここで明示的に定義しておかないと、Lambda が永久保存設定のロググループを
# 勝手に作成してしまい、terraform destroy 時に削除漏れ（孤立）が発生します。
resource "aws_cloudwatch_log_group" "cognito_hook_lambda" {
  name              = "/aws/lambda/react-dynamodb-sandbox-cognito-hook"
  retention_in_days = 14
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

# -------------------------------------------------------------
# Phase 5: Amplify Hosting (Frontend)
# -------------------------------------------------------------

resource "aws_amplify_app" "frontend" {
  name = "react-dynamodb-sandbox-frontend"

  # 手動デプロイ構成のため repository は指定しない
  # ※ 以前は environment_variables を設定していましたが、手動デプロイ構成においては
  #    デプロイスクリプト側で Terraform output から環境変数を生成するため不要です。
  #    （また、ここに API Gateway の URL を入れると循環依存が発生するため削除しています）

  # SPA(Single Page Application)のためのリダイレクト設定
  custom_rule {
    source = "</^[^.]+$|\\.(?!(css|gif|ico|jpg|js|png|txt|svg|woff|woff2|ttf|map|json)$)([^.]+$)/>"
    status = "200"
    target = "/index.html"
  }
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = "main"
}

# Attach WAF to Amplify Hosting
resource "aws_wafv2_web_acl_association" "amplify" {
  provider     = aws.us_east_1
  resource_arn = aws_amplify_app.frontend.arn
  web_acl_arn  = aws_wafv2_web_acl.amplify.arn
}

# -------------------------------------------------------------
# Phase 6: CloudFront + S3 (Alternative SPA Hosting)
# Amplify とは別の、CloudFront と S3 を組み合わせた静的ウェブサイトホスティング環境
# -------------------------------------------------------------

# バケット名がグローバルで一意になるようにランダムな文字列を生成
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# SPA の静的ファイルを保存する S3 バケット
resource "aws_s3_bucket" "spa" {
  bucket = "react-dynamodb-sandbox-spa-${random_string.bucket_suffix.result}"
}

# セキュリティ対策: S3 バケットのパブリックアクセスを完全にブロック
resource "aws_s3_bucket_public_access_block" "spa" {
  bucket                  = aws_s3_bucket.spa.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront から S3 へ安全にアクセスするための OAC (Origin Access Control)
resource "aws_cloudfront_origin_access_control" "spa" {
  name                              = "react-dynamodb-sandbox-spa-oac"
  description                       = "OAC for SPA S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront 用の WAF アクセスログを長期保存するための CloudWatch ロググループ
resource "aws_cloudwatch_log_group" "waf_cloudfront" {
  provider          = aws.us_east_1
  name              = "aws-waf-logs-cloudfront"
  retention_in_days = 90
}

# CloudFront 用の WAF (グローバルに作成する必要があるため us-east-1 を指定)
resource "aws_wafv2_web_acl" "cloudfront" {
  provider    = aws.us_east_1
  name        = "react-dynamodb-sandbox-cloudfront-waf"
  description = "WAF for CloudFront SPA Hosting"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cloudfront-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "cloudfront-waf"
    sampled_requests_enabled   = true
  }
}

# CloudFront 用 WAF のロギング設定 (CloudWatch Logs へ転送)
resource "aws_wafv2_web_acl_logging_configuration" "cloudfront" {
  provider                = aws.us_east_1
  log_destination_configs = [aws_cloudwatch_log_group.waf_cloudfront.arn]
  resource_arn            = aws_wafv2_web_acl.cloudfront.arn
}

# CloudFront ディストリビューション
resource "aws_cloudfront_distribution" "spa" {
  origin {
    domain_name              = aws_s3_bucket.spa.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.spa.id
    origin_access_control_id = aws_cloudfront_origin_access_control.spa.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # CloudFront の場合はアソシエーションリソースではなく、ここに WAF の ARN を直接指定する
  web_acl_id = aws_wafv2_web_acl.cloudfront.arn

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.spa.id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # SPA (React Router等) のためのフォールバック設定
  # 存在しないパスへのアクセス (403/404) をすべて index.html に転送し、ステータス 200 で返す
  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }

  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# S3 バケットポリシー: CloudFront (OAC) からの読み取りアクセスのみを許可する
resource "aws_s3_bucket_policy" "spa" {
  bucket = aws_s3_bucket.spa.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.spa.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.spa.arn
          }
        }
      }
    ]
  })
}
