# Optional storefront. Set enable_frontend = true only if CloudFront is allowed in your lab.
resource "aws_s3_bucket" "web" {
  count         = var.enable_frontend ? 1 : 0
  bucket        = "${local.name_prefix}-web-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "web" {
  count                   = var.enable_frontend ? 1 : 0
  bucket                  = aws_s3_bucket.web[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "web" {
  count                             = var.enable_frontend ? 1 : 0
  name                              = "${local.name_prefix}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  cloudfront_cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
}

resource "aws_cloudfront_distribution" "web" {
  count               = var.enable_frontend ? 1 : 0
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.web[0].bucket_regional_domain_name
    origin_id                = "s3-web"
    origin_access_control_id = aws_cloudfront_origin_access_control.web[0].id
  }

  default_cache_behavior {
    target_origin_id       = "s3-web"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.cloudfront_cache_policy_id
    compress               = true
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate { cloudfront_default_certificate = true }
}

data "aws_iam_policy_document" "web" {
  count = var.enable_frontend ? 1 : 0

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.web[0].arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.web[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "web" {
  count      = var.enable_frontend ? 1 : 0
  bucket     = aws_s3_bucket.web[0].id
  policy     = data.aws_iam_policy_document.web[0].json
  depends_on = [aws_s3_bucket_public_access_block.web]
}

resource "aws_s3_object" "index" {
  count        = var.enable_frontend ? 1 : 0
  bucket       = aws_s3_bucket.web[0].id
  key          = "index.html"
  source       = "${path.module}/web/index.html"
  etag         = filemd5("${path.module}/web/index.html")
  content_type = "text/html"
}

resource "aws_s3_object" "config" {
  count        = var.enable_frontend ? 1 : 0
  bucket       = aws_s3_bucket.web[0].id
  key          = "config.json"
  content_type = "application/json"
  content = jsonencode({
    region     = var.aws_region
    apiUrl     = aws_api_gateway_stage.this.invoke_url
    userPoolId = aws_cognito_user_pool.this.id
    clientId   = aws_cognito_user_pool_client.web.id
  })
}
