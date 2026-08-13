# ============================================
# SSM parameters
#
# Terraform owns the parameter — its path, type, KMS and IAM scoping — so
# nothing has to be created by hand and no Lambda ever hits ParameterNotFound.
# What Terraform does NOT own is the *value* of a third-party credential, for
# two reasons:
#
#   1. It cannot invent one. A balldontlie or Google key is issued by someone
#      else; no amount of HCL produces it.
#   2. Any value routed through Terraform lands in state in plaintext. State
#      lives in S3 and would then hold live secrets.
#
# So each secret is created with a real, non-empty placeholder and carries
# `ignore_changes = [value]`. Dom sets the value once, out of band, and
# Terraform never fights it afterwards.
#
# The placeholder is "unset", NOT "". This is the exact failure xomtracks hit:
# no-default variables wired to TF_VAR_* secrets that were never set resolved to
# an empty string, which plan and validate accepted silently, and then SSM's
# PutParameter rejected outright (ValidationException: length >= 1) on the first
# real apply.
# ============================================

locals {
  # A parameter still holding this has not been filled in yet. Features that
  # need a real credential check for it before switching themselves on.
  ssm_placeholder = "unset"
}

# --------------------------------------------------------------- balldontlie
#
# The NBA is the only sport in the corpus behind a credential — every keyless
# route is closed (stats.nba.com hangs for non-browser clients, cdn.nba.com
# returns 403, Basketball-Reference prohibits scraping). The free tier is
# sufficient and reaches back to 1946.
#
# Set the value with:
#   aws ssm put-parameter --name /today-in-sports/balldontlie/api-key \
#     --type SecureString --value 'YOUR_KEY' --overwrite
# The key was created by hand before Terraform managed this resource, so the
# first apply hit ParameterAlreadyExists. An import block adopts the existing
# parameter rather than trying to create it — and it runs during a normal
# `apply`, so nothing has to be done from a laptop or the console.
#
# Safe to delete once applied; it is only needed for the adoption.
import {
  to = aws_ssm_parameter.balldontlie_api_key
  id = "/today-in-sports/balldontlie/api-key"
}

resource "aws_ssm_parameter" "balldontlie_api_key" {
  name        = "/${var.app_name}/balldontlie/api-key"
  description = "balldontlie API key for NBA ingestion — value set out of band"
  type        = "SecureString"
  value       = local.ssm_placeholder

  lifecycle {
    ignore_changes = [value, tags, tags_all]
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
  description = "Google OAuth client id — value set out of band"
  type        = "SecureString"
  value       = local.ssm_placeholder

  lifecycle {
    ignore_changes = [value, tags, tags_all]
  }

  tags = merge(local.standard_tags, tomap({ "name" = "google-client-id" }))
}

resource "aws_ssm_parameter" "google_client_secret" {
  name        = "/${var.app_name}/google/client-secret"
  description = "Google OAuth client secret — value set out of band"
  type        = "SecureString"
  value       = local.ssm_placeholder

  lifecycle {
    ignore_changes = [value, tags, tags_all]
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
