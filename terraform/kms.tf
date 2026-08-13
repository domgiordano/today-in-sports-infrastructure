#**********************
# DynamoDB CMK
#**********************

resource "aws_kms_key" "dynamodb" {
  description         = "KMS CMK for ${var.app_name} DynamoDB tables"
  enable_key_rotation = true
  tags                = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-dynamodb" }))
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${var.app_name}-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}

#**********************
# Web app S3 CMK
#
# Needs a policy permitting CloudFront to decrypt objects it serves.
#**********************

resource "aws_kms_key" "web_app" {
  description         = "KMS CMK for ${var.app_name} web app S3 bucket"
  enable_key_rotation = true
  tags                = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-web-app" }))

  policy = jsonencode({
    "Id" : "KMSKeyPolicy",
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "Full key access for account root",
        "Effect" : "Allow",
        "Principal" : { "AWS" : ["arn:aws:iam::${local.web_app_account_id}:root"] },
        "Action" : ["kms:*"],
        "Resource" : "*"
      },
      {
        "Sid" : "Key access for any services with S3 bucket access",
        "Effect" : "Allow",
        "Principal" : { "AWS" : ["*"] },
        "Action" : [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ],
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : { "kms:CallerAccount" : local.web_app_account_id }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "web_app" {
  name          = "alias/${var.app_name}-web-app"
  target_key_id = aws_kms_key.web_app.key_id
}

#**********************
# AWS-managed SSM key
#
# SecureString parameters are encrypted under this unless a CMK is named. The
# Lambda role needs decrypt on it to read any secret — see iam_lambda.tf.
#**********************

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}
