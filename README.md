# TaskFlow 

A containerised task-management REST API deployed on **AWS ECS (EC2 launch type)** with full infrastructure-as-code, configuration management, CI/CD automation, and auto-scaling.

| Layer | Technology |
| :--- | :--- |
| Application | Python 3.11 · FastAPI · Uvicorn · psycopg 3 |
| Container | Multi-stage Docker build · Amazon ECR |
| Orchestration | Amazon ECS on EC2 · Application Load Balancer |
| Database | Amazon RDS PostgreSQL 15 · Secrets Manager |
| Infrastructure | Terraform 1.10 · modular per-service layout |
| Configuration | Ansible · SSM Session Manager transport |
| CI/CD | GitHub Actions · 9-stage gated pipeline |
| Scaling | Horizontal (ECS target tracking) · Vertical (CloudWatch → Lambda) |

---

## Repository Structure

```
.
├── app/                          # Application source and Dockerfile
│   ├── src/                      #   FastAPI application code
│   ├── tests/                    #   Pytest unit tests
│   ├── Dockerfile                #   Multi-stage build
│   └── requirements.txt
├── terraform/
│   ├── modules/                  # Reusable Terraform modules
│   │   ├── vpc/                  #   VPC, subnets, NAT Gateway
│   │   ├── iam/                  #   IAM roles and instance profiles
│   │   ├── ecs/                  #   ECR, ALB, ECS cluster/service, auto scaling
│   │   ├── rds/                  #   RDS PostgreSQL, Secrets Manager
│   │   └── vertical_scaling/     #   Lambda scaler, CloudWatch alarm
│   └── envs/
│       └── prod/                 # Production root module
├── ansible/
│   ├── roles/
│   │   ├── security_hardening/   #   SSH hardening, sysctl, auto-updates
│   │   └── ecs_node/             #   CloudWatch agent, Docker, ECS agent
│   ├── inventory/                #   Dynamic AWS EC2 inventory
│   └── site.yml
├── .github/workflows/
│   └── pipeline.yml              # GitHub Actions CI/CD pipeline
├── docs/
│   ├── adr/                      # Architecture Decision Records
│   ├── architecture-diagram.png
│   └── runbook.md                # Operational runbook
└── evidence/                     # Pipeline execution evidence
```

---

## DevOps vs. Platform Engineering

DevOps focuses on changing the culture between software developers and IT operations so teams can build, test, and release software faster. Instead of passing code over to a separate operations team, developers take on more operational tasks, such as managing pipelines and monitoring applications. While this approach speeds up delivery and breaks down old barriers, it often forces developers to learn too many complex cloud tools. Over time, managing infrastructure, security scripts, and deployment pipelines can distract developers from their main job of writing useful application features.

Platform engineering solves this problem by building dedicated internal developer platforms that simplify daily operations. A specialized platform team creates self-service tools, templates, and automated workflows tailored to their needs. Developers can easily deploy code, provision databases, and check system health without needing to become cloud infrastructure experts. In this way, platform engineering does not replace DevOps principles, but rather improves them by reducing mental strain on developers and letting them focus on building great products.

---

## The Shift Toward DevSecOps

The shift toward DevSecOps replaces late-stage security bottlenecks with continuous, automated quality gates embedded directly into the developer workflow. In cloud and CI/CD environments, traditional pre-release audits are too slow. Remediating vulnerabilities after deployment is more expensive and risky. By integrating automated secret detection, infrastructure-as-code linting, container scanning, and least-privilege policies directly into pull requests, teams can catch critical flaws during active development. This transforms security into an automated feedback loop, allowing organizations to accelerate software delivery without compromising system resilience or compliance.

---

## Setup and Local Run Instructions

### Prerequisites

| Tool | Version | Purpose |
| :--- | :--- | :--- |
| Python | 3.11+ | Application runtime |
| Docker | 24+ | Container build and local database |
| Terraform | 1.5+ | Infrastructure provisioning |
| AWS CLI | 2.x | Cloud interaction |
| Ansible | 2.15+ | Host configuration management |
| Git | 2.x | Version control |

### 1. Clone the Repository

```bash
git clone https://github.com/Gayan-Kaushalya/TaskFlow.git
cd TaskFlow
```

### 2. Run the Application Locally

**Start a local PostgreSQL database:**

```bash
docker run -d \
  --name taskflow-db \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=taskflow \
  -p 5433:5432 \
  postgres:15
```

**Install Python dependencies and start the server:**

```bash
cd app
python -m venv venv
source venv/bin/activate      # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

```bash
DATABASE_URL="postgresql://postgres:postgres@localhost:5433/taskflow" \
uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload
```

The API is now available at `http://localhost:8000`. The health check endpoint is at `http://localhost:8000/health`.

**Interactive API documentation:** FastAPI auto-generates Swagger UI at `http://localhost:8000/docs`.

### 3. Run Tests

```bash
cd app
pytest tests/ -v --cov=src --cov-report=term-missing --cov-fail-under=70
```

### 4. Build the Docker Image Locally

```bash
cd app
docker build -t taskflow-app:local .
docker run -d \
  --name taskflow-app \
  -e DATABASE_URL="postgresql://postgres:postgres@host.docker.internal:5433/taskflow" \
  -p 8000:8000 \
  taskflow-app:local
```

