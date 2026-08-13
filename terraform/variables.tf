variable "app_name" {
  description = "The name for the application."
  type        = string
  default     = "today-in-sports"
}

# This app is standalone — it is NOT hosted under xomware.com. It owns its own
# apex domain and its own Route53 hosted zone (see route53.tf).
#
# Both todayinsports.app and today-in-sports.app were confirmed available at
# time of writing. After buying it, point the registrar's nameservers at the
# four NS values this stack outputs, then apply again.
variable "domain_name" {
  description = "Apex domain for the app, e.g. todayinsports.app. Must be registered and its nameservers pointed at this stack's hosted zone."
  type        = string
  default     = "todayinsports.app"
}

variable "enable_google_idp" {
  description = "Wire Google sign-in into the user pool. Requires /<app_name>/google/client-id and /client-secret to exist in SSM first — see cognito.tf."
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# CloudFront
variable "cloudfront_origin_path" {
  description = "Optional directory in the S3 bucket CloudFront requests content from."
  type        = string
  default     = ""
}

variable "us_canada_only" {
  description = "Georestrict the distribution to US and Canada."
  type        = bool
  default     = false
}

variable "custom_error_response_page_path" {
  description = "Custom error response page path for SPA routing."
  type        = string
  default     = "/index.html"
}

variable "retain_on_delete" {
  description = "Disable rather than delete the distribution on destroy."
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for CloudFront"
  type        = string
  default     = "TLSv1.2_2018"
}

variable "enable_cloudfront_cache" {
  description = "Setting this false zeroes default_ttl and max_ttl."
  type        = bool
  default     = true
}

# Lambda
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.13"
}

variable "lambda_trace_mode" {
  description = "X-Ray tracing mode for Lambda"
  type        = string
  default     = "Active"
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
}

# API Gateway
variable "api_stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "dev"
}

# See xomtracks-infrastructure/terraform/variables.tf for the full write-up:
# the pinned api-gateway-service module's per-origin CORS VTL always echoes
# origins_list[0] regardless of the request Origin, so a static "*" (the
# module-documented default) is the correct value rather than a list.
# Every route here is authorized NONE at the gateway with the Bearer token
# validated in-handler, so Origin is never used for authorization.
variable "cors_allowed_origins" {
  description = "CORS Access-Control-Allow-Origin for the API."
  type        = string
  default     = "*"
}

# Tags
variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "domgiordano"
}

variable "admin_email" {
  description = "Email address treated as the admin principal."
  type        = string
  default     = "dominickj.giordano@gmail.com"
}

# ============================================
# Secrets supplied by CI
#
# Values arrive as TF_VAR_* from GitHub Actions secrets, matching
# xomify-infrastructure. Terraform owns both the parameter and its value.
#
# Each defaults to "" and is coalesced to a placeholder before being written.
# That guard exists because an unset TF_VAR resolves to an empty string, which
# plan and validate accept silently and SSM's PutParameter then rejects outright
# (ValidationException: length >= 1) — exactly the failure xomtracks hit on its
# first real apply. Writing "unset" instead fails loudly in the app, where it is
# obvious, rather than at apply time in a way that looks like an infra bug.
# ============================================

variable "google_client_id" {
  description = "Google OAuth client id (TF_VAR_google_client_id)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "google_client_secret" {
  description = "Google OAuth client secret (TF_VAR_google_client_secret)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "balldontlie_api_key" {
  description = "balldontlie API key for NBA ingestion (TF_VAR_balldontlie_api_key)"
  type        = string
  default     = ""
  sensitive   = true
}
