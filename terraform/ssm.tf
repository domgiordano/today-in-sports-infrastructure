# ============================================
# SSM parameters
#
# Terraform owns both the parameter and its value, matching
# xomify-infrastructure. Secrets arrive as TF_VAR_* from GitHub Actions secrets,
# so the only place a credential is pasted is the repo's secret store — never a
# console, never an ad-hoc CLI call.
#
# The accepted cost is that these values live in Terraform state, which sits in
# the private, encrypted xomware-terraform-state bucket.
#
# The one generated in-stack (the API signing key) needs no human input at all,
# which is strictly better where it is possible.
# ============================================

locals {
  # A parameter still holding this has not been filled in yet. Features that
  # need a real credential check for it before switching themselves on.
  ssm_placeholder = "unset"

  # Coalesce empties to the placeholder. SSM rejects an empty value outright,
  # so an unset CI secret would otherwise fail the apply rather than the feature.
  google_client_id     = var.google_client_id != "" ? var.google_client_id : local.ssm_placeholder
  google_client_secret = var.google_client_secret != "" ? var.google_client_secret : local.ssm_placeholder
  balldontlie_api_key  = var.balldontlie_api_key != "" ? var.balldontlie_api_key : local.ssm_placeholder
}

# --------------------------------------------------------------- balldontlie
#
# The NBA is the only sport in the corpus behind a credential — every keyless
# route is closed (stats.nba.com hangs for non-browser clients, cdn.nba.com
# returns 403, Basketball-Reference prohibits scraping). The free tier is
# sufficient and reaches back to 1946.
#
# Value comes from the BALLDONTLIE_API_KEY repo secret via TF_VAR.
resource "aws_ssm_parameter" "balldontlie_api_key" {
  name        = "/${var.app_name}/balldontlie/api-key"
  description = "balldontlie API key for NBA ingestion"
  type        = "SecureString"
  value       = local.balldontlie_api_key

  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  tags = merge(local.standard_tags, tomap({ "name" = "balldontlie-api-key" }))
}

# --------------------------------------------------------------------- Google
#
# Only consumed when `enable_google_idp` is true. Creating the parameters
# unconditionally means the path exists and is IAM-scoped from the first apply,
# so turning Google sign-in on later is a one-variable change rather than a
# chicken-and-egg.
resource "aws_ssm_parameter" "google_client_id" {
  name        = "/${var.app_name}/google/client-id"
  description = "Google OAuth client id"
  type        = "SecureString"
  value       = local.google_client_id

  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  tags = merge(local.standard_tags, tomap({ "name" = "google-client-id" }))
}

resource "aws_ssm_parameter" "google_client_secret" {
  name        = "/${var.app_name}/google/client-secret"
  description = "Google OAuth client secret"
  type        = "SecureString"
  value       = local.google_client_secret

  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  tags = merge(local.standard_tags, tomap({ "name" = "google-client-secret" }))
}

# ---------------------------------------------------------- API signing secret
#
# Generated in-stack rather than supplied, so it needs no manual step at all.
resource "random_password" "api_secret_key" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "api_secret_key" {
  name        = "/${var.app_name}/api/API_SECRET_KEY"
  description = "HS256 signing key for internal API tokens — generated in-stack"
  type        = "SecureString"
  value       = random_password.api_secret_key.result

  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  tags = merge(local.standard_tags, tomap({ "name" = "api-secret-key" }))
}
