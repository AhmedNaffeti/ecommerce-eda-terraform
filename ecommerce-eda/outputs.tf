output "api_url" {
  value = aws_api_gateway_stage.this.invoke_url
}

output "website_url" {
  value = "https://${aws_cloudfront_distribution.web.domain_name}"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "event_bus_name" {
  value = aws_cloudwatch_event_bus.this.name
}

output "queue_urls" {
  value = { for k, q in aws_sqs_queue.main : k => q.url }
}

output "dlq_urls" {
  value = { for k, q in aws_sqs_queue.dlq : k => q.url }
}

output "order_notifications_topic_arn" {
  value = aws_sns_topic.orders.arn
}
