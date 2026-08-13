#**********************
# API Gateway (via the shared reusable module)
#
# `aws_api_gateway_account` is an account-level singleton and is deliberately
# NOT managed here — see the write-up in xomtracks-infrastructure/terraform/
# apigateway.tf. Multiple app repos each managing it caused perpetual drift as
# every apply flipped the account's cloudwatch_role_arn between apps. It belongs
# in xomware-infrastructure.
#**********************

locals {
  # Admin routes are gated by the Cognito user-pool authorizer, so API Gateway
  # verifies the JWT signature and expiry before a handler runs and hands the
  # claims through as `requestContext.authorizer.claims`.
  #
  # These were NONE, which meant that context was never populated at all — the
  # handlers looked for a caller email, found nothing, and returned 401 to
  # everyone including the admin. Being an admin is still checked in-handler
  # against ADMIN_EMAIL; the gateway only establishes *who* is calling.
  play_endpoints = [
    for l in local.play_lambdas : {
      name        = l.name
      path_part   = l.path_part
      http_method = l.http_method
      invoke_arn  = aws_lambda_function.play[l.name].invoke_arn
      # Public. Anonymous players are first-class here.
      authorization = "NONE"
    }
  ]

  account_endpoints = [
    for l in local.account_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.account[l.name].invoke_arn
      authorization = "COGNITO_USER_POOLS"
    }
  ]

  admin_endpoints = [
    for l in local.admin_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.admin[l.name].invoke_arn
      authorization = "COGNITO_USER_POOLS"
    }
  ]
}

module "api" {
  source = "git::https://github.com/domgiordano/api-gateway-service.git?ref=v2.7.0"

  app_name      = var.app_name
  stage_name    = var.api_stage_name
  authorization = "NONE"
  cognito_user_pool_arns = [
    aws_cognito_user_pool.main.arn
  ]
  tags          = local.standard_tags
  allow_headers = local.api_allow_headers
  allow_origin  = var.cors_allowed_origins

  domain_name     = local.api_domain_name
  certificate_arn = aws_acm_certificate_validation.api.certificate_arn

  services = {
    admin   = { path_prefix = "admin", endpoints = local.admin_endpoints }
    play    = { path_prefix = "play", endpoints = local.play_endpoints }
    account = { path_prefix = "account", endpoints = local.account_endpoints }
  }
}
