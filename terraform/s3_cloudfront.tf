#**********************
# Web app hosting — private S3 origin behind CloudFront with OAC.
#
# Phase 1 serves the admin portal only; the public play surface lands here in
# phase 2. SPA routing is handled by the custom error response mapping 403/404
# back to /index.html.
#**********************

resource "aws_s3_bucket" "site" {
  bucket = local.domain_name
  tags   = merge(local.standard_tags, tomap({ "name" = local.domain_name }))
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3, deliberately, not the customer-managed key.
#
# CloudFront's origin access control reaches S3 as the *service* principal
# `cloudfront.amazonaws.com`. With SSE-KMS that principal also needs
# `kms:Decrypt` on the key, and the key policy here grants AWS principals in the
# account rather than service principals — so every object returned
# AccessDenied through the distribution while being perfectly readable directly.
#
# Granting CloudFront decrypt would work, but it is the wrong trade: this bucket
# holds a public website. Encrypting assets that are served to anyone with a
# customer-managed key buys no confidentiality and adds a KMS request charge to
# every origin fetch. The CMK is kept where it earns its place — the DynamoDB
# tables and the raw source archive.
resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.app_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Bucket is private; only this distribution may read it.
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipalReadOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
        }
      }
    }]
  })
}

resource "aws_acm_certificate" "cert" {
  # CloudFront requires its certificate in us-east-1; the provider is already
  # pinned there, so no aliased provider is needed.
  domain_name       = local.domain_name
  validation_method = "DNS"
  tags              = merge(local.standard_tags, tomap({ "name" = local.domain_name }))

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [local.domain_name]
  retain_on_delete    = var.retain_on_delete
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.site.id
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
    origin_path              = var.cloudfront_origin_path
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.site.id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # Managed-CachingOptimized
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id
  }

  # SPA routing: the Angular router owns paths, so S3's 403/404 for an unknown
  # key must return index.html rather than an error page.
  dynamic "custom_error_response" {
    for_each = [403, 404]
    content {
      error_code            = custom_error_response.value
      response_code         = 200
      response_page_path    = var.custom_error_response_page_path
      error_caching_min_ttl = 10
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.us_canada_only ? "whitelist" : "none"
      locations        = var.us_canada_only ? ["US", "CA"] : []
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = var.minimum_tls_version
  }

  tags = merge(local.standard_tags, tomap({ "name" = local.domain_name }))
}

resource "aws_cloudfront_response_headers_policy" "site" {
  name = "${var.app_name}-security-headers"

  security_headers_config {
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
  }
}

resource "aws_route53_record" "site" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
