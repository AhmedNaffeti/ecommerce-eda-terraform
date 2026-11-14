resource "aws_cloudwatch_event_bus" "this" {
  name = "${local.name_prefix}-bus"
}

# Allows replaying business events after a bug fix
resource "aws_cloudwatch_event_archive" "this" {
  name             = "${local.name_prefix}-archive"
  event_source_arn = aws_cloudwatch_event_bus.this.arn
  retention_days   = 7
}

locals {
  # Business-event routing table: event -> destination queue
  event_routes = {
    order_created     = { source = "ecommerce.orders", detail_type = "OrderCreated", queue = "warehouse" }
    stock_reserved    = { source = "ecommerce.warehouse", detail_type = "StockReserved", queue = "payment" }
    stock_rejected    = { source = "ecommerce.warehouse", detail_type = "StockRejected", queue = "orders" }
    payment_succeeded = { source = "ecommerce.payment", detail_type = "PaymentSucceeded", queue = "orders" }
    payment_failed    = { source = "ecommerce.payment", detail_type = "PaymentFailed", queue = "orders" }
  }
}

resource "aws_cloudwatch_event_rule" "route" {
  for_each = local.event_routes

  name           = "${local.name_prefix}-${replace(each.key, "_", "-")}"
  event_bus_name = aws_cloudwatch_event_bus.this.name

  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = [each.value.detail_type]
  })
}

resource "aws_cloudwatch_event_target" "queue" {
  for_each = local.event_routes

  rule           = aws_cloudwatch_event_rule.route[each.key].name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = each.key
  arn            = aws_sqs_queue.main[each.value.queue].arn
}

data "aws_iam_policy_document" "queue" {
  for_each = local.queues

  statement {
    sid       = "AllowEventBridge"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.main[each.key].arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for k, r in local.event_routes : aws_cloudwatch_event_rule.route[k].arn if r.queue == each.key]
    }
  }
}

resource "aws_sqs_queue_policy" "main" {
  for_each = local.queues

  queue_url = aws_sqs_queue.main[each.key].id
  policy    = data.aws_iam_policy_document.queue[each.key].json
}
