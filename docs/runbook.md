# TaskFlow Operational Runbook

## 1. System Overview & Architecture

* **Traffic Ingress**: Public Internet -> Application Load Balancer (`taskflow-alb`) -> Target Group (`taskflow-tg`) routing to port 8000.
* **Compute Host & Orchestration**: Amazon ECS Cluster (`taskflow-cluster`) running on EC2 container hosts in an Auto Scaling Group created with the prefix `taskflow-ecs-asg-`, placed across private subnets in two Availability Zones.
* **Database Layer**: Amazon RDS PostgreSQL (`taskflow-postgres`) instance running in private subnets with credentials stored in AWS Secrets Manager (`taskflow/db-credentials`). The Terraform configuration provisions a single RDS instance rather than a multi-AZ deployment.
* **Telemetry & Logging**: JSON-formatted stdout logs from the application are shipped to CloudWatch Log Group `/ecs/taskflow`; the repo also creates `/ec2/taskflow-instances` for EC2 host logging and installs the CloudWatch agent on ECS hosts, but the exact host metric configuration is not defined in the Terraform beyond the log group and agent package installation.

> **Repository note:** The ASG name is created with a prefix (`taskflow-ecs-asg-`) and therefore has a generated suffix in AWS; the exact full name is not hard-coded in Terraform.

---

## 2. Deployment & Rollback Procedures

### Automated CI/CD Deployment Procedure
1. Push code changes via a Pull Request to run static analysis, security scans, and test coverage checks.
2. Merge the Pull Request into the default branch to trigger the deployment pipeline.
3. The pipeline builds the container image, tags it with `$GITHUB_SHA` (and short commit SHA), and pushes it to Amazon ECR.
4. Run `terraform apply` under the manual approval gate to provision or update AWS infrastructure.
5. Execute the Ansible playbook against the dynamic AWS inventory (`aws_ec2`) to apply host baseline hardening and agent configurations.
6. Trigger an ECS service redeployment:
   ```bash
   aws ecs update-service \
     --cluster taskflow-cluster \
     --service taskflow-service \
     --force-new-deployment
   ```
7. The pipeline executes automated smoke tests against `http://<ALB_DNS_NAME>/health` until HTTP 200 is verified.

### Manual Rollback Procedure
If a bad release passes deployment validation or causes runtime degradation:
1. List available Task Definition revisions:
   ```bash
   aws ecs list-task-definitions \
     --family-prefix taskflow-task \
     --sort DESC \
     --max-items 5
   ```
2. Roll back the ECS service to the previous known-good task revision (for example, revision `11`):
   ```bash
   aws ecs update-service \
     --cluster taskflow-cluster \
     --service taskflow-service \
     --task-definition taskflow-task:11 \
     --force-new-deployment
   ```
3. Monitor rolling update status until the previous task definition reaches steady state:
   ```bash
   aws ecs describe-services \
     --cluster taskflow-cluster \
     --services taskflow-service \
     --query "services[0].deployments" \
     --output table
   ```

---

## 3. Scaling Procedures

### Automated Vertical Scaling Mechanism
* **Trigger**: The CloudWatch alarm `taskflow-ecs-high-cpu` monitors average task CPU utilization and triggers when usage exceeds 80% over two 60-second periods.
* **Execution**: CloudWatch invokes the Lambda function `taskflow-vertical-scaler`.
* **Action**: Lambda registers a new Task Definition with upgraded compute specs (CPU: 256 -> 512 units, Memory: 512 -> 1024 MiB) and issues `update-service` with `forceNewDeployment=True`.

### Manual Vertical Scaling Override
If the automated vertical scaling Lambda is throttled or misbehaves:
1. Fetch the active task definition JSON:
   ```bash
   aws ecs describe-task-definition \
     --task-definition taskflow-task \
     --query "taskDefinition" > task-def.json
   ```
2. Update the `cpu` and `memory` fields in `task-def.json` manually (e.g., `"cpu": "512"`, `"memory": "1024"`), stripping metadata fields (`compatibilities`, `taskDefinitionArn`, `revision`, `status`, `registeredAt`, `registeredBy`).
3. Register the new task definition:
   ```bash
   aws ecs register-task-definition --cli-input-json file://task-def.json
   ```
4. Update the service to deploy the new revision:
   ```bash
   aws ecs update-service \
     --cluster taskflow-cluster \
     --service taskflow-service \
     --task-definition taskflow-task:<NEW_REVISION> \
     --force-new-deployment
   ```

### Horizontal vs. Vertical Scaling Matrix

| Dimension | Trigger Mechanism | Target Threshold | Scaling Action | When It Applies |
| :--- | :--- | :--- | :--- | :--- |
| **Horizontal Scaling (Bonus)** | ECS Target Tracking Policy | Average CPU > 60% | Increases `desired_count` (1 to 4 tasks) | High request concurrency, distributed HTTP load, stateless request spreading. |
| **Vertical Scaling** | CloudWatch Alarm + Lambda | Task CPU > 80% | Upsizes CPU (256->512) & Memory (512->1024 MiB) | Monolithic bottlenecks, memory-intensive data operations, single-task compute saturation. |

---

## 4. Incident Management & Remediation

