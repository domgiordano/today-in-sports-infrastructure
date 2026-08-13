#**********************
# Cognito — this app owns its identity surface outright.
#
# Deliberately NOT the shared xomware_users pool that xomify/xomtracks/xomforms
# consume. Today in Sports is a standalone product: its users are the public,
# not Dom, and it must be able to live or die without touching anything else in
# the org. The only intended link back to xomware is an app tile on the landing
# page.
#
# Practical upside: this removes the cross-repo blocker entirely. Nothing here
# waits on an SSM parameter being exported from another repo's apply.
#**********************

resource "aws_cognito_user_pool" "main" {
  name = "${var.app_name}-users"

  # Email is the identity. Usernames are a support burden nobody asked for.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  # Eight characters, one number, no forced uppercase or symbols.
  #
  # Deliberately light. An account here holds a quiz streak, a display name and
  # an email — no payments, nothing personal. The worst case of a compromise is
  # someone else's trivia history, while every additional rule costs real
  # signups at the moment a person is deciding whether to bother.
  #
  # It also matches current NIST guidance, which argues against mandatory
  # composition rules: they push people toward "Password1!" patterns that are
  # easier to guess, not harder. Length is what helps.
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = false
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your Today in Sports verification code"
    email_message        = "Your verification code is {####}"
  }

  # Cognito's built-in sender is capped at 50 emails/day and is fine for phase 1
  # (admin only). Moving to SES is a phase-2 task, before the play surface opens
  # to the public.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 5
      max_length = 254
    }
  }

  # Set at signup so an anonymous player's streak and history survive account
  # creation. Losing a streak at the moment of signup is exactly when people
  # quit, and it is trivially avoidable if the field exists from day one.
  schema {
    name                     = "device_id"
    attribute_data_type      = "String"
    required                 = false
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 0
      max_length = 64
    }
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-users" }))

  lifecycle {
    # Renaming or replacing a pool orphans every account in it.
    prevent_destroy = true
  }
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.app_name}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false # public SPA client — a secret cannot be kept

  # USER_PASSWORD_AUTH lets the app present its own sign-in form and call
  # Cognito directly, rather than redirecting to the hosted UI. The password
  # crosses the wire under TLS to Cognito's own endpoint and is never stored.
  #
  # SRP would avoid sending it at all, but needs a sizeable client library for a
  # difference that only matters if TLS is already broken. The hosted UI is the
  # thing being avoided here: it cannot be styled, and bouncing someone to a
  # different-looking page mid-signup is the worst part of the flow.
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  supported_identity_providers = concat(
    ["COGNITO"],
    var.enable_google_idp ? ["Google"] : [],
  )

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = [
    "https://${local.domain_name}/auth/callback",
    "http://localhost:4200/auth/callback",
  ]
  logout_urls = [
    "https://${local.domain_name}",
    "http://localhost:4200",
  ]

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"

  depends_on = [aws_cognito_identity_provider.google]
}

#**********************
# Hosted UI domain
#
# Uses the Cognito prefix domain for now. A custom domain (auth.<domain>)
# requires an ACM cert AND an existing A record at the zone apex, which is a
# first-apply ordering hazard. Worth doing before the public play surface ships
# in phase 2 — the prefix domain is only ever visible during an OAuth redirect,
# and phase 1 is admin-only.
#**********************

resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.app_name
  user_pool_id = aws_cognito_user_pool.main.id
}

#**********************
# Google sign-in
#
# Credentials come from TF_VAR_google_client_* (GitHub secrets), the same route
# as every other secret here. Read straight from the variables rather than via a
# data source on the SSM parameter: Terraform writes those parameters in this
# same apply, so a read-back would race its own write.
#**********************

resource "aws_cognito_identity_provider" "google" {
  count = var.enable_google_idp ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "email openid profile"
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}
