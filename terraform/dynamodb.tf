#**********************
# GAMES — the ETL landing zone
#
# Every ingested game from every source, untouched by notability rules.
# Deliberately separate from EVENTS: re-running or adding a detector must never
# require re-hitting an upstream source. Several of those sources are free
# community endpoints and two have already been shut down once (Ergast, and the
# NHL's old statsapi host), so ingestion is treated as a one-time extraction of
# immutable history.
#
# gameDate is the source's OFFICIAL local game date, never the queried date —
# an MLB night game at 23:05Z on Oct 10 has an officialDate of Oct 11 and is
# returned under both. See docs/features/today-in-sports/SPIKE-FINDINGS.md.
#**********************

resource "aws_dynamodb_table" "games" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-games"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "sportSeason"
  range_key                   = "gameDateId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  # "mlb#1991"
  attribute {
    name = "sportSeason"
    type = "S"
  }

  # "1991-05-01#201097"
  attribute {
    name = "gameDateId"
    type = "S"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-games" }))
}

#**********************
# EVENTS — notable moments, derived from GAMES by rule
#
# Partitioned on the calendar date (MM-DD) because every read is "what happened
# on this day", across all years at once.
#**********************

resource "aws_dynamodb_table" "events" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-events"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "mmdd"
  range_key                   = "yearEventId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  # "08-13"
  attribute {
    name = "mmdd"
    type = "S"
  }

  # "1991#201097"
  attribute {
    name = "yearEventId"
    type = "S"
  }

  attribute {
    name = "sport"
    type = "S"
  }

  attribute {
    name = "year"
    type = "N"
  }

  attribute {
    name = "notabilityScore"
    type = "N"
  }

  global_secondary_index {
    name            = "sport-year-index"
    hash_key        = "sport"
    range_key       = "year"
    projection_type = "ALL"
  }

  # Used by the assembler to pick the most notable event for a thin date.
  global_secondary_index {
    name            = "sport-notability-index"
    hash_key        = "sport"
    range_key       = "notabilityScore"
    projection_type = "ALL"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-events" }))
}

#**********************
# QUESTIONS — the reviewable bank
#**********************

resource "aws_dynamodb_table" "questions" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-questions"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "questionId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "questionId"
    type = "S"
  }

  # draft | approved | rejected | used
  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "mmdd"
    type = "S"
  }

  # "mlb#3" — sport and tier, so the assembler can pull a specific
  # sport-and-difficulty slot straight out of the approved bank.
  attribute {
    name = "sportTier"
    type = "S"
  }

  global_secondary_index {
    name            = "status-mmdd-index"
    hash_key        = "status"
    range_key       = "mmdd"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "status-sportTier-index"
    hash_key        = "status"
    range_key       = "sportTier"
    projection_type = "ALL"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-questions" }))
}

#**********************
# QUIZZES — the assembled daily five
#
# quizDate is a UTC yyyy-mm-dd. Note this is a different thing from an event's
# gameDate, which is the local date the game was actually played.
#**********************

resource "aws_dynamodb_table" "quizzes" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-quizzes"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "quizDate"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "quizDate"
    type = "S"
  }

  # draft | scheduled | published
  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "status-quizDate-index"
    hash_key        = "status"
    range_key       = "quizDate"
    projection_type = "ALL"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-quizzes" }))
}

#**********************
# SOURCE RUNS — ingestion and detector run log
#
# Ingestion is throttled and resumable; this is where the checkpoint lives so a
# multi-decade run can be stopped and restarted without re-fetching.
#**********************

resource "aws_dynamodb_table" "source_runs" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-source-runs"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "runId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "runId"
    type = "S"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-source-runs" }))
}

#**********************
# PLAYS — one session per identity per quiz date
#
# Holds server-stamped serve times and graded answers. The client never posts a
# score; it posts a choice, and everything that decides points is computed
# server-side from this row.
#
# Sessions are transient, unlike everything else here, so they carry a TTL
# rather than accumulating forever.
#**********************

resource "aws_dynamodb_table" "plays" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-plays"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "playId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # "<cognito-sub-or-device-id>#2026-08-13"
  attribute {
    name = "playId"
    type = "S"
  }

  attribute {
    name = "quizDate"
    type = "S"
  }

  attribute {
    name = "totalPoints"
    type = "N"
  }

  # Daily leaderboard reads: one partition per day, sorted by score. Sharding
  # comes with the leaderboard itself; this serves the top-N query.
  global_secondary_index {
    name            = "quizDate-totalPoints-index"
    hash_key        = "quizDate"
    range_key       = "totalPoints"
    projection_type = "ALL"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-plays" }))
}

#**********************
# Request / error log
#**********************

# Written by the error-handling hook on every request, best-effort and silent
# on failure. Partitioned by outcome rather than by path so the errors panel is
# a query rather than a scan over every successful request ever served.
#
# Rows expire on their own: successes after a fortnight, failures after ninety
# days, because a 500 is looked up long after it happened and a 200 is not.
resource "aws_dynamodb_table" "request_log" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-request-log"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "bucket"
  range_key                   = "loggedAt"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  # Deliberately off. This table is disposable instrumentation with a TTL, and
  # continuous backups of it would cost more than the data is worth.
  point_in_time_recovery {
    enabled = false
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  # ok | rejected | error | last-seen
  attribute {
    name = "bucket"
    type = "S"
  }

  attribute {
    name = "loggedAt"
    type = "S"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-request-log" }))
}

#**********************
# People and groups
#**********************

# The spine of everything social. Cognito holds credentials and nothing else,
# so streaks, badges, group membership and play counts need somewhere of their
# own to live.
#
# Written lazily on the first authenticated request rather than by a Cognito
# post-confirmation trigger: a trigger is a second deploy target and a failure
# mode where sign-up succeeds and the profile silently does not.
resource "aws_dynamodb_table" "users" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-users"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "userId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "userId"
    type = "S"
  }

  # Streak leaderboards, and the admin users panel sorted by activity.
  attribute {
    name = "lastPlayedDate"
    type = "S"
  }

  global_secondary_index {
    name            = "activity-index"
    hash_key        = "lastPlayedDate"
    projection_type = "ALL"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-users" }))
}

