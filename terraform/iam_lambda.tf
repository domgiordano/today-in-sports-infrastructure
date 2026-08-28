data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.app_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-lambda-role" }))
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${local.web_app_account_id}:*"]
  }

  statement {
    sid       = "Xray"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }

  statement {
    sid = "Ssm"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${local.web_app_account_id}:parameter/${var.app_name}/*"
    ]
  }

  statement {
    sid = "Kms"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    # The SSM key matters as much as the table key. SecureString parameters are
    # encrypted under the AWS-managed alias/aws/ssm key, so without decrypt on
    # it every GetParameter(WithDecryption=true) fails with AccessDenied — at
    # runtime only, since plan and apply are both perfectly happy.
    resources = [
      aws_kms_key.dynamodb.arn,
      data.aws_kms_alias.ssm.target_key_arn,
    ]
  }

  statement {
    sid = "Dynamo"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchWriteItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
    ]
    resources = [
      aws_dynamodb_table.games.arn,
      "${aws_dynamodb_table.games.arn}/index/*",
      aws_dynamodb_table.events.arn,
      "${aws_dynamodb_table.events.arn}/index/*",
      aws_dynamodb_table.questions.arn,
      "${aws_dynamodb_table.questions.arn}/index/*",
      aws_dynamodb_table.quizzes.arn,
      "${aws_dynamodb_table.quizzes.arn}/index/*",
      aws_dynamodb_table.source_runs.arn,
      aws_dynamodb_table.plays.arn,
      "${aws_dynamodb_table.plays.arn}/index/*",
      aws_dynamodb_table.reactions.arn,
      "${aws_dynamodb_table.reactions.arn}/index/*",
      aws_dynamodb_table.usernames.arn,
      "${aws_dynamodb_table.usernames.arn}/index/*",
      aws_dynamodb_table.comments.arn,
      "${aws_dynamodb_table.comments.arn}/index/*",
      aws_dynamodb_table.notifications.arn,
      "${aws_dynamodb_table.notifications.arn}/index/*",
      aws_dynamodb_table.request_log.arn,
      "${aws_dynamodb_table.request_log.arn}/index/*",
      aws_dynamodb_table.users.arn,
      "${aws_dynamodb_table.users.arn}/index/*",
      aws_dynamodb_table.groups.arn,
      "${aws_dynamodb_table.groups.arn}/index/*",
      aws_dynamodb_table.announcements.arn,
      aws_dynamodb_table.stats.arn
    ]
  }

  # Sending the daily mail, and only ever as this domain. Scoped to the
  # identity rather than "*" so a compromised handler cannot send as any other
  # verified sender on the account — and there are several, belonging to other
  # apps entirely.
  statement {
    sid       = "SendMailAsThisDomain"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = [aws_ses_domain_identity.main.arn]
  }

  # Read-only on the raw archive. Writes to it happen from the local ingestion
  # scripts under Dom's own credentials, not from a Lambda — nothing in the
  # request path should ever be able to mutate the source of record.
  statement {
    sid     = "RawArchiveRead"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.raw_archive.arn,
      "${aws_s3_bucket.raw_archive.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "lambda_role_policy" {
  name   = "${var.app_name}-lambda-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}
