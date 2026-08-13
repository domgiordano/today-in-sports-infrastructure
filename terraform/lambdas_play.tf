# ============================================
# Play surface — the first PUBLIC routes.
#
# Everything before this sat behind the admin gate. These are open by design:
# anyone can play, signed in or not. The identity a caller supplies decides
# leaderboard eligibility later, never whether they may play.
#
# Anti-cheat lives in the handlers, not here — questions are served one at a
# time, answers are never in a payload, and timing is stamped server-side.
# ============================================

locals {
  play_lambdas = [
    {
      name        = "start"
      description = "Public: begin or resume today's quiz, returns question one without its answer"
      path_part   = "start"
      http_method = "POST"
    },
    {
      name        = "answer"
      description = "Public: grade one answer server-side and return the next question"
      path_part   = "answer"
      http_method = "POST"
    },
    {
      name        = "hint"
      description = "Public: release the multiple-choice options in exchange for part of the credit"
      path_part   = "hint"
      http_method = "POST"
    },
    {
      name        = "announcements"
      description = "Public: anything the product needs to tell players"
      path_part   = "announcements"
      http_method = "GET"
    },
    {
      name        = "leaderboard"
      description = "Public: the day's scores, plus the caller's own standing"
      path_part   = "leaderboard"
      http_method = "GET"
    },
    {
      name        = "name"
      description = "Public: attach a display name to a finished round"
      path_part   = "name"
      http_method = "POST"
    },
  ]
}

resource "aws_lambda_function" "play" {
  for_each         = { for l in local.play_lambdas : l.name => l }
  function_name    = "${var.app_name}-play-${each.value.name}"
  description      = each.value.description
  filename         = "./templates/lambda_stub.zip"
  source_code_hash = filebase64sha256("./templates/lambda_stub.zip")
  handler          = "handler.handler"
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
  runtime          = var.lambda_runtime
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout
  role             = aws_iam_role.lambda_role.arn

  environment {
    variables = local.lambda_variables
  }

  tracing_config {
    mode = var.lambda_trace_mode
  }

  tags = merge(local.standard_tags, tomap({
    "name"        = "${var.app_name}-play-${each.value.name}",
    "lambda_type" = "play"
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
