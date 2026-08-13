locals {
  # Phase 1 ships admin routes only — there is no play surface yet, so every
  # route here is behind the admin gate. `authorization` is NONE at the gateway
  # and the Bearer token is validated in-handler, matching xomtracks/xomify.
  admin_lambdas = [
    {
      name        = "questions-list"
      description = "Admin-only: browse the question bank, filtered by status/sport/tier/date"
      path_part   = "questions"
      http_method = "GET"
    },
    {
      name        = "questions-review"
      description = "Admin-only: approve, reject with reason, or edit a question"
      path_part   = "questions-review"
      http_method = "POST"
    },
    {
      name        = "questions-regenerate"
      description = "Admin-only: re-queue a question's source event for regeneration"
      path_part   = "questions-regenerate"
      http_method = "POST"
    },
    {
      name        = "bank-coverage"
      description = "Admin-only: approved-unused question counts per calendar date"
      path_part   = "bank-coverage"
      http_method = "GET"
    },
    {
      name        = "quizzes-list"
      description = "Admin-only: scheduled quizzes for the next N days"
      path_part   = "quizzes"
      http_method = "GET"
    },
    {
      name        = "quizzes-assemble"
      description = "Admin-only: propose quizzes from the approved bank"
      path_part   = "quizzes-assemble"
      http_method = "POST"
    },
    {
      name        = "quizzes-update"
      description = "Admin-only: swap a question or publish a quiz"
      path_part   = "quizzes-update"
      http_method = "PATCH"
    },
    {
      name        = "events-list"
      description = "Admin-only: browse detected events and the needs-review queue"
      path_part   = "events"
      http_method = "GET"
    },
  ]
}

resource "aws_lambda_function" "admin" {
  for_each         = { for lambda in local.admin_lambdas : lambda.name => lambda }
  function_name    = "${var.app_name}-admin-${each.value.name}"
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
    "name"        = "${var.app_name}-admin-${each.value.name}",
    "lambda_type" = "admin"
  }))

  # CI (deploy-backend.yml) owns the code; Terraform owns the resource. Without
  # this every apply would revert the deployed zip back to the stub.
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

#**********************
# Authorizer
#**********************

resource "aws_lambda_function" "authorizer" {
  function_name    = "${var.app_name}-authorizer"
  description      = "Validates the caller's JWT against this app's own Cognito pool"
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

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-authorizer" }))

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
