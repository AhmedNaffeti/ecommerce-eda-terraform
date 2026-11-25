# Learner Lab: creating IAM roles/policies is forbidden, so every Lambda uses the pre-existing LabRole.
data "aws_iam_role" "lab" {
  name = "LabRole"
}

locals {
  common_env = {
    PRODUCTS_TABLE       = aws_dynamodb_table.products.name
    ORDERS_TABLE         = aws_dynamodb_table.orders.name
    INVENTORY_TABLE      = aws_dynamodb_table.inventory.name
    PAYMENTS_TABLE       = aws_dynamodb_table.payments.name
    EVENT_BUS_NAME       = aws_cloudwatch_event_bus.this.name
    SNS_TOPIC_ARN        = aws_sns_topic.orders.arn
    PAYMENT_FAILURE_RATE = tostring(var.payment_failure_rate)
  }

  services = toset(["products", "orders", "warehouse", "payment"])
}

# Package each service together with the shared helper module
data "archive_file" "lambda" {
  for_each    = local.services
  type        = "zip"
  output_path = "${path.module}/build/${each.key}.zip"

  source {
    content  = file("${path.module}/lambda_src/${each.key}/handler.py")
    filename = "handler.py"
  }
  source {
    content  = file("${path.module}/lambda_src/common/common.py")
    filename = "common.py"
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = local.services
  name              = "/aws/lambda/${local.name_prefix}-${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "svc" {
  for_each = local.services

  function_name    = "${local.name_prefix}-${each.key}"
  role             = data.aws_iam_role.lab.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  filename         = data.archive_file.lambda[each.key].output_path
  source_code_hash = data.archive_file.lambda[each.key].output_base64sha256
  timeout          = var.lambda_timeout_s
  memory_size      = var.lambda_memory_mb

  dynamic "tracing_config" {
    for_each = var.enable_xray ? [1] : []
    content {
      mode = "Active"
    }
  }

  environment { variables = local.common_env }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# SQS -> Lambda triggers (warehouse, payment, orders)
resource "aws_lambda_event_source_mapping" "sqs" {
  for_each = local.queues

  event_source_arn        = aws_sqs_queue.main[each.key].arn
  function_name           = aws_lambda_function.svc[each.key].arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config { maximum_concurrency = 10 }
}
