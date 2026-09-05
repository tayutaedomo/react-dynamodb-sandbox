output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "cognito_region" {
  value = data.aws_region.current.name
}


output "api_endpoint" {
  value = aws_apigatewayv2_api.backend.api_endpoint
}
