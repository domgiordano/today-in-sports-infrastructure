# ============================================
# Recurring pipeline
#
# History is immutable, so nothing here re-fetches the backfill. 1871 onwards is
# ingested once and never touched again.
#
# What decays is tier 1 — "the last twelve months" — which goes stale
# continuously. That is the only thing these crons exist to maintain, plus the
# scheduling buffer that keeps a bad week from becoming a missing quiz.
#
# Declarative list into for_each, matching the pattern in
# xomify-infrastructure/terraform/lambdas_cron.tf and xomtracks'.
# ============================================

locals {
  cron_lambdas = [
    {
      name        = "ingest-recent"
      description = "Weekly: ingest the last 8 days from the live APIs into draft questions"
      # Monday 09:00 UTC — after the weekend's results are final everywhere.
      schedule             = "cron(0 9 ? * MON *)"
      schedule_description = "Mondays at 09:00 UTC"
      timeout              = 900
      memory               = 1024
    },
    {
      name        = "assemble-quizzes"
      description = "Monthly: propose the next 60 days of quizzes from the approved bank"
      # 1st of the month, 10:00 UTC — an hour after a Monday ingest could run.
      schedule             = "cron(0 10 1 * ? *)"
      schedule_description = "1st of each month at 10:00 UTC"
      timeout              = 600
      memory               = 512
    },
  ]
}

resource "aws_lambda_function" "cron" {
  for_each         = { for l in local.cron_lambdas : l.name => l }
  function_name    = "${var.app_name}-cron-${each.value.name}"
  description      = each.value.description
  filename         = "./templates/lambda_stub.zip"
  source_code_hash = filebase64sha256("./templates/lambda_stub.zip")
  handler          = "handler.handler"
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
  runtime          = var.lambda_runtime

  # Ingestion walks several days of external APIs, so it needs far longer than
  # a request-path Lambda.
  timeout     = each.value.timeout
  memory_size = each.value.memory
  role        = aws_iam_role.lambda_role.arn

  environment {
    variables = local.lambda_variables
  }

  tracing_config {
    mode = var.lambda_trace_mode
  }

  tags = merge(local.standard_tags, tomap({
    "name"        = "${var.app_name}-cron-${each.value.name}",
    "lambda_type" = "cron"
  }))

  lifecycle {
    ignore_changes = [
      description,
      filename,
      source_code_hash,
      layers
    ]
  }

  depends_on = [
    aws_iam_role_policy.lambda_role_policy,
    aws_iam_role.lambda_role
  ]
}

resource "aws_cloudwatch_event_rule" "cron" {
  for_each            = { for l in local.cron_lambdas : l.name => l }
  name                = "${var.app_name}-cron-${each.value.name}"
  description         = "${each.value.description} (${each.value.schedule_description})"
  schedule_expression = each.value.schedule

  tags = merge(local.standard_tags, tomap({
    "name" = "${var.app_name}-cron-${each.value.name}"
  }))
}

resource "aws_cloudwatch_event_target" "cron" {
  for_each  = { for l in local.cron_lambdas : l.name => l }
  rule      = aws_cloudwatch_event_rule.cron[each.key].name
  target_id = "${var.app_name}-cron-${each.value.name}"
  arn       = aws_lambda_function.cron[each.key].arn
}

resource "aws_lambda_permission" "cron" {
  for_each      = { for l in local.cron_lambdas : l.name => l }
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cron[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cron[each.key].arn
}
