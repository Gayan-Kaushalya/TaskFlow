# ADR-0006: Ansible Connectivity - SSM Session Manager over Bastion Host

## Context

The ECS EC2 instances reside in private subnets with no public IP addresses and no inbound SSH security group rules from the internet. Ansible must connect to these hosts to perform security hardening and service verification. We need a connectivity mechanism.

Alternatives considered:

1. **Bastion host in a public subnet:** Traditional approach - SSH from CI/CD runner to bastion, then hop to private instances. Requires provisioning and hardening an additional EC2 instance, managing its SSH keys, and opening inbound port 22 on a public-facing security group.
2. **AWS Systems Manager Session Manager as SSH proxy:** SSM agent is pre-installed on ECS-optimised AMIs. The agent initiates an outbound HTTPS connection to the SSM service via the NAT Gateway. Ansible's `ProxyCommand` directive tunnels SSH through `aws ssm start-session`. No inbound ports, no bastion instance.
3. **Ansible with `aws_ssm` connection plugin (direct, no SSH):** Uses SSM `SendCommand` or `StartSession` natively. Avoids SSH entirely but has limited support for some Ansible modules and is less mature.

## Decision

We will use **SSM Session Manager as an SSH transport proxy**, configured via `ProxyCommand` in `ansible.cfg`:

```ini
[ssh_connection]
pipelining = True
ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ControlMaster=auto -o ControlPersist=30m \
    -o ProxyCommand="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"
```

Dynamic inventory uses the `amazon.aws.aws_ec2` plugin, filtering by `tag:Name=taskflow-ecs-node` and using `instance-id` as the hostname - which maps directly to SSM's target identifier.

### Supporting infrastructure

- **IAM:** The EC2 instance role includes `AmazonSSMManagedInstanceCore` policy, granting SSM agent permissions.
- **Network:** Outbound HTTPS from private subnets through the NAT Gateway allows the SSM agent to register with the SSM service.
- **CI/CD:** The pipeline installs the `session-manager-plugin` on the GitHub Actions runner and uses `ec2-instance-connect send-ssh-public-key` to authorise an ephemeral SSH key for each instance.

## Consequences

- **No bastion host** to provision, patch, or pay for. Eliminates an entire attack surface.
- **No inbound SSH ports** open on any security group. All connectivity is outbound-initiated by the SSM agent.
- **Ephemeral key authorisation:** Each pipeline run generates and authorises a fresh SSH key via EC2 Instance Connect, which expires after 60 seconds. This avoids long-lived SSH key management.
- **Dependency on SSM agent registration:** A 30-second wait is inserted in the pipeline after Terraform Apply to allow newly launched instances to register with SSM. If instances are slow to start, this wait may need to be increased.
- **Pipelining enabled:** SSH pipelining is turned on for performance, reducing the number of SSH connections Ansible makes per task execution.
