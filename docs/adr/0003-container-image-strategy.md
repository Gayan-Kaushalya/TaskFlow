# ADR-0003: Container Image Strategy - Multi-Stage Build with Non-Root Execution

## Context

The FastAPI application needs to be packaged as a Docker image for deployment on ECS. The image must balance security, size, and build reproducibility. Key concerns:

- Build dependencies (gcc, libpq-dev) should not be present in the runtime image.
- The container process should not run as root.
- The base image should be minimal to reduce the attack surface and image pull time.
- ECR image scanning should be enabled to detect known vulnerabilities.

## Decision

We will use a **multi-stage Docker build** with `python:3.11-slim` as both the builder and runtime base:

### Stage 1 - Builder
- Installs build-time dependencies (`gcc`, `libpq-dev`) needed to compile Python packages with C extensions (e.g., `psycopg` binary).
- Installs Python dependencies to `--user` prefix (`/root/.local`).
- This stage is discarded after build.

### Stage 2 - Runtime
- Starts from a clean `python:3.11-slim` image.
- Installs only runtime dependencies (`libpq5` for PostgreSQL client library, `curl` for container health checks).
- Creates a non-root user (`appuser`, UID 10001) and copies the pre-built Python packages from the builder stage into that user's home directory.
- Runs the application as UID 10001 via `USER 10001`.

### ECR configuration
- `image_tag_mutability = MUTABLE` - allows the `latest` tag to be overwritten on each push, simplifying deployment references.
- `scan_on_push = true` - ECR automatically scans each pushed image for CVEs.

## Consequences

- **Smaller image size:** Build tools are excluded from the runtime image, reducing size by ~200MB compared to a single-stage build.
- **Non-root execution:** The container process runs as an unprivileged user, limiting the impact of container escape vulnerabilities.
- **Image tagging:** Each build produces two tags - the short Git SHA for audit traceability and `latest` for default deployment. The SHA tag enables precise rollback to any previous build.
- **Mutable tags:** The `latest` tag is overwritten on each push. While convenient, this means `latest` is not a stable reference. The SHA-tagged image provides the stable reference for rollbacks.
- **Trivy scanning in CI/CD** (stage 2 of the pipeline) provides an additional layer of vulnerability detection beyond ECR's built-in scanning.
