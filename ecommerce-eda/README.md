# Event-Driven Serverless E-Commerce (AWS Learner Lab + Terraform)

Flow: POST /orders -> OrderCreated -> SQS warehouse -> Warehouse Lambda -> StockReserved / StockRejected
-> SQS payment -> Payment Lambda -> PaymentSucceeded / PaymentFailed -> SQS orders -> Orders Lambda (status + SNS).

## Learner Lab adaptations
- Lambdas use the existing `LabRole` (no IAM role creation).
- Region: us-east-1. X-Ray and CloudFront frontend are OFF by default (`enable_xray`, `enable_frontend`).
- No DynamoDB PITR, no EventBridge archive. CI only validates (lab credentials expire).

## Deploy (PowerShell)
1. Lab started, credentials pasted in `~/.aws/credentials`, then `aws sts get-caller-identity`.
2. `copy terraform.tfvars.example terraform.tfvars` and set your email.
3. `terraform init`
4. `terraform apply`
5. Confirm the SNS subscription email.
6. `pip install boto3` then `python tests/smoke_test.py`
7. When done: `terraform destroy`

Credentials expire with each lab session: re-paste them before every `terraform` command.
