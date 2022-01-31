terraform {
  backend "s3" {
    bucket         = "teak-terraform-state"
    key            = "docs"
    region         = "us-east-1"
    dynamodb_table = "teak-terraform-locks"
    encrypt        = true
    kms_key_id     = "a285ccc4-035b-4436-834f-7e0b2d5b0f60"
  }

  required_version = ">= 0.15.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.73"
    }
  }
}

locals {
  service = "Docs"

  default_tags = {
    Managed     = "terraform"
    Environment = terraform.workspace
    CostCenter  = local.service
    Application = local.service
    Service     = local.service
  }

  account_names = {
    development = "workload-dev-0001",
    production  = "workload-prod"
  }

  account_name = local.account_names[terraform.workspace]

  parameter_prefix = "/${var.organization_prefix}/${terraform.workspace}/${local.account_name}"
}

provider "aws" {
  region = var.region
  alias  = "admin"

  default_tags {
    tags = local.default_tags
  }
}

data "aws_caller_identity" "admin" {
  provider = aws.admin
}

data "aws_ssm_parameter" "role_arn" {
  provider = aws.admin

  name = "${local.parameter_prefix}/roles/admin"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.default_tags
  }

  assume_role {
    role_arn = data.aws_ssm_parameter.role_arn.value
  }
}

data "aws_caller_identity" "current" {}

data "aws_route53_zone" "zone" {
  name = var.domain_root
}

data "aws_acm_certificate" "certificate" {
  domain      = var.domain_root
  statuses    = ["ISSUED"]
  most_recent = true
}

resource "aws_s3_bucket" "docs-bucket" {
  bucket_prefix = "teak-docs-${terraform.workspace}-"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  force_destroy = terraform.workspace == "development"
}

resource "aws_s3_bucket_public_access_block" "docs-bucket" {
  bucket = aws_s3_bucket.docs-bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object" "robots-deny" {
  count = terraform.workspace == "development" ? 1 : 0

  bucket       = aws_s3_bucket.docs-bucket.id
  key          = "robots.txt"
  source       = "${path.module}/deny_all_robots.txt"
  source_hash  = filemd5("${path.module}/deny_all_robots.txt")
  content_type = "text/plain"
}

resource "aws_cloudfront_origin_access_identity" "cloudfront-oai" {
  comment = "OAI for docs bucket access."
}

data "aws_iam_policy_document" "allow-cloudfront-access" {
  statement {
    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.cloudfront-oai.iam_arn]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.docs-bucket.arn}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "docs-bucket" {
  bucket = aws_s3_bucket.docs-bucket.id
  policy = data.aws_iam_policy_document.allow-cloudfront-access.json

  depends_on = [
    aws_s3_bucket_public_access_block.docs-bucket
  ]
}


locals {
  s3_origin_id = "docs-s3-origin"
}

resource "aws_cloudfront_distribution" "docs" {
  origin {
    domain_name = aws_s3_bucket.docs-bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.cloudfront-oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Docs Hosting"
  default_root_object = "index.html"

  aliases = ["${var.subdomain}.${var.domain_root}"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    compress = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  custom_error_response {
    error_caching_min_ttl = 0

    # 403 is what S3 gives us when trying to access a path that does not exist.
    error_code         = 403
    response_code      = 404
    response_page_path = "/404.html"
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.certificate.arn
    ssl_support_method  = "sni-only"

    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

data "aws_iam_policy_document" "docs-deploy" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.docs-bucket.arn,
      "${aws_s3_bucket.docs-bucket.arn}/*"
    ]
  }

  statement {
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation"
    ]

    resources = [
      aws_cloudfront_distribution.docs.arn
    ]
  }
}

resource "aws_iam_policy" "docs-deploy" {
  name        = "DocsDeploy"
  description = "Allows deploying docs to the S3 bucket and invalidating the Cloudfront distribution."

  policy = data.aws_iam_policy_document.docs-deploy.json
}

data "aws_iam_policy_document" "allow-meta-account-assume" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.admin.id}:root", ]
    }
  }
}

resource "aws_iam_role" "docs-deploy" {
  name = "DocsDeploy"
  path = "/${var.organization_prefix}/ci-service-role/"

  description = "Role for CI to assume to manage doc deployments"

  assume_role_policy = data.aws_iam_policy_document.allow-meta-account-assume.json
}

resource "aws_iam_role_policy_attachment" "docs-deploy" {
  role       = aws_iam_role.docs-deploy.name
  policy_arn = aws_iam_policy.docs-deploy.arn
}

resource "aws_route53_record" "docs" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.subdomain
  type    = "A"

  alias {
    name    = aws_cloudfront_distribution.docs.domain_name
    zone_id = aws_cloudfront_distribution.docs.hosted_zone_id

    evaluate_target_health = false
  }
}
