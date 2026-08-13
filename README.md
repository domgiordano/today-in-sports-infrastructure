# today-in-sports-infrastructure

Terraform for **Today in Sports** — a daily five-question sports history quiz
anchored to the calendar date.

Plan: `~/Code/docs/features/today-in-sports/PLAN.md`
Research: `~/Code/docs/features/today-in-sports/SPIKE-FINDINGS.md`

## Scope

Phase 1 provisions the **content pipeline and admin portal only**. There is no
play surface, no leaderboards and no public routes yet — every API route is
behind the admin gate.

## Layout

| File | Contents |
|---|---|
| `main.tf` | Provider pins and the S3 backend (`xomware-terraform-state`, key `today-in-sports/`) |
| `variables.tf` | App name, domain, Lambda and CloudFront tunables |
| `locals.tf` | Standard tags, and the `lambda_variables` map injected into every function |
| `kms.tf` | CMKs for DynamoDB and the web-app S3 bucket |
| `dynamodb.tf` | Five tables — games, events, questions, quizzes, source-runs |
| `s3_raw.tf` | The raw upstream-payload archive |
| `data_cognito.tf` | SSM reads for the **shared** `xomware_users` pool |
| `iam_lambda.tf` | Lambda execution role and policy |
| `lambda_layers.tf` | Shared `lambdas/common/` layer |
| `lambdas_admin.tf` | Eight admin functions plus the authorizer |
| `apigateway.tf` | `api-gateway-service` module wiring |
| `acm_api.tf` / `route53.tf` | API certificate and DNS |
| `s3_cloudfront.tf` | Admin portal hosting |

## Two things to know before applying

**1. There is a cross-repo dependency.** `data_cognito.tf` reads
`/xomware/shared/cognito/clients/today-in-sports-id`. That parameter does not
exist yet — `xomware-infrastructure` must first add
`aws_cognito_user_pool_client.today_in_sports` and its SSM export, and be
applied. `terraform plan` here will fail until it does. This mirrors the
dependency xomtracks hit.

**2. The raw archive is the source of record, not the upstream APIs.** The
corpus is a one-time extraction of immutable data — historical results never
change. Once ingested and archived to `s3://today-in-sports-raw-archive-*`,
every upstream source can disappear without affecting the product. This is not
hypothetical: Ergast shut down at the end of 2024 and the NHL retired its old
`statsapi` host. Ingestion writes the untouched payload to S3 *before* parsing,
and Lambdas hold read-only access to that bucket so nothing in the request path
can mutate it.

## Data model notes

`games` is deliberately separate from `events`. Detectors derive notable moments
from raw game rows by rule, so adding or fixing a detector must never require
re-hitting a source.

`gameDate` on a game is the source's **official local game date**, never the
date used to query it. An MLB night game at 23:05Z on 10 October has an
`officialDate` of 11 October and is returned under both — keying on the query
date silently misfiles a large share of evening games onto the previous day,
which for a "what happened on this date" product is fatal.

`quizDate` on a quiz is a **UTC** `yyyy-mm-dd` and is a different concept. The
daily rollover is midnight UTC; the game date is local. Do not conflate them.

## Usage

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

CI runs `fmt`, `validate` and `plan` on pull requests and applies on merge to
`master` — see `.github/workflows/terraform.yml`.
