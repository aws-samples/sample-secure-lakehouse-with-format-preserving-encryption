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
