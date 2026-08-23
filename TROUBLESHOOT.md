# Troubleshooting

## Backend Configuration Changed

If `terraform init -backend-config=backend.hcl` gives:

```Error
╷
│ Error: Backend configuration changed
│ 
│ A change in the backend configuration has been detected, which may require migrating existing state.
│ 
│ If you wish to attempt automatic migration of the state, use "terraform init -migrate-state".
│ If you wish to store the current configuration with no changes to the state, use "terraform init -reconfigure".
╵
```

Run:

```bash
terraform init -reconfigure -backend-config=backend.hcl
```

Then:

```bash
terraform init -backend-config=backend.hcl
```

## Invalid SQS Queue Name

If you see:

```Error
Error: invalid queue name: enc-blog-sqs-pipeline-queue.fifo-dlq.fifo
```

The `sqs_queue_name` variable in `terraform.tfvars` should NOT include the `.fifo` suffix — Terraform appends it automatically:

```hcl
sqs_queue_name = "enc-blog-sqs-pipeline-queue"  # correct — no .fifo
```

## VPC-Attached Lambdas Taking 3-5 Minutes

This is normal AWS behavior on first creation. AWS provisions Hyperplane ENIs in your private subnets. Subsequent updates are fast since ENIs persist.

## Security Group Rule Error: All Protocols + Specific Ports

If you see:

```Error
Error: InvalidParameterValue: You may not specify all protocols and specific ports.
```

When using `ip_protocol = "-1"` (all protocols), omit `from_port` and `to_port` entirely:

```hcl
resource "aws_vpc_security_group_ingress_rule" "example" {
  security_group_id            = aws_security_group.example.id
  referenced_security_group_id = aws_security_group.example.id
  ip_protocol                  = "-1"
  # Do NOT set from_port or to_port with "-1"
}
```

## Archive Creation Error: Missing fpe_layer Directory

If you see:

```Error
Error: error archiving directory: could not archive missing directory: modules/vault-transform-service/assets/fpe_layer
```

The FPE layer directory doesn't exist. This is created by `bootstrap.sh`. If you skipped bootstrap or cloned fresh, run:

```bash
mkdir -p modules/vault-transform-service/assets/fpe_layer/python
touch modules/vault-transform-service/assets/fpe_layer/python/__init__.py
```

Or re-run the bootstrap script:

```bash
./scripts/bootstrap.sh
```

The `terraform_data.build_fpe_layer` resource populates this directory with packages during `terraform apply`.

## Glue Job Script Not Found in S3

If the Glue job fails because the script doesn't exist in S3, Terraform now uploads it automatically via `aws_s3_object.glue_encryption_script`. The Glue job has `depends_on` to ensure the script is uploaded first. Re-run `terraform apply`.

## State Lock Issues

If you see "Releasing state lock..." messages after errors, this is normal — Terraform acquired a lock before the operation and releases it on failure. No action needed.

## DNS Resolution Failure (no such host)

If you see errors like:

```Error
Error: request send failed, Post "https://sts.us-east-1.amazonaws.com/": dial tcp: lookup sts.us-east-1.amazonaws.com: no such host
```

This is a local network/DNS issue — your machine cannot resolve AWS endpoints. Common causes:

- No internet connection
- VPN blocking DNS resolution to AWS endpoints
- DNS resolver misconfiguration

**Fix:** Check your internet connection, disconnect/reconnect VPN:

```bash
nslookup sts.us-east-1.amazonaws.com
```

**Fix:**  or Re-run:

```bash
terraform apply -var-file=tfvars/terraform.tfvars
```

If that fails, your DNS is the problem — not Terraform. Once connectivity is restored, re-run the same Terraform command.
## Glue Job Gets 403 from the Vault Transform API

`POST /transform/encrypt` uses `AWS_IAM` authorization, so a 403 is an authorization failure rather
than a bad path. Work through these in order.

**`{"message":"Missing Authentication Token"}`**

Either the request was not SigV4-signed, or the path is wrong. API Gateway returns this same body
for both. Confirm the URL ends in `/transform/encrypt` and that the call goes through
`encryption_api()`, which signs it. A request built with a plain `requests.post(...)` will always
fail here.

**`{"message":"The security token included in the request is invalid"}` or a signature mismatch**

The signature did not verify. Usual causes:

- Signing region does not match the API region. `encryption_api()` resolves the region from the
  boto3 session, then `AWS_REGION` / `AWS_DEFAULT_REGION`, then the execute-api hostname. Set
  `AWS_REGION` on the Glue job if none of those resolve to `us-east-1`.
- The body was re-serialized after signing. SigV4 hashes the exact bytes sent, so the same string
  must be passed to `AWSRequest(data=...)` and `requests.post(data=...)`.
- The `Host` header sent does not match the one signed.

**`{"Message":"User: ... is not authorized to perform: execute-api:Invoke"}`**

The Glue execution role lacks the permission. It is scoped to the exact method:

```json
"Resource": "${vault_api_execution_arn}/*/POST/transform/encrypt"
```

Verify the role in use is `enc-blog-iam-glue-execution-role` and that the API execution ARN in the
policy matches the deployed API.

**403 with no useful body**

The resource policy denied the request because `aws:sourceVpce` did not match. Check that the Glue
connection is attached to the subnets that route to the `execute-api` interface endpoint, and that
`execute_api_vpc_endpoint_id` in Terraform matches the deployed endpoint.

**Authorization change did not take effect**

API Gateway serves whatever is in the deployed stage. Changing `authorization` or the resource
policy requires a new deployment. The `aws_api_gateway_deployment` trigger hash includes
`aws_api_gateway_method.encrypt_post.authorization` for this reason, since the method's Terraform
`id` does not change when authorization does. If the stage still behaves the old way, confirm a new
deployment was created:

```bash
aws apigateway get-deployments --rest-api-id <api-id>
```
