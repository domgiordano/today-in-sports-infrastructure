#**********************
# GitHub Actions OIDC
# Keyless auth for the frontend and backend deploy workflows
#**********************

# Account-wide, created by whichever stack migrated first.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_subjects = {
    frontend = var.github_frontend_subjects
    backend  = var.github_backend_subjects
  }
}

data "aws_iam_policy_document" "github_actions_trust" {
  for_each = local.github_oidc_subjects

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for subject in each.value : "${subject}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  for_each = local.github_oidc_subjects

  name               = "${var.app_name}-github-actions-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust[each.key].json

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-github-actions-${each.key}" }))
}

data "aws_iam_policy_document" "github_actions_frontend" {
  statement {
    sid    = "PublishSite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.site.arn,
      "${aws_s3_bucket.site.arn}/*",
    ]
  }

  # The deploy resolves its distribution by alias at runtime and
  # ListDistributions has no resource form -- account-wide or nothing.
  statement {
    sid       = "FindDistribution"
    effect    = "Allow"
    actions   = ["cloudfront:ListDistributions"]
    resources = ["*"]
  }

  statement {
    sid    = "InvalidateCache"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
    ]
    resources = [aws_cloudfront_distribution.site.arn]
  }

  # The site bucket is KMS-encrypted, so writing an object needs the key as well
  # as the bucket -- s3:PutObject alone fails with AccessDenied on
  # kms:GenerateDataKey.
  statement {
    sid    = "UseWebAppKey"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_alias.web_app.target_key_arn]
  }
}

resource "aws_iam_role_policy" "github_actions_frontend" {
  name   = "deploy"
  role   = aws_iam_role.github_actions["frontend"].id
  policy = data.aws_iam_policy_document.github_actions_frontend.json
}

data "aws_iam_policy_document" "github_actions_backend" {
  statement {
    sid    = "ManageSharedLayer"
    effect = "Allow"
    actions = [
      "lambda:PublishLayerVersion",
      "lambda:ListLayerVersions",
      "lambda:GetLayerVersion",
    ]
    resources = [
      "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:layer:${var.app_name}-shared-packages",
      "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:layer:${var.app_name}-shared-packages:*",
    ]
  }

  # By name prefix, so a new lambda needs no IAM change to be deployable.
  statement {
    sid    = "DeployFunctions"
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
    ]
    resources = ["arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:function:${var.app_name}-*"]
  }

  statement {
    sid       = "ListLayers"
    effect    = "Allow"
    actions   = ["lambda:ListLayers", "lambda:ListFunctions"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_backend" {
  name   = "deploy"
  role   = aws_iam_role.github_actions["backend"].id
  policy = data.aws_iam_policy_document.github_actions_backend.json
}

output "github_actions_frontend_role_arn" {
  value = aws_iam_role.github_actions["frontend"].arn
}

output "github_actions_backend_role_arn" {
  value = aws_iam_role.github_actions["backend"].arn
}
