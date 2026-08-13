locals {
  domain_name     = var.domain_name
  api_domain_name = "api.${local.domain_name}"

  web_app_account_id = data.aws_caller_identity.web_app_account.account_id

  standard_tags = {
    "source"      = "terraform"
    "app_name"    = var.app_name
    "environment" = var.environment
    "owner"       = var.owner
  }

  lambda_variables = {
    APP_NAME           = var.app_name
    DYNAMODB_KMS_ALIAS = aws_kms_alias.dynamodb.name

    # Raw ingested game rows, one per source game. Kept separate from EVENTS so
    # detectors can be re-run without re-hitting any upstream source.
    GAMES_TABLE_NAME = aws_dynamodb_table.games.id

    # Detected notable events, partitioned by calendar date (MM-DD).
    EVENTS_TABLE_NAME       = aws_dynamodb_table.events.id
    EVENTS_SPORT_INDEX      = "sport-year-index"
    EVENTS_NOTABILITY_INDEX = "sport-notability-index"

    QUESTIONS_TABLE_NAME   = aws_dynamodb_table.questions.id
    QUESTIONS_STATUS_INDEX = "status-mmdd-index"
    QUESTIONS_BANK_INDEX   = "status-sportTier-index"

    QUIZZES_TABLE_NAME   = aws_dynamodb_table.quizzes.id
    QUIZZES_STATUS_INDEX = "status-quizDate-index"

    SOURCE_RUNS_TABLE_NAME = aws_dynamodb_table.source_runs.id
    PLAYS_TABLE_NAME       = aws_dynamodb_table.plays.id
    REQUEST_LOG_TABLE_NAME = aws_dynamodb_table.request_log.id
    USERS_TABLE_NAME       = aws_dynamodb_table.users.id
    GROUPS_TABLE_NAME      = aws_dynamodb_table.groups.id

    # Untouched upstream payloads. Once ingestion completes this archive, not
    # the upstream API, is the source of record — see the durability rule in
    # docs/features/today-in-sports/PLAN.md.
    RAW_ARCHIVE_BUCKET = aws_s3_bucket.raw_archive.id

    COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
    COGNITO_JWKS_URL     = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
    ADMIN_EMAIL          = var.admin_email
    AWS_ACCOUNT_ID       = data.aws_caller_identity.web_app_account.account_id
  }

  api_allow_headers = [
    "Authorization",
    "Content-Type",
    "X-Amz-Date",
    "X-Amz-Security-Token",
    "X-Api-Key",
    "Origin",
    "Accept",
    "Access-Control-Allow-Origin",
    "Accept-Language"
  ]
}