# Friend groups. Joining is by invite code, never by a searchable directory: a
# public list of small private groups is a harassment surface with no upside
# for a trivia game.
resource "aws_dynamodb_table" "groups" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-groups"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "groupId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "groupId"
    type = "S"
  }

  attribute {
    name = "inviteCode"
    type = "S"
  }

  global_secondary_index {
    name            = "invite-index"
    hash_key        = "inviteCode"
    projection_type = "ALL"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-groups" }))
}

#**********************
# Announcements
#**********************

# Rows carry a hard end date and clean themselves up a month after it passes.
# An announcement without an end runs forever once you forget about it, and a
# stale banner teaches people to ignore the channel.
resource "aws_dynamodb_table" "announcements" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-announcements"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "announcementId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = false
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  attribute {
    name = "announcementId"
    type = "S"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-announcements" }))
}

#**********************
# Precomputed statistics
#**********************

# Written nightly, read by key. Computing these per request means scanning the
# plays table on every page load - fine at ten players, and a silent failure at
# ten thousand. Keyed scope/period so any slice is one GetItem.
resource "aws_dynamodb_table" "stats" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-stats"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "scope"
  range_key                   = "period"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  # Derived data. It can be rebuilt from the plays table by rerunning the job,
  # so continuous backups would be paying to protect a cache.
  point_in_time_recovery {
    enabled = false
  }

  attribute {
    name = "scope"
    type = "S"
  }

  attribute {
    name = "period"
    type = "S"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-stats" }))
}

#**********************
# Reactions
#**********************

# An emoji left on somebody's round.
#
# Keyed by the round it is about (`playId`, which is already
# "<identity>#<quiz-date>") and by who left it, so one person can react once to
# a given round. Reacting again replaces rather than stacks — the alternative
# is a row that says nothing except that somebody tapped a lot.
#
# The day index exists because a leaderboard needs every reaction for a date at
# once. Without it a fifty-row board is fifty queries; with it, one.
#
# Rows expire with the round they are about. A reaction to a quiz nobody can
# still see is not worth storing, and it means this table needs no cleanup of
# its own.
resource "aws_dynamodb_table" "reactions" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-reactions"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "playId"
  range_key                   = "reactorId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  attribute {
    name = "playId"
    type = "S"
  }

  attribute {
    name = "reactorId"
    type = "S"
  }

  attribute {
    name = "quizDate"
    type = "S"
  }

  global_secondary_index {
    name            = "day-index"
    hash_key        = "quizDate"
    range_key       = "playId"
    projection_type = "ALL"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-reactions" }))
}

#**********************
# Usernames
#**********************

# A claimed @handle.
#
# Its own table rather than a sentinel row in `users`, because that table is
# scanned to build the admin user list and reservation rows would show up there
# as people who do not exist.
#
# The key is the handle folded to lower case, which is what makes it unique:
# "Dom" and "dom" are the same claim, and a conditional write on
# attribute_not_exists is what settles a race between two people reaching for
# the same one. Uniqueness cannot be had from a GSI — an index will happily
# hold two identical values.
#
# No TTL. A handle is released when its owner changes or deletes it, never by
# expiry: a name that lapses on a timer would be reassigned to somebody else
# while the original owner's scores still carry it.
resource "aws_dynamodb_table" "usernames" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-usernames"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "username"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "username"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  # So a user's current handle can be found without storing it in two places
  # and hoping they agree.
  global_secondary_index {
    name            = "owner-index"
    hash_key        = "userId"
    projection_type = "ALL"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-usernames" }))
}

#**********************
# Comments
#**********************

# What a group says about a day's results.
#
# One thread per group per day — `<groupId>#<quiz-date>` — because that is the
# unit people actually talk about. A single endless thread per group would bury
# today's argument under last month's, and a thread per player would fragment
# four people into four conversations.
#
# The sort key is the creation timestamp with the comment id appended, so a
# query returns a day in order and two comments posted in the same millisecond
# still have a stable position rather than a race.
#
# Rows expire on the same 90-day clock as the rounds they discuss. A comment
# about a quiz nobody can still reach has nothing left to point at.
resource "aws_dynamodb_table" "comments" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-comments"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "threadId"
  range_key                   = "postedAtId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  attribute {
    name = "threadId"
    type = "S"
  }

  attribute {
    name = "postedAtId"
    type = "S"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-comments" }))
}

#**********************
# Notifications
#**********************

# Something that happened which is worth telling one person about.
#
# Keyed by the person told, sorted newest first, because that is the only way
# this is ever read: "what have I missed". There is no query for "everything
# about a group" — that is what the group page is.
#
# Rows expire on the same 90-day clock as the things they point at. A
# notification about a comment on a quiz that has aged out has nothing left to
# open, and expiring them is what stops this table growing without bound for a
# player who never opens the list.
resource "aws_dynamodb_table" "notifications" {
  deletion_protection_enabled = true
  name                        = "${var.app_name}-notifications"
  billing_mode                = "PAY_PER_REQUEST"
  read_capacity               = 0
  write_capacity              = 0
  hash_key                    = "userId"
  range_key                   = "createdAtId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "createdAtId"
    type = "S"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-notifications" }))
}