### Incident 1: ECS Tasks Stuck in `PENDING`
* **Symptoms**: Task count does not match desired count; tasks alternate between `PENDING` and `STOPPED`.
* **Root Causes**:
  * EC2 container instances have insufficient available CPU/Memory resources.
  * Host EC2 instances cannot register with the ECS cluster due to missing IAM roles or outbound network failures.
* **Diagnosis**:
  ```bash
  aws ecs list-tasks --cluster taskflow-cluster --desired-status STOPPED
  aws ecs describe-tasks --cluster taskflow-cluster --tasks <TASK_ARN> --query "tasks[0].stoppedReason"
  ```
* **Remediation**:
  1. Increase the Auto Scaling Group capacity if host resources are saturated:
     ```bash
     aws autoscaling set-desired-capacity \
       --auto-scaling-group-name <ASG_NAME> \
       --desired-capacity 2
     ```
  2. Verify that the EC2 instance role contains `AmazonEC2ContainerServiceforEC2Role` and that private subnet routes point outbound internet traffic to the NAT Gateway.

### Incident 2: ALB Returning HTTP 502 Bad Gateway
* **Symptoms**: External requests to the ALB return HTTP 502; Target Group shows targets in `Unhealthy` state.
* **Root Causes**:
  * The application process is crashing or failing initialization.
  * Security group rules block traffic between the ALB and EC2 container port.
* **Diagnosis**:
  ```bash
  aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>
  aws logs tail /ecs/taskflow --follow --since 15m
  ```
* **Remediation**:
  1. Review application logs in CloudWatch for missing environment variables or database connection errors.
  2. Verify that the EC2 Instance Security Group allows TCP ingress on all ephemeral/container ports (`0-65535`) from the ALB Security Group ID.

### Incident 3: Database Connection Pool Exhaustion
* **Symptoms**: Application logs report `TimeoutError: QueuePool limit of size X reached`; client requests time out.
* **Root Causes**:
  * High concurrency bursts exceeding pool limits.
  * Idle connections retained during horizontal scale-out without connection pooling cleanup.
* **Diagnosis**:
  ```bash
  aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value=taskflow-postgres \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Maximum
  ```
* **Remediation**:
  1. Ensure FastAPI lifespan event handlers cleanly close the database engine pool on task termination.
  2. Adjust pool limits in `app/src/database.py` (e.g., set `pool_size=20`, `max_overflow=10`).
  3. Terminate hanging idle backend connections in RDS PostgreSQL:
     ```sql
     SELECT pg_terminate_backend(pid)
     FROM pg_stat_activity
     WHERE state = 'idle'
       AND state_change < current_timestamp - INTERVAL '5' MINUTE;
     ```

---

## 5. Amazon RDS Backup & Restore Procedures

### Creating an Immediate Manual Snapshot
```bash
aws rds create-db-snapshot \
  --db-instance-identifier taskflow-postgres \
  --db-snapshot-identifier taskflow-postgres-manual-$(date +%Y%m%d%H%M)
```

### Restoring Database from Snapshot
1. Retrieve snapshot identifier:
   ```bash
   aws rds describe-db-snapshots \
     --db-instance-identifier taskflow-postgres \
     --query "DBSnapshots[*].DBSnapshotIdentifier" \
     --output table
   ```
2. Restore to a new RDS instance inside the private DB subnet group:
   ```bash
   aws rds restore-db-instance-from-db-snapshot \
     --db-instance-identifier taskflow-postgres-restored \
     --db-snapshot-identifier <SNAPSHOT_IDENTIFIER> \
     --db-subnet-group-name taskflow-db-subnet-group \
     --vpc-security-group-ids <RDS_SECURITY_GROUP_ID>
   ```
3. Wait for the restored database instance to become available:
   ```bash
   aws rds wait db-instance-available --db-instance-identifier taskflow-postgres-restored
   ```

4. Update the DATABASE_URL Secret in AWS Secrets Manager

Update the `DATABASE_URL` secret value stored in AWS Secrets Manager (`taskflow/db-credentials`) with the new RDS endpoint:

```bash
aws secretsmanager update-secret \
  --secret-id taskflow/db-credentials \
  --secret-string '{"DATABASE_URL":"postgresql://taskflow_user:<PASSWORD>@<NEW_RDS_ENDPOINT>:5432/taskflowdb"}'
```

> **Note:** Replace `<PASSWORD>` and `<NEW_RDS_ENDPOINT>` with the actual credentials and endpoint.

5. Trigger an ECS Rolling Deployment

Force a new deployment on the ECS service to inject the updated database URL into running tasks:

```bash
aws ecs update-service \
  --cluster taskflow-cluster \
  --service taskflow-service \
  --force-new-deployment
```

This performs a rolling restart — ECS will launch new tasks that pull the latest secret values and gracefully drain the old tasks.

6. Verify the Deployment

Monitor the deployment status to ensure all tasks are running with the new configuration:

```bash
aws ecs describe-services \
  --cluster taskflow-cluster \
  --services taskflow-service \
  --query 'services[0].deployments'
```

Confirm that the `PRIMARY` deployment shows the desired count matching the running count and that no `ACTIVE` (old) deployments remain.
