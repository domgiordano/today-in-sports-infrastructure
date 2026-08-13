#**********************
# This app owns its own hosted zone.
#
# Not a data source pointed at xomware.com — Today in Sports is standalone and
# its DNS lives with it.
#
# Bootstrap ordering, which matters on a first apply:
#   1. Buy the domain at a registrar.
#   2. `terraform apply` — this zone is created and outputs four NS records.
#   3. Set those four nameservers at the registrar.
#   4. Wait for propagation, then apply again. The ACM certificates validate by
#      DNS, so they cannot issue until the registrar delegates to this zone;
#      until then apply will sit at certificate validation and eventually time
#      out. That is expected, not a failure of this config.
#**********************

resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "Managed by ${var.app_name}-infrastructure"

  tags = merge(local.standard_tags, tomap({ "name" = var.domain_name }))

  lifecycle {
    # Recreating a zone issues new nameservers and takes the domain offline
    # until the registrar is updated again.
    prevent_destroy = true
  }
}

# API Gateway custom domain DNS record
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.api_domain_name
  type    = "A"

  alias {
    name                   = module.api.domain_regional_domain_name
    zone_id                = module.api.domain_regional_zone_id
    evaluate_target_health = true
  }
}

output "nameservers" {
  description = "Set these four at the domain registrar, then apply again."
  value       = aws_route53_zone.main.name_servers
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_web_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "cognito_hosted_ui_domain" {
  value = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
}
