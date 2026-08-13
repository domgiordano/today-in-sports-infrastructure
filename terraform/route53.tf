#**********************
# Hosted zone — read, not created.
#
# Registering a domain through Route53 Domains creates its hosted zone
# automatically, and the registration points the domain's delegation at that
# zone. Declaring `resource "aws_route53_zone"` here would create a *second*
# zone with different nameservers, which the domain would ignore — records would
# apply cleanly to a zone nothing resolves against, and DNS would silently not
# work.
#
# Reading it instead keeps ownership consistent: the domain and its zone are
# created by registration, Terraform manages the records inside. It also removes
# the two-pass apply entirely — delegation is already correct, so ACM's DNS
# validation succeeds on the first run.
#**********************

data "aws_route53_zone" "main" {
  name         = "${var.domain_name}."
  private_zone = false
}

# API Gateway custom domain DNS record
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.api_domain_name
  type    = "A"

  alias {
    name                   = module.api.domain_regional_domain_name
    zone_id                = module.api.domain_regional_zone_id
    evaluate_target_health = true
  }
}

output "hosted_zone_id" {
  description = "The zone Route53 Domains created at registration."
  value       = data.aws_route53_zone.main.zone_id
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

# Consumed by the local ingestion scripts — see docs DEPLOY.md. Raw payloads are
# archived here before parsing, and that archive is the source of record once
# ingestion completes.
output "raw_archive_bucket" {
  value = aws_s3_bucket.raw_archive.id
}

output "api_domain" {
  value = local.api_domain_name
}

output "site_domain" {
  value = local.domain_name
}

output "dynamodb_tables" {
  value = {
    games       = aws_dynamodb_table.games.id
    events      = aws_dynamodb_table.events.id
    questions   = aws_dynamodb_table.questions.id
    quizzes     = aws_dynamodb_table.quizzes.id
    source_runs = aws_dynamodb_table.source_runs.id
  }
}
