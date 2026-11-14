terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.60" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }

  # Remote state (recommended for CI/CD) - create the bucket/table first, then uncomment.
  # backend "s3" {
  #   bucket         = "my-tfstate-bucket"
  #   key            = "ecommerce-eda/terraform.tfstate"
  #   region         = "eu-west-1"
  #   dynamodb_table = "tfstate-lock"
  #   encrypt        = true
  # }
}
