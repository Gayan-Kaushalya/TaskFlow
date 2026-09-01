# ADR-0007: Database Credentials Management - Secrets Manager with ECS Native Injection

## Context

The FastAPI application connects to an RDS PostgreSQL database and requires a `DATABASE_URL` connection string at runtime. This secret must be provisioned, stored, rotated, and injected securely without hard-coding credentials in source code, environment variables visible in the task definition, or Terraform state in plaintext.

Alternatives considered:

1. **Terraform `sensitive` variable passed at apply time:** Credentials exist in Terraform state (even if marked sensitive) and require manual input or CI/CD secret injection at plan/apply time. Rotation requires a Terraform change.
2. **AWS Systems Manager Parameter Store (SecureString):** Free tier, KMS-encrypted, but limited to 4KB and lacks native rotation support.
3. **AWS Secrets Manager with ECS container definition `secrets` block:** Automatic KMS encryption, native ECS integration via the `valueFrom` field in container definitions, optional rotation with Lambda, and audit trail via CloudTrail.
4. **HashiCorp Vault:** Powerful but introduces an additional system to deploy and manage - over-engineered for this scope.

## Decision

We will use **AWS Secrets Manager** to store the database connection string, with **ECS native secret injection** to deliver it to the container at task launch time.

### Implementation

1. **Terraform provisions the secret:** `random_password` generates a 16-character password. `aws_secretsmanager_secret_version` stores the full `DATABASE_URL` (including host, username, password, and database name) as a JSON-encoded secret.

2. **ECS task definition references the secret:** The container definition uses the `secrets` block rather than `environment`:
   ```json
   "secrets": [{
     "name": "DATABASE_URL",
     "valueFrom": "<secret_arn>:DATABASE_URL::"
   }]
   ```
   The ECS agent fetches the secret value at task start via the Execution Role's `secretsmanager:GetSecretValue` permission.

3. **The secret never appears in:** Terraform outputs, ECS console environment variables, container `docker inspect` output, or CI/CD logs.

## Consequences

- **Zero credential exposure:** The `DATABASE_URL` is resolved by the ECS agent at launch time. It does not appear in the task definition's `environment` block (which is visible in the AWS console), only in the `secrets` block as an ARN reference.
- **Terraform state contains the password:** `random_password` and `aws_secretsmanager_secret_version` store the password in Terraform state. The S3 backend is configured with `encrypt = true` to mitigate this. For production, Terraform state access should be restricted via IAM.
- **No automatic rotation:** The current implementation does not configure Secrets Manager rotation. Rotation would require a Lambda function that updates both the RDS password and the secret value, then triggers an ECS redeployment. This is a known gap acceptable for the exercise.
- **Recovery window set to zero:** `recovery_window_in_days = 0` allows immediate secret deletion during `terraform destroy`. In production, a 7–30 day recovery window would be used to prevent accidental deletion.
