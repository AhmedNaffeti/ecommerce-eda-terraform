locals {
  # One queue per consuming service; the name matches the Lambda key in lambda.tf
  queues = toset(["warehouse", "payment", "orders"])
}

resource "aws_sqs_queue" "dlq" {
  for_each = local.queues

  name                      = "${local.name_prefix}-${each.key}-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "main" {
  for_each = local.queues

  name                       = "${local.name_prefix}-${each.key}"
  visibility_timeout_seconds = var.lambda_timeout_s * 6 # AWS recommends >= 6x function timeout
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = 3
  })
}
