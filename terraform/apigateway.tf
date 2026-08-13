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
  # Phase 1 exposes admin routes only. `authorization` is NONE at the gateway;
  # each handler validates the Bearer token in-handler and checks the caller
  # against ADMIN_EMAIL. This matches xomify and xomtracks.
  admin_endpoints = [
    for l in local.admin_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.admin[l.name].invoke_arn
      authorization = "NONE"
    }
  ]
}

module "api" {
  source = "git::https://github.com/domgiordano/api-gateway-service.git?ref=v2.7.0"

  app_name      = var.app_name
  stage_name    = var.api_stage_name
  authorization = "NONE"
  cognito_user_pool_arns = [
    data.aws_ssm_parameter.cognito_user_pool_arn.value
  ]
  tags          = local.standard_tags
  allow_headers = local.api_allow_headers
  allow_origin  = var.cors_allowed_origins

  domain_name     = local.api_domain_name
  certificate_arn = aws_acm_certificate_validation.api.certificate_arn

  services = {
    admin = { path_prefix = "admin", endpoints = local.admin_endpoints }
  }
}
