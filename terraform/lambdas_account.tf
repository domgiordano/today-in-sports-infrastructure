locals {
  # Signed-in but not admin. A third category, because /me is neither public
  # (it is the caller's own record) nor admin-gated (every player has one).
  #
  # The gateway verifies the JWT and hands the claims through; there is no
  # in-handler email check, because being yourself is the only permission
  # needed to read your own profile.
  account_lambdas = [
    {
      name        = "me"
      description = "The signed-in player's own profile, streak and badges"
      path_part   = "me"
      http_method = "GET"
    },
    {
      name        = "profile"
      description = "Update your own display name or self-declared region"
      path_part   = "profile"
      http_method = "POST"
    },
    {
      name        = "groups"
      description = "The groups this player belongs to"
      path_part   = "groups"
      http_method = "GET"
    },
    {
      name        = "groups-action"
      description = "Create, join, leave or re-code a group"
      path_part   = "groups-action"
      http_method = "POST"
    },
    {
      name        = "comments"
      description = "What a group said about a day's results"
      path_part   = "comments"
      http_method = "GET"
    },
    {
      name        = "notifications"
      description = "What this player has missed"
      path_part   = "notifications"
      http_method = "GET"
    },
    {
      name        = "notifications-action"
      description = "Mark notifications read"
      path_part   = "notifications-action"
      http_method = "POST"
    },
    {
      name        = "friends"
      description = "This player's friends, their board, and pending requests"
      path_part   = "friends"
      http_method = "GET"
    },
    {
      name        = "friends-action"
      description = "Add, accept, decline, withdraw or unfriend"
      path_part   = "friends-action"
      http_method = "POST"
    },
    {
      name        = "history"
      description = "This player's own recent rounds and accuracy by sport"
      path_part   = "history"
      http_method = "GET"
    },
    {
      name        = "comments-action"
      description = "Post or delete a comment on a group's day"
      path_part   = "comments-action"
      http_method = "POST"
    },
  ]
}

resource "aws_lambda_function" "account" {
  for_each         = { for l in local.account_lambdas : l.name => l }
  function_name    = "${var.app_name}-account-${each.value.name}"
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
    "name"        = "${var.app_name}-account-${each.value.name}",
    "lambda_type" = "account"
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
