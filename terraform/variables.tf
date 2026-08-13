variable "app_name" {
  description = "The name for the application."
  type        = string
  default     = "today-in-sports"
}

# Hosted under the xomware.com zone by default, matching the other apps.
# If a standalone domain is bought later (today-in-sports.app and
# todayinsports.app were both confirmed available), this and
# route53_zone_name are the only two values that change.
variable "domain_suffix" {
  description = "Suffix for the domain of the app."
  type        = string
  default     = ".xomware.com"
}

variable "route53_zone_name" {
  description = "Route53 hosted zone name for DNS records"
  type        = string
  default     = "xomware.com"
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
  default     = "python3.12"
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