### 5. Lint Checks

```bash
# Python
pip install flake8 black
black --check app/
flake8 app/ --max-line-length=120

# Terraform
terraform fmt -check -recursive terraform/

# Ansible
pip install ansible-lint
ansible-lint ansible/site.yml
```

---

## Reproducing the Full Deployment from a Clean AWS Account

This section describes the one-time setup needed in a fresh AWS account, followed by the automated pipeline that handles all subsequent deployments.

### Step 1 - Create the Terraform State Backend

Terraform requires a pre-existing S3 bucket and DynamoDB table for remote state locking. These must be created manually (or via a separate bootstrap script) before the first `terraform init`.

```bash
# Create the S3 bucket for state storage
aws s3api create-bucket \
  --bucket <your-unique-tfstate-bucket-name> \
  --region us-east-1

# Enable versioning for state recovery
aws s3api put-bucket-versioning \
  --bucket <your-unique-tfstate-bucket-name> \
  --versioning-configuration Status=Enabled

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket <your-unique-tfstate-bucket-name> \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

# Block all public access
aws s3api put-public-access-block \
  --bucket <your-unique-tfstate-bucket-name> \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create the DynamoDB table for state locking
aws dynamodb create-table \
  --table-name taskflow-tfstate-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Then update `terraform/envs/prod/versions.tf` to point to your bucket name:

```hcl
backend "s3" {
  bucket         = "<your-unique-tfstate-bucket-name>"
  key            = "prod/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "taskflow-tfstate-locks"
  encrypt        = true
}
```

### Step 2 - Configure GitHub Repository Secrets

In your GitHub repository, go to **Settings → Secrets and variables → Actions** and create these secrets:

| Secret Name | Value |
| :--- | :--- |
| `AWS_ACCESS_KEY_ID` | IAM user access key with admin-level permissions |
| `AWS_SECRET_ACCESS_KEY` | Corresponding secret key |
| `EC2_SSH_KEY` | Private SSH key (PEM format) for Ansible EC2 connectivity |

### Step 3 - Create a GitHub Environment with Protection Rules

Go to **Settings → Environments** and create an environment named `production`:

- Enable **Required reviewers** and add at least one approver.
- This gates the `terraform apply` stage, preventing automated infrastructure changes without human approval.

### Step 4 - Generate an SSH Key Pair

```bash
ssh-keygen -t rsa -b 4096 -f taskflow-ec2-key -N ""
```

Add the contents of `taskflow-ec2-key` (the private key) to the `EC2_SSH_KEY` GitHub secret created in Step 2.

### Step 5 - Push to Main and Trigger the Pipeline

```bash
git push origin main
```

The GitHub Actions pipeline will execute the following stages automatically:

1. **Lint** - Python (Black, Flake8), Terraform (`fmt -check`), Ansible Lint
2. **Security** - Gitleaks secret scanning, Trivy IaC vulnerability scan
3. **Test** - Pytest with 70% coverage gate
4. **Build & Push** - Docker build → tag with Git SHA → push to ECR
5. **Terraform Plan** - Preview infrastructure changes
6. **Terraform Apply** - *Requires manual approval* via the `production` environment
7. **Ansible Configure** - SSH hardening, CloudWatch agent, ECS/Docker service verification
8. **ECS Deploy** - Force new deployment on the ECS service
9. **Smoke Test** - Retry loop against ALB `/health` endpoint until HTTP 200

### Step 6 - Verify the Deployment

After the pipeline completes, retrieve the ALB DNS name:

```bash
cd terraform/envs/prod
terraform output alb_dns_name
```

Test the live application:

```bash
# Health check
curl http://<ALB_DNS_NAME>/health

# Create a task
curl -X POST http://<ALB_DNS_NAME>/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "First task", "description": "Deployed from pipeline", "priority": "HIGH"}'

# List all tasks
curl http://<ALB_DNS_NAME>/tasks
```

### Tear Down

To destroy all provisioned infrastructure:

```bash
cd terraform/envs/prod
terraform destroy -auto-approve
```

---

## Architecture Decision Records

Detailed ADRs covering key design decisions are in [`docs/adr/`](docs/adr/):

| ADR | Decision |
| :--- | :--- |
| [0001](docs/adr/0001-ecs-hosting-model.md) | ECS on EC2 over Fargate - required for Ansible host hardening |
| [0002](docs/adr/0002-vpc-network-topology.md) | Public/private subnet split with NAT Gateway |
| [0003](docs/adr/0003-container-image-strategy.md) | Multi-stage Docker build with non-root execution |
| [0004](docs/adr/0004-scaling-strategy.md) | Dual horizontal + vertical auto-scaling strategy |
| [0005](docs/adr/0005-terraform-module-structure.md) | Custom per-service Terraform modules with env composition |
| [0006](docs/adr/0006-ansible-ssm-connectivity.md) | SSM Session Manager as bastion-less Ansible transport |
| [0007](docs/adr/0007-database-credentials-management.md) | Secrets Manager with ECS native injection |

## Additional Documentation

- **[Operational Runbook](docs/runbook.md)** - Deployment, rollback, scaling, and incident response procedures.
