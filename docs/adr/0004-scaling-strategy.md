# ADR-0004: Scaling Strategy - Combined Horizontal and Vertical Auto Scaling

## Context

The assignment requires implementing **vertical scaling** for the ECS service, with horizontal scaling as a bonus. The application is a stateless FastAPI REST API, making it suitable for both scaling dimensions. We need to decide:

1. How to implement vertical scaling, which ECS does not natively support through managed auto-scaling policies.
2. Whether to also implement horizontal scaling and how the two strategies interact.
3. What metrics and thresholds trigger each scaling action.

Alternatives considered for vertical scaling:

1. **Manual task definition updates:** Operator manually registers a new task definition with larger CPU/memory and redeploys. Simple but not automated.
2. **Step Functions workflow:** Orchestrates the describe → register → update cycle. More robust but over-engineered for this scope.
3. **Lambda function triggered by CloudWatch Alarm:** Lightweight, event-driven, and directly invocable by CloudWatch. Fits the exercise scope well.

## Decision

We will implement a **dual-axis scaling strategy**:

### Horizontal Scaling (ECS Application Auto Scaling)

- **Mechanism:** ECS Target Tracking Scaling Policy on `ECSServiceAverageCPUUtilization`.
- **Target:** 60% average CPU utilisation.
- **Range:** 1 to 4 tasks.
- **Cooldowns:** 60 seconds scale-out, 300 seconds scale-in.
- **Use case:** Distributes concurrent HTTP load across multiple stateless task replicas.

### Vertical Scaling (CloudWatch Alarm → Lambda)

- **Mechanism:** A CloudWatch Alarm monitors `CPUUtilization` at the ECS service level. When average CPU exceeds **80%** for two consecutive 60-second periods, it invokes a Lambda function.
- **Lambda action:** The function retrieves the current task definition, registers a new revision with upgraded compute allocation (CPU: 256 → 512, Memory: 512 → 1024 MiB), and triggers a forced redeployment.
- **Use case:** Addresses single-task compute saturation where adding more replicas would not help (e.g., memory-intensive operations, CPU-bound data processing within a single request).

### Interaction between the two axes

| CPU Range | Which fires first | Behaviour |
| :--- | :--- | :--- |
| 0–59% | Neither | Steady state |
| 60–79% | Horizontal only | ECS adds tasks up to max 4 |
| ≥ 80% | Both | Horizontal adds tasks **and** Lambda upsizes the task definition |

The 20-percentage-point gap between the horizontal threshold (60%) and vertical threshold (80%) ensures horizontal scaling is attempted first before vertical scaling modifies the task definition.

## Consequences

- **Horizontal scaling** is fully managed by AWS with no custom code. It handles the common case of HTTP concurrency bursts effectively.
- **Vertical scaling** requires a custom Lambda function, which introduces a component to maintain. However, the function is ~30 lines of Python with no external dependencies.
- **Vertical scaling is a one-way ratchet** in the current implementation - it scales up but does not scale back down. A production system would need a complementary scale-down mechanism (e.g., a scheduled Lambda or a low-CPU alarm that reverts to the baseline task definition).
- **Task definition drift:** After vertical scaling fires, the Terraform-managed task definition (`cpu=256`, `memory=512`) diverges from the running state. The next `terraform apply` will revert the task definition to baseline, which is the intended reset mechanism.
- **CloudWatch Alarm → Lambda permission** is configured with a resource-based policy to allow CloudWatch to invoke the function directly.
