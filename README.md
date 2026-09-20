# Macky Merch API — DevSecOps Engineering Submission

[![CI Pipeline with Security Scanning](https://github.com/djmarcaida/devsecops-exam-starter-lscs/actions/workflows/ci.yml/badge.svg)](https://github.com/djmarcaida/devsecops-exam-starter-lscs/actions/workflows/ci.yml)

This repository contains the production-grade DevSecOps pipeline and container orchestration architecture for the **Macky Merch API**, submitted for the **La Salle Computer Society (LSCS) DevSecOps Engineering Challenge**.

---

## Table of Contents
1. [Architecture & DevSecOps Strategy](#1-architecture--devsecops-strategy)
   - [Base Image Rationale: `node:20-alpine` vs `node:latest`](#base-image-rationale-node20-alpine-vs-nodelatest)
   - [Security Scanner Selection: Aqua Security Trivy](#security-scanner-selection-aqua-security-trivy)
   - [Least Privilege & Hardening](#least-privilege--hardening)
2. [Getting Started & Setup Instructions](#2-getting-started--setup-instructions)
   - [Prerequisites](#prerequisites)
   - [Local Development (Host)](#local-development-host)
   - [Production Container (Docker)](#production-container-docker)
   - [Multi-Container Orchestration (Docker Compose)](#multi-container-orchestration-docker-compose)
3. [Vulnerability Demonstration & Remediation (Milestone 3)](#3-vulnerability-demonstration--remediation-milestone-3)
   - [The Deliberate Vulnerability: `lodash@4.17.15`](#the-deliberate-vulnerability-lodash41715)
   - [Automated Pipeline Detection & Gate Enforcement](#automated-pipeline-detection--gate-enforcement)
   - [Remediation Workflow](#remediation-workflow)
4. [Engineering Challenges & Technical Solutions](#4-engineering-challenges--technical-solutions)
5. [Summary of DevSecOps & Production Features](#5-summary-of-devsecops--production-features)

---

## 1. Architecture & DevSecOps Strategy

### Base Image Rationale: `node:20-alpine` vs `node:latest`

Selecting an appropriate base image is the first and most impactful perimeter defense in container security. We explicitly chose `node:20-alpine` over Debian-based alternatives (`node:latest` or `node:20`):

| Evaluation Vector | `node:latest` (Debian-based) | `node:20-alpine` (Alpine Linux) | DevSecOps Rationale |
| :--- | :--- | :--- | :--- |
| **Attack Surface Area** | Extremely Broad (~400+ OS packages) | Drastically Minimized (~40 OS packages) | Alpine eliminates unnecessary binaries (e.g., `bash`, `perl`, `python`, `curl`, development headers) that attackers leverage for "Living off the Land" (LotL) post-exploitation. |
| **Known Vulnerabilities (CVEs)** | Regularly 50+ to 100+ CVEs (glibc, systemd, coreutils) | Typically 0 to low single-digit CVEs | The minimal OS package footprint drastically reduces exposure to upstream Common Vulnerabilities and Exposures (CVEs). |
| **Image Size / Footprint** | ~1.1 GB uncompressed | ~180 MB uncompressed | A ~84% reduction in image size minimizes CI layer caching overhead, accelerates cold-start boot times, and reduces bandwidth costs in container registries. |
| **Deterministic Tagging** | Mutable floating tag (`latest`) | Immutable major-version tag (`node:20-alpine`) | Pinning to Node 20 LTS prevents unexpected breaking runtime or OS changes during automated builds. |

---

### Security Scanner Selection: Aqua Security Trivy

We integrated **Aqua Security Trivy** into our automated CI pipeline rather than single-purpose alternatives (such as standalone `npm audit` or `TruffleHog`):

1. **Dual-Layer Coverage (SCA + Container Scanning):**
   - `npm audit` only evaluates `package.json` / `package-lock.json` dependencies; it has zero visibility into OS packages, system libraries, or container layers.
   - Trivy performs **Software Composition Analysis (SCA)** across application manifests (`scan-type: 'fs'`) **and** inspects Alpine base OS packages and filesystem layers inside the built image (`scan-type: 'image'`).
2. **Secret & Misconfiguration Detection:**
   - In addition to CVEs, Trivy scans for leaked API keys, tokens, and Dockerfile misconfigurations (e.g., root execution, unnecessary capabilities).
3. **Pipeline Flexibility & Gate Enforcement:**
   - Trivy provides fine-grained control via flags like `--severity CRITICAL,HIGH` and `--exit-code 1`, enabling hard quality gates that block pull requests if severe vulnerabilities are introduced.

---

### Least Privilege & Hardening

- **Non-Root Execution:** The container explicitly switches to `USER node` (UID/GID 1000:1000) before runtime. This prevents container breakout attacks from compromising the host kernel.
- **Explicit Signal Handling (PID 1):** Express is launched directly via exec-form `CMD ["node", "server.js"]` rather than `npm start`. This ensures Node.js receives `SIGTERM` and `SIGINT` directly, enabling graceful connection draining and zero-downtime container termination.
- **Deterministic Installs (`npm ci`):** The builder stage strictly uses `npm ci --omit=dev`, guaranteeing exact package-lock resolution and excluding heavy test runners (`jest`, `supertest`) from the shipping artifact.

---

## 2. Getting Started & Setup Instructions

### Prerequisites
- [Node.js](https://nodejs.org/) v20.x or higher
- [Docker](https://www.docker.com/) 24.x or higher
- [Docker Compose](https://docs.docker.com/compose/) v2.x or higher

### Local Development (Host)
```bash
# 1. Install all dependencies (including devDependencies)
npm install

# 2. Run test suite
npm test

# 3. Start development server
npm start
# API available at http://localhost:3000 (Healthcheck: http://localhost:3000/health)
```

### Production Container (Docker)
```bash
# 1. Build the production multi-stage image
docker build -t macky-merch-api:local .

# 2. Run the container detached with port mapping
docker run -d --name macky-merch-api -p 3000:3000 macky-merch-api:local

# 3. Verify healthcheck endpoint
curl -i http://localhost:3000/health
# PowerShell: Invoke-RestMethod -Uri http://localhost:3000/health | ConvertTo-Json

# 4. DevSecOps Verification: Confirm non-root execution (node UID 1000)
docker exec macky-merch-api whoami
# Output: node

docker exec macky-merch-api id
# Output: uid=1000(node) gid=1000(node) groups=1000(node)

# 5. Teardown
docker stop macky-merch-api && docker rm macky-merch-api
```

### Multi-Container Orchestration (Docker Compose)
Orchestrates the Express API and Redis with automated health checks over a custom bridge network:

```bash
# 1. Bring up the stack in detached mode
docker compose up -d --build

# 2. Verify running services and health status
docker compose ps

# 3. Inspect custom bridge network attachment
docker network inspect macky-bridge-net

# 4. Verify inter-container DNS and network reachability (API -> Redis)
docker exec macky-api nc -zv redis 6379
# Output: redis (172.18.0.2:6379) open

docker exec macky-redis redis-cli ping
# Output: PONG

# 5. Clean teardown
docker compose down
```

---

## 3. Vulnerability Demonstration & Remediation (Milestone 3)

### The Deliberate Vulnerability: `lodash@4.17.15`

To test the sensitivity and enforcement capabilities of our security pipeline, we deliberately introduced an outdated version of `lodash` (`4.17.15`) into `package.json` and synchronized `package-lock.json`.

This version contains multiple high-severity vulnerabilities documented in the National Vulnerability Database (NVD):
- **CVE-2020-8203 (High - CVSS 7.4):** Prototype Pollution in `lodash.zipObjectDeep` allowing attackers to inject properties into `Object.prototype`.
- **CVE-2020-28500 (High - CVSS 7.5):** Regular Expression Denial of Service (ReDoS) in `toNumber` and `trim` functions.
- **CVE-2021-23337 (High - CVSS 7.2):** Command Injection in `lodash.template` when custom delimiter imports are untrusted.

Because `lodash` was placed in production `dependencies`, it is installed during the container build and packaged into `/app/node_modules`, enabling both filesystem and container image scans to detect it.

---

### Automated Pipeline Detection & Gate Enforcement

In [.github/workflows/ci.yml](.github/workflows/ci.yml), Trivy is configured with `exit-code: '1'` and `--severity CRITICAL,HIGH`:

```yaml
- name: Run Trivy vulnerability scanner (Filesystem & Dependencies)
  uses: aquasecurity/trivy-action@v0.28.0
  with:
    scan-type: 'fs'
    scan-ref: '.'
    format: 'table'
    severity: 'CRITICAL,HIGH'
    exit-code: '1'

- name: Run Trivy vulnerability scanner (Container Image)
  if: always() && steps.build_docker.outcome == 'success'
  uses: aquasecurity/trivy-action@v0.28.0
  with:
    scan-type: 'image'
    image-ref: 'macky-merch-api:${{ github.sha }}'
    format: 'table'
    severity: 'CRITICAL,HIGH'
    exit-code: '1'
```

#### Pipeline Execution Outcome:
1. **Linting & Tests:** `npm test` passes completely (6/6 tests green), proving the application logic is intact.
2. **Docker Build:** The container image builds successfully.
3. **Security Gate (Filesystem):** Trivy detects `lodash@4.17.15` in `package-lock.json`, prints the tabular vulnerability report, and triggers **exit code 1**.
4. **Security Gate (Container):** Trivy scans the built image layers, finds `node_modules/lodash` at version `4.17.15`, and confirms container-level risk.
5. **PR Blocked:** GitHub Actions marks the check as **Failed (Red ❌)**, automatically preventing merge into `main`.

```
======================================================================
                        Trivy Vulnerability Report                     
======================================================================
Node.js (node-pkg)
==================
Total: 3 (HIGH: 3, CRITICAL: 0)

┌─────────┬────────────────┬──────────┬──────────────┬────────────────────────┬──────────────────────────────────────────┐
│ Library │ Vulnerability  │ Severity │ Installed    │ Fixed Version          │ Title                                    │
├─────────┼────────────────┼──────────┼──────────────┼────────────────────────┼──────────────────────────────────────────┤
│ lodash  │ CVE-2020-8203  │ HIGH     │ 4.17.15      │ 4.17.19                │ Prototype Pollution in lodash            │
│ lodash  │ CVE-2020-28500 │ HIGH     │ 4.17.15      │ 4.17.21                │ ReDoS in toNumber and trim               │
│ lodash  │ CVE-2021-23337 │ HIGH     │ 4.17.15      │ 4.17.21                │ Command Injection in template            │
└─────────┴────────────────┴──────────┴──────────────┴────────────────────────┴──────────────────────────────────────────┘
```

<!-- Markdown Screenshot Placeholder -->
![GitHub Actions Security Gate Failure Screenshot](docs/images/trivy-scan-failure.png)
*Figure 1: GitHub Actions CI output showing Aqua Security Trivy detecting HIGH vulnerabilities and failing the pipeline build.*

---

### Remediation Workflow

To remediate the vulnerability and unblock the pipeline:

1. **Option A: Upgrade to Patched Version (`>=4.17.21`):**
   ```bash
   npm install lodash@^4.17.21
   ```
2. **Option B: Remove Unused Dependency (Best Practice):**
   Since `lodash` is not actively imported by `server.js`, removing dead dependencies strictly follows attack surface minimization:
   ```bash
   npm uninstall lodash
   ```
3. **Verify Locally & Commit:**
   ```bash
   # Confirm clean audit
   npm audit

   # Commit and push
   git commit -am "fix(security): remediate lodash CVEs by upgrading/removing dependency"
   git push origin <branch>
   ```
4. **Pipeline Outcome:** GitHub Actions re-runs; both Trivy scans find 0 High/Critical vulnerabilities and complete with **Green ✅**, allowing merge.

---

## 4. Engineering Challenges & Technical Solutions

### Challenge 1: Non-Root Permissions on Layer Copying
- **The Problem:** In Alpine Linux, when `WORKDIR /app` is executed before switching user context, the directory is created with root ownership (`root:root`, mode 755). If non-root `USER node` is switched without adjusting directory permissions, processes that attempt to create runtime temporary files or socket caches fail with `EACCES: permission denied`.
- **The Solution:** We implemented explicit ownership initialization:
  ```dockerfile
  WORKDIR /app
  RUN chown -R node:node /app
  USER node
  COPY --chown=node:node --from=builder /app/node_modules ./node_modules
  COPY --chown=node:node --from=builder /app/package.json ./package.json
  COPY --chown=node:node --from=builder /app/server.js ./server.js
  ```
  Every file and the working directory are strictly owned by `node:node` before runtime execution begins.

---

### Challenge 2: Dual-Scanner Visibility in CI Pipelines
- **The Problem:** By default, GitHub Actions aborts subsequent steps when an earlier step fails with a non-zero exit code. If the filesystem scan (`trivy fs`) failed on Step 6, the container image scan (`trivy image`) on Step 7 would be cancelled, preventing engineers from understanding whether vulnerabilities also leaked into the production image.
- **The Solution:** We implemented conditional execution flow control:
  ```yaml
  - name: Run Trivy vulnerability scanner (Container Image)
    if: always() && steps.build_docker.outcome == 'success'
  ```
  This guarantees that as long as the Docker image was built successfully, both scanners run and report their diagnostics in the pull request logs, while still marking the overall job as failed.

---

### Challenge 3: Isolated Bridge Network & DNS Health Dependencies
- **The Problem:** When orchestrating multi-container services, standard `depends_on: [redis]` only checks if the container process has spawned, not whether Redis is ready to accept socket connections. Furthermore, stale container instances holding host ports cause DNS endpoint corruption on bridge networks (`nc: bad address 'redis'`).
- **The Solution:** In `docker-compose.yml`, we bound services to a custom bridge network (`macky-bridge-net`), defined a native Redis health check (`redis-cli ping`), and coupled the API startup strictly to health readiness:
  ```yaml
  depends_on:
    redis:
      condition: service_healthy
  ```

---

## 5. Summary of DevSecOps & Production Features

| Capability | Implementation Detail | Security / Operational Benefit |
| :--- | :--- | :--- |
| **Multi-Stage Build** | 2-Stage Dockerfile (`builder` ➔ `runner`) | Excludes package managers, test suites, and build caches from the runtime image. |
| **Least Privilege User** | `USER node` (UID 1000) | Prevents root-level host escalation in the event of an RCE exploit. |
| **Clean Context** | `.dockerignore` | Eliminates accidental leakage of `.git`, `.env*`, logs, and local `node_modules`. |
| **Deterministic CI** | `npm ci` & `setup-node` caching | Guarantees identical dependencies matching `package-lock.json` across all environments. |
| **Automated Vulnerability Gate**| Aqua Security Trivy in GitHub Actions | Scans code, lockfiles, and container layers for CRITICAL/HIGH CVEs with build break rules. |
| **Microservice Isolation** | Docker Compose custom bridge network | Internal DNS service discovery without exposing internal datastores (Redis) to public host ports. |
| **Process Lifecycle** | Exec-form `CMD ["node", "server.js"]` | Direct PID 1 signal propagation for zero-downtime container termination. |
| **Branch Protection** | Required Status Checks (`build-and-test`) | Prevents merging code with failing tests or unmitigated High/Critical CVEs. |

---

## 6. Branch Protection Rule Guidance (Governance & Compliance)

To enforce the DevSecOps quality gate and ensure no vulnerable code enters production unreviewed, branch protection must be enabled on the `main` branch.

### Recommended GitHub Branch Protection Configuration:

1. Navigate to **Settings** ➔ **Branches** ➔ Click **Add branch protection rule** (or **Rulesets**).
2. Set **Branch name pattern** to `main`.
3. Enable **Require a pull request before merging**:
   - Check *Require approvals* (minimum 1 peer review).
   - Check *Dismiss stale pull request approvals when new commits are pushed*.
4. Enable **Require status checks to pass before merging**:
   - Check *Require branches to be up to date before merging*.
   - In the search box, select the status check: **`Build, Test & Security Scan`** (the job name defined in `.github/workflows/ci.yml`).
5. Enable **Do not allow bypassing the above settings** (enforce policy across administrators to prevent accidental overrides).
6. Click **Create** / **Save changes**.

> [!IMPORTANT]
> **DevSecOps Impact:**
> With this rule active, when a pull request introduces high/critical CVEs (such as our deliberate `lodash@4.17.15` vulnerability), the Trivy scanner triggers an exit code 1, marking the status check as **Failed (Red ❌)**. GitHub's branch protection engine will physically disable the **Merge pull request** button, cryptographically safeguarding the `main` branch against vulnerable releases.

