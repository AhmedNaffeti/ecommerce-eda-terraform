# Event-Driven Serverless E-Commerce (AWS + Terraform)

Flow: `POST /orders` -> **OrderCreated** -> SQS warehouse -> Warehouse Lambda -> **StockReserved / StockRejected**
-> SQS payment -> Payment Lambda -> **PaymentSucceeded / PaymentFailed** -> SQS orders -> Orders Lambda (status update + SNS).

## Deploy
```bash
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

## Try it
```bash
aws cognito-idp sign-up --client-id <client_id> --username you@example.com --password 'Passw0rd'
aws cognito-idp admin-confirm-sign-up --user-pool-id <pool_id> --username you@example.com
aws cognito-idp admin-add-user-to-group --user-pool-id <pool_id> --username you@example.com --group-name admins

TOKEN=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id <client_id> \
  --auth-parameters USERNAME=you@example.com,PASSWORD='Passw0rd' --query AuthenticationResult.IdToken --output text)

curl -X POST $API/products -H "Authorization: $TOKEN" -d '{"name":"Laptop","price":999.9,"stock":5}'
curl -X POST $API/orders   -H "Authorization: $TOKEN" -d '{"items":[{"product_id":"<id>","quantity":1}]}'
curl $API/orders -H "Authorization: $TOKEN"   # status becomes CONFIRMED or CANCELLED
```
