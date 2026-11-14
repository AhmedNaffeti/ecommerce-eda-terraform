variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "ecommerce"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "notification_email" {
  description = "Email subscribed to the order-notification and alert topics (leave empty to skip)."
  type        = string
  default     = ""
}

variable "lambda_memory_mb" {
  type    = number
  default = 256
}

variable "lambda_timeout_s" {
  type    = number
  default = 10
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "payment_failure_rate" {
  description = "Probability (0-1) that the simulated payment provider declines a payment."
  type        = number
  default     = 0.1
}
