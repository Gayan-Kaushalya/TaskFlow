# ADR-0001: ECS Hosting Model - EC2 Launch Type over Fargate

## Context

The assignment requires deploying a containerised FastAPI application on Amazon ECS and applying Ansible-based host hardening and configuration management to the underlying compute nodes. Two ECS launch types are available:

| Capability               | ECS on EC2                             | ECS on Fargate                         |
| :------------------------ | :------------------------------------- | :------------------------------------- |
| Host access (SSH / SSM)   | Full OS-level access                | No host access - serverless runtime |
| Ansible applicability     | Ansible can manage and harden hosts | No host to configure                |
| Instance-level monitoring | CloudWatch Agent installable        | Limited to task-level metrics       |
| Operational overhead      | Higher - AMI patching, ASG management  | Lower - AWS manages hosts              |
| Cost at low utilisation   | Higher - EC2 instance runs 24/7        | Lower - pay-per-task-second            |

A core deliverable of the assessment is demonstrating **Ansible configuration management** including SSH hardening, sysctl tuning, automatic security patching (`dnf-automatic`), and service verification (Docker daemon, ECS agent, CloudWatch agent). These tasks require a host operating system to configure.

## Decision

We will use the **ECS EC2 launch type** backed by an Auto Scaling Group of ECS-optimised Amazon Linux 2023 instances.

### Rationale

1. **Assignment requirement compliance:** The assessment explicitly requires Ansible host hardening. Fargate abstracts away the host layer entirely, making it impossible to demonstrate SSH configuration, kernel sysctl hardening, or package-level agent management - all of which are mandatory deliverables.

2. **Demonstrates full-stack platform engineering:** Operating EC2-backed ECS forces the engineer to manage the complete compute lifecycle - AMI selection, instance profiles, user-data for cluster registration, security groups, launch templates, and ASG integration - showcasing a broader skill set than Fargate's managed abstraction.

3. **Ansible + SSM integration showcase:** The pipeline uses AWS Systems Manager Session Manager as the SSH transport (`ProxyCommand` in `ansible.cfg`), demonstrating bastion-less, zero-inbound-port connectivity to private subnet instances. This pattern is only possible with EC2 hosts.

4. **Observability depth:** Installing the CloudWatch Agent directly on the host via Ansible provides access to instance-level system metrics (disk I/O, memory, network) that Fargate's built-in metrics do not expose.

### Trade-offs accepted

- **Higher operational overhead:** We accept responsibility for AMI patching and host lifecycle management. This is partially mitigated by using the SSM parameter store for the latest ECS-optimised AMI and `dnf-automatic` for unattended security updates.
- **Higher baseline cost:** A `t3.small` instance runs continuously even at zero task load. For a production system at scale, Fargate or mixed capacity providers would be reconsidered.
- **Blast radius:** A host-level misconfiguration could affect all tasks on that instance. Fargate's task-level isolation would eliminate this risk.

## Consequences

- EC2 instances are launched in **private subnets** with outbound internet access through a NAT Gateway, and SSH access is provided only via SSM - no bastion host or public IP.
- An **Ansible playbook** runs post-Terraform in the CI/CD pipeline to harden and verify each ECS host before task deployment begins.
- The **Auto Scaling Group** is configured with `min_size=1`, `max_size=2` to keep cost low while retaining the ability to add capacity.
- If the assignment requirements changed to remove the Ansible deliverable, **Fargate would be the preferred launch type** due to its lower operational overhead and per-second billing.
