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
  value = aws_api_gateway_stage.default.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}

output "amplify_app_url" {
  value = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.frontend.default_domain}"
}

output "amplify_branch_name" {
  value = aws_amplify_branch.main.branch_name
}
