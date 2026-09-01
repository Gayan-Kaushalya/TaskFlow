# ADR-0005: Terraform Module Structure - Per-Service Modules with Environment Composition

## Context

The infrastructure spans multiple AWS services: VPC networking, IAM roles, ECS compute, RDS database, and a custom vertical scaling mechanism. We need to decide how to organise the Terraform code for clarity, reusability, and testability.

Alternatives considered:

1. **Monolithic single directory:** All resources in one `main.tf`. Simple for small projects but becomes difficult to navigate and test as resource count grows.
2. **Community modules (e.g., `terraform-aws-modules/vpc`):** Pre-built, well-tested modules. However, they add external dependencies, may include unnecessary complexity, and reduce visibility into what is provisioned - a disadvantage in an assessment context where demonstrating understanding is important.
3. **Custom per-service modules with environment composition roots:** Each logical service boundary gets its own module, and environment directories compose them together. Balances clarity with reusability.

## Decision

We will use **custom, per-service Terraform modules** composed by environment-specific root configurations:

```
terraform/
├── modules/
│   ├── vpc/              # VPC, subnets, route tables, NAT/IGW
│   ├── iam/              # Instance profiles, execution/task roles
│   ├── ecs/              # ECR, ALB, ECS cluster/service/task, auto scaling
│   ├── rds/              # RDS instance, subnet group, security group, Secrets Manager
│   └── vertical_scaling/ # Lambda scaler, CloudWatch alarm, IAM for Lambda
└── envs/
    └── prod/             # Root module composing all service modules
        ├── main.tf       # Module calls with cross-module variable wiring
        ├── versions.tf   # Provider constraints and S3 backend
        ├── variables.tf  # Environment-specific inputs
        └── terraform.tfvars
```

### Design principles

- **Module boundaries follow AWS service boundaries**, making it easy to reason about blast radius of changes. A change to `modules/rds` cannot accidentally modify networking or IAM resources.
- **Cross-module dependencies** are expressed through explicit output → variable wiring in `envs/prod/main.tf` (e.g., `module.vpc.vpc_id → module.ecs.vpc_id`). No hard-coded references between modules.
- **No community module dependencies.** All modules are hand-written to demonstrate understanding of the underlying AWS resources and to keep the dependency footprint minimal.
- **Remote state** is stored in S3 with DynamoDB locking (`taskflow-tfstate-bucket-gayankk` / `taskflow-tfstate-locks`), enabling safe concurrent operations and pipeline-based applies.

## Consequences

- **Clarity:** Each module has a focused scope (50–120 lines), making code review and assessment evaluation straightforward.
- **Environment extensibility:** Adding a `staging` environment requires only a new directory under `envs/` with its own `main.tf` and `terraform.tfvars` - no module changes needed.
- **Trade-off - duplication risk:** Without community modules, common patterns (e.g., subnet creation, security group rules) are hand-rolled and could diverge across environments. Acceptable at the current single-environment scale.
- **State isolation:** Each environment has its own state file key (`prod/terraform.tfstate`), preventing cross-environment state corruption.
