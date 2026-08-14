# ============================================
# Email — the sending identity for this app.
#
# The account already has SES production access, so there is no sandbox to
# escape and no recipient to pre-verify. What is missing is a sender that
# belongs to this game: mail about tomorrow's questions arriving from
# noreply@xomware.com would be a different product writing to you.
#
# Everything here is DNS in a zone Terraform already reads, so verification
# completes on apply rather than waiting on anybody to paste records anywhere.
# ============================================

resource "aws_ses_domain_identity" "main" {
  domain = local.domain_name
}

# DKIM signs the mail so a receiver can tell it really came from this domain.
# Three CNAMEs, published for us, because a sending domain that fails DKIM is a
# sending domain that lands in spam.
resource "aws_ses_domain_dkim" "main" {
  domain = aws_ses_domain_identity.main.domain
}

resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${aws_ses_domain_dkim.main.dkim_tokens[count.index]}._domainkey.${local.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.main.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# A custom MAIL FROM, so the envelope sender is this domain rather than
# amazonses.com. Without it SPF aligns to Amazon's domain and not to ours,
# which is the difference DMARC checks for.
#
# On a subdomain deliberately: it needs its own MX, and putting one on the root
# would claim this domain receives mail here, which it does not.
resource "aws_ses_domain_mail_from" "main" {
  domain           = aws_ses_domain_identity.main.domain
  mail_from_domain = "mail.${local.domain_name}"
}

resource "aws_route53_record" "ses_mail_from_mx" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = aws_ses_domain_mail_from.main.mail_from_domain
  type    = "MX"
  ttl     = 600
  records = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

resource "aws_route53_record" "ses_mail_from_spf" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = aws_ses_domain_mail_from.main.mail_from_domain
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com -all"]
}

# DMARC on p=none: this reports where mail claiming to be from this domain is
# coming from, without asking anybody to reject it yet. Tightening to quarantine
# is a decision to make once the reports show only our own sending.
resource "aws_route53_record" "dmarc" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "_dmarc.${local.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = ["v=DMARC1; p=none; rua=mailto:${var.admin_email}"]
}

# Blocks the apply until AWS confirms the domain, so a later resource cannot be
# built against an identity that is not actually verified yet.
resource "aws_ses_domain_identity_verification" "main" {
  domain     = aws_ses_domain_identity.main.id
  depends_on = [aws_route53_record.ses_dkim]
}

output "ses_sender" {
  description = "The From address the daily mail should use."
  value       = "noreply@${local.domain_name}"
}

output "ses_domain_identity_arn" {
  value = aws_ses_domain_identity.main.arn
}
