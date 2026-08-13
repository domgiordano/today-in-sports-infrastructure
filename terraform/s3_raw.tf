#**********************
# RAW ARCHIVE
#
# Untouched upstream payloads, written at ingestion time before any parsing.
#
# This exists because the corpus is a one-time extraction of immutable data.
# Historical results never change, so once a source has been ingested and its
# payload archived here, that source can disappear without affecting the
# product. Two of the candidate sources already died once — Ergast shut down at
# the end of 2024 and the NHL retired its old statsapi host — which is the
# reason this bucket is mandatory rather than nice to have.
#
# Layout: s3://<bucket>/<source>/<yyyy>/<yyyy-mm-dd>.json
#**********************

resource "aws_s3_bucket" "raw_archive" {
  bucket = "${var.app_name}-raw-archive-${local.web_app_account_id}"
  tags   = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-raw-archive" }))
}

resource "aws_s3_bucket_public_access_block" "raw_archive" {
  bucket                  = aws_s3_bucket.raw_archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "raw_archive" {
  bucket = aws_s3_bucket.raw_archive.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_archive" {
  bucket = aws_s3_bucket.raw_archive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Raw payloads are read constantly during a backfill, then almost never again.
# They must never expire — this archive is the source of record.
resource "aws_s3_bucket_lifecycle_configuration" "raw_archive" {
  bucket = aws_s3_bucket.raw_archive.id

  rule {
    id     = "transition-cold"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER_IR"
    }
  }
}
