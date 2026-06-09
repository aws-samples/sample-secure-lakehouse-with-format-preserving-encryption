# Security

## Disclaimer

This is sample code accompanying an AWS blog post. It is provided for educational purposes only and is **not production-ready**. Do not deploy to production without the additional hardening listed below. The code is not certified for any compliance regime, including PCI DSS.

## AWS Services Used

| Service | Security-Relevant Configuration |
| --------- | ------------------------------- |
| Amazon S3 | SSE-KMS encryption, versioning, public access blocked, VPC gateway endpoint |
| Amazon SQS | SSE-KMS encryption, DLQ with redrive policy |
| AWS KMS | Customer-managed key with rotation enabled, resource-level grants |
| AWS Secrets Manager | KMS-encrypted, accessed only via VPC endpoint |
| Amazon API Gateway | Private endpoint, VPC endpoint resource policy restriction |
| AWS Lambda | VPC-attached (private subnets), least-privilege IAM roles |
| AWS Glue | VPC-attached via NETWORK connection, least-privilege IAM |
| AWS Step Functions | Execution logging to CloudWatch, scoped IAM role |
| Amazon VPC | Private subnets only, no IGW/NAT, 7 interface + 1 gateway endpoint |

## Known Security Considerations

### 1. KMS Key Policy — `kms:*` to Root Principal

The KMS key policy grants `kms:*` with `Resource: "*"` to the account root principal. This is the AWS-recommended default key policy pattern that enables IAM policy-based access control for the key.

**Production recommendation:** Scope the key policy to specific administrative roles rather than the root principal. Add condition keys to restrict key usage to specific services.

### 2. Step Functions Logging Policy — `Resource: "*"`

The Step Functions logging policy uses `Resource: "*"` for log delivery actions (`CreateLogDelivery`, `ListLogDeliveries`, `DescribeResourcePolicies`, `DescribeLogGroups`). These actions are account-level operations that require wildcard resources per the AWS Service Authorization Reference.

**Production recommendation:** No change needed — this is the minimum required configuration. The write actions (`CreateLogStream`, `PutLogEvents`) are already scoped to the specific log group ARN.

### 3. API Gateway — `authorization = "NONE"`

The Vault Transform API method uses `authorization = "NONE"`. Access control is enforced at the network layer via:

- Private API Gateway endpoint type
- Resource policy restricting to a specific VPC endpoint (`aws:sourceVpce`)
- VPC with no internet access

**Production recommendation:** Add IAM authorization (`AWS_IAM`) as defense-in-depth. This adds identity-based access control on top of the existing network restriction.

## Production Hardening Recommendations

### IAM

- Replace root principal `kms:*` with scoped administrative actions for a specific deployment role
- Add `aws:SecureTransport` deny-policies on every S3 bucket and SQS queue
- Enable IAM Access Analyzer for continuous policy validation

### Encryption and TLS

- Enable KMS encryption on CloudWatch Log Groups (`kms_key_id`)
- Enable KMS encryption on Lambda environment variables
- Add `aws:SecureTransport` condition to S3 bucket policies

### Lambda

- Add Dead Letter Queues (DLQ) for async invocations
- Enable X-Ray tracing for distributed debugging
- Configure reserved concurrency to prevent runaway scaling
- Enable code signing to prevent unauthorized deployments
- Encrypt environment variables with the project CMK

### Amazon S3

- Enable S3 access logging (requires a separate logging bucket)
- Add lifecycle rules to expire old object versions
- Consider cross-region replication for disaster recovery
- Add `aws:SecureTransport` deny-policy to bucket policies

### Amazon API Gateway

- Add IAM authorization (`AWS_IAM`) to the POST method
- Enable X-Ray tracing on the stage
- Enable request validation
- Add a custom domain with a client certificate
- Use `create_before_destroy` lifecycle on deployments

### Step Functions and AWS Glue

- Enable X-Ray tracing on the state machine
- Create a Glue Security Configuration (encryption at rest for job bookmarks, CloudWatch logs, S3 targets)
- Add job bookmarks for idempotent reruns

### Observability

- Enable VPC Flow Logs for network-level audit trail
- Enable CloudWatch Logs KMS encryption
- Set strict log retention (30-90 days for demo, per-policy for production)
- Enable AWS CloudTrail for API-level audit

### Secrets and Rotation

- Enable automatic rotation on the Secrets Manager secret (30-90 day schedule)
- Use the `secret_generator` Lambda as the rotation function

### Logging Hygiene

- Redact S3 object keys before logging (may contain PII fragments)
- Move sensitive-column metadata logging to DEBUG level
- Add structured logging with correlation IDs across services

## Resource Cleanup

To destroy all resources created by this project:

```bash
terraform destroy -var-file=tfvars/terraform.tfvars
```

This permanently deletes all S3 buckets (including data), CloudWatch logs, Secrets Manager secrets, and all other infrastructure. Back up any needed data before running.

The state bucket created by `bootstrap.sh` is not Terraform-managed and must be deleted separately:

```bash
aws s3 rb s3://enc-blog-s3-tf-state-bucket-<account-id> --force
```

## Dependencies

| Package | Version | Purpose | License |
| --------- | --------- | --------- | --------- |
| ff3 | 1.0.2 | FF3-1 Format-Preserving Encryption | MIT |
| passlib | 1.7.4 | PBKDF2 key derivation | BSD |
| PyYAML | 6.0.2 | Treatment contract parsing | MIT |
| requests | 2.32.3 | HTTP client for vault API calls | Apache 2.0 |
| boto3 | 1.34.162 | AWS SDK (Glue runtime) | Apache 2.0 |

All dependencies are pinned to exact versions. Lambda layer dependencies are built at `terraform apply` time from `requirements.txt`.
