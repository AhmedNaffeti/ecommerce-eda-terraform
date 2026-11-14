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

  sqs_consume = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]

  # Least-privilege permissions per microservice
  services = {
    products = {
      statements = [
        { actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Scan"], resources = [aws_dynamodb_table.products.arn] },
        { actions = ["dynamodb:PutItem"], resources = [aws_dynamodb_table.inventory.arn] },
      ]
    }
    orders = {
      statements = [
        { actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"], resources = [aws_dynamodb_table.orders.arn, "${aws_dynamodb_table.orders.arn}/index/*"] },
        { actions = ["dynamodb:GetItem"], resources = [aws_dynamodb_table.products.arn] },
        { actions = ["events:PutEvents"], resources = [aws_cloudwatch_event_bus.this.arn] },
        { actions = ["sns:Publish"], resources = [aws_sns_topic.orders.arn] },
        { actions = local.sqs_consume, resources = [aws_sqs_queue.main["orders"].arn] },
      ]
    }
    warehouse = {
      statements = [
        { actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"], resources = [aws_dynamodb_table.inventory.arn] },
        { actions = ["events:PutEvents"], resources = [aws_cloudwatch_event_bus.this.arn] },
        { actions = local.sqs_consume, resources = [aws_sqs_queue.main["warehouse"].arn] },
      ]
    }
    payment = {
      statements = [
        { actions = ["dynamodb:GetItem", "dynamodb:PutItem"], resources = [aws_dynamodb_table.payments.arn] },
        { actions = ["events:PutEvents"], resources = [aws_cloudwatch_event_bus.this.arn] },
        { actions = local.sqs_consume, resources = [aws_sqs_queue.main["payment"].arn] },
      ]
    }
  }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "service" {
  for_each           = local.services
  name               = "${local.name_prefix}-${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  for_each   = local.services
  role       = aws_iam_role.service[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray" {
  for_each   = local.services
  role       = aws_iam_role.service[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "service" {
  for_each = local.services
  name     = "access"
  role     = aws_iam_role.service[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for s in each.value.statements : {
      Effect   = "Allow"
      Action   = s.actions
      Resource = s.resources
    }]
  })
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
  role             = aws_iam_role.service[each.key].arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  filename         = data.archive_file.lambda[each.key].output_path
  source_code_hash = data.archive_file.lambda[each.key].output_base64sha256
  timeout          = var.lambda_timeout_s
  memory_size      = var.lambda_memory_mb

  tracing_config { mode = "Active" }

  environment { variables = local.common_env }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.service]
}

# SQS -> Lambda triggers (warehouse, payment, orders)
resource "aws_lambda_event_source_mapping" "sqs" {
  for_each = local.queues

  event_source_arn        = aws_sqs_queue.main[each.key].arn
  function_name           = aws_lambda_function.svc[each.key].arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config { maximum_concurrency = 10 }

  depends_on = [aws_iam_role_policy.service]
}
