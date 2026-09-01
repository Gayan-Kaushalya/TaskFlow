# ADR-0002: VPC Network Topology - Public/Private Subnet Split with NAT Gateway

## Context

The application consists of internet-facing components (Application Load Balancer) and internal components (ECS container hosts, RDS database) that must not be directly reachable from the public internet. We need a network design that:

- Allows the ALB to receive inbound HTTP traffic from the internet.
- Keeps ECS instances and RDS in a non-publicly-routable network.
- Provides outbound internet access for private instances (ECR image pulls, SSM agent registration, package updates).
- Spans at least two Availability Zones for ALB and RDS subnet group requirements.

Alternatives considered:

1. **All-public subnets:** Simple but exposes EC2 instances and RDS to internet-routable addresses, violating defence-in-depth.
2. **Public/private with VPC endpoints only (no NAT):** Lower cost but requires creating and maintaining individual VPC endpoints for ECR, SSM, Secrets Manager, CloudWatch, and S3 - increasing Terraform complexity significantly.
3. **Public/private with NAT Gateway:** Moderate cost with clean outbound access from private subnets.

## Decision

We will use a **two-tier VPC** (`10.0.0.0/16`) with:

- **2 public subnets** across two AZs - hosting the ALB and NAT Gateway.
- **2 private subnets** across two AZs - hosting ECS EC2 instances and RDS.
- **A single NAT Gateway** in the first public subnet for outbound internet from private subnets.

## Consequences

- **Security posture:** ECS instances and RDS have no public IP addresses and no direct inbound internet path. All inbound application traffic is mediated by the ALB. SSH access to EC2 hosts is via SSM Session Manager over the NAT Gateway's outbound path.
- **NAT Gateway as single point of failure:** Using a single NAT Gateway (rather than one per AZ) introduces a single point of failure for outbound connectivity. This is acceptable for an assessment exercise to reduce cost (~$32/month per NAT Gateway). For production, a NAT Gateway per AZ would be deployed.
- **Cost:** NAT Gateway incurs ~$32/month fixed plus data processing charges. This is the primary ongoing networking cost beyond ALB.
- **Outbound access:** Private instances can reach ECR, SSM, Secrets Manager, and the internet for package updates without VPC endpoints, keeping the Terraform simpler.
