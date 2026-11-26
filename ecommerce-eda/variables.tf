variable "aws_region" {
  description = "Learner Lab only allows us-east-1 and us-west-2."
  type        = string
  default     = "us-east-1"
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

variable "enable_xray" {
  description = "X-Ray tracing (may be blocked in Learner Lab). Try true once the base deploy works."
  type        = bool
  default     = false
}

variable "enable_frontend" {
  description = "S3 + CloudFront storefront (CloudFront OAC may be blocked in Learner Lab)."
  type        = bool
  default     = false
}
