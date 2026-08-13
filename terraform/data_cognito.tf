# Shared Cognito SSM data sources
#
# These read the SSM parameters exported by xomware-infrastructure (the shared
# pool owner -- see cognito_ssm.tf there). Today-in-Sports consumes the shared
# xomware_users User Pool rather than owning its own identity surface.
# Do NOT provision a new pool here.
#
# Pattern matches xomtracks-infrastructure/terraform/data_cognito.tf and
# xomforms-infrastructure/terraform/data_cognito.tf exactly.

data "aws_ssm_parameter" "cognito_user_pool_arn" {
  name = "/xomware/shared/cognito/user-pool-arn"
}

data "aws_ssm_parameter" "cognito_user_pool_id" {
  name = "/xomware/shared/cognito/user-pool-id"
}

data "aws_ssm_parameter" "cognito_user_pool_jwks_url" {
  name = "/xomware/shared/cognito/user-pool-jwks-url"
}

data "aws_ssm_parameter" "cognito_hosted_ui_domain" {
  name = "/xomware/shared/cognito/hosted-ui-domain"
}

# App client -- lives with the pool owner (xomware-infrastructure), matching
# xomware_com / xomappetit / xomforms / xomtracks. See that repo's cognito.tf
# aws_cognito_user_pool_client.today_in_sports and its SSM export in
# cognito_ssm.tf.
#
# NOTE: this data source cannot resolve until the xomware-infrastructure change
# adding the client is applied. Do not run plan/apply here until that parameter
# exists in SSM.
data "aws_ssm_parameter" "cognito_client_today_in_sports_id" {
  name = "/xomware/shared/cognito/clients/today-in-sports-id"
}
