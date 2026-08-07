# 30-Day DevOps Project Roadmap

**Constraints:** 2–4 h/day · Hetzner-primary, AWS as second cloud · weighted toward Terraform, CI/CD, observability, security.

**Design principle:** every day is a distinct scenario and deliverable, but they all operate on the *same* platform. At the end you have one strong repo that tells a story, not 30 disconnected toys. That is what gets you hired.

**Daily rhythm (2.5 h):** `15 min` read the ticket, sketch the design → `100 min` build → `20 min` PR-review with Claude → `15 min` commit \+ write 3 lines in `JOURNAL.md` (what broke, what fixed it, what I'd do differently).

**Pick your app on Day 0\.** Reuse HouseMate or your URL shortener. Do not build a new app — the app is not the point, the platform around it is.

---

## Week 1 — Terraform & IaC foundations

**Day 1 — Provision from zero** *Scenario:* Staging burned down. Recreate it from an empty account. *Ship:* Terraform for Hetzner: server, SSH key, firewall, floating IP, Cloudflare DNS record. `terraform apply` from nothing to a pingable host. *Hook:* Why `count` vs `for_each`?

**Day 2 — Modules & environments** *Scenario:* Sales sold a second environment. Make dev and staging identical but separately sized. *Ship:* Refactor Day 1 into a reusable module \+ per-env tfvars. Zero copy-paste.

**Day 3 — Remote state, locking, drift** *Scenario:* Two engineers ran `apply` simultaneously and corrupted state. *Ship:* Remote backend (Hetzner S3-compatible object storage or AWS S3) with locking. Then manually change a resource in the console and detect \+ reconcile the drift.

**Day 4 — AWS, day one** *Scenario:* A client insists on AWS for a POC. You have never touched it. *Ship:* VPC, public/private subnets, security groups, one t3.micro, one IAM role — all Terraform, all free tier. Set a budget alarm *first*.

**Day 5 — Configuration management** *Scenario:* Five fresh nodes, none of them consistent. *Ship:* Ansible role that takes a bare Hetzner box to your baseline (users, SSH hardening, Docker, monitoring agent). Run it twice — prove idempotency.

**Day 6 — Nobody applies from a laptop** *Scenario:* Ban local `terraform apply`. *Ship:* GitHub Actions: `fmt`/`validate`/`plan` on PR with the plan posted as a comment, `apply` on merge to main. Authenticate to AWS with OIDC — no long-lived access keys.

**Day 7 — Rebuild drill** *Scenario:* Prove the IaC is real. *Ship:* `terraform destroy` everything, then rebuild from zero in under 30 minutes with a written runbook. Time it. This is an interview story.

---

## Week 2 — CI/CD pipeline design

**Day 8 — The image is 1.2 GB and runs as root** *Ship:* Multi-stage Dockerfile, non-root user, slim/distroless base, `.dockerignore`, `HEALTHCHECK`, pinned base digest. Set an image-size budget and hit it.

**Day 9 — Build pipeline** *Scenario:* Builds take 12 minutes. Get under 4\. *Ship:* GH Actions: lint → test → build → tag with semver *and* git SHA → push to GHCR. Layer \+ dependency caching, matrix builds.

**Day 10 — Deployment pipeline** *Scenario:* Deploys are someone SSHing in and running `git pull`. *Ship:* Automated promotion dev → staging → prod with a manual approval gate on prod. Deploy artifact \= the immutable image tag, never a branch name.

**Day 11 — Migrate the pipeline** *Scenario:* "We're consolidating from GitLab CI to GitHub Actions." (Or reverse — pick the direction you know least.) *Ship:* The same pipeline, both platforms, plus a one-page comparison of runners, caching, secrets, and reusable workflows vs templates.

**Day 12 — Bad deploy at 17:00 on Friday** *Ship:* Zero-downtime rolling or blue/green deploy, health-gated, with an automated rollback triggered by a failing post-deploy smoke test. Deliberately deploy a broken build and let the pipeline save you.

**Day 13 — Package it** *Ship:* Helm chart for your app: values per environment, sane defaults, `helm upgrade --atomic --wait`, chart linting in CI, chart published as an OCI artifact. Deploy to kind, then to k3s on Hetzner.

**Day 14 — The migration locked the table** *Scenario:* A schema migration took production down for 8 minutes. *Ship:* Expand/contract migration pattern, migrations as a pre-deploy job (not app startup), backward-compatible for one release. Prove old and new app versions both run against the new schema.

---

## Week 3 — Observability & SRE

**Day 15 — Metrics** *Ship:* Prometheus \+ node\_exporter \+ app instrumented with the RED method (Rate, Errors, Duration). One Grafana dashboard that answers "is the service healthy?" in 5 seconds.

**Day 16 — Logs** *Scenario:* A user reports an error at 14:32. Find their request. *Ship:* Loki \+ Promtail, structured JSON logging, request/correlation IDs propagated end to end. Set a retention policy.

**Day 17 — Traces** *Ship:* OpenTelemetry instrumentation → Tempo or Jaeger. Inject artificial latency somewhere and find the slow span from the trace alone.

**Day 18 — SLOs and error budgets** *Scenario:* "What is our availability target and are we meeting it?" You have no answer. *Ship:* Written SLI/SLO definitions (availability \+ latency), an error-budget dashboard, and multi-window multi-burn-rate alert rules.

**Day 19 — Alert fatigue** *Scenario:* 200 pages a week. Get it under 5\. *Ship:* Alertmanager routing by severity, symptom-based alerts (not cause-based), inhibition and silences, an on-call runbook linked from every alert. Delete every alert nobody would act on at 3am.

**Day 20 — Incident day** ⭐ *Scenario:* Break your own platform without looking — fill a disk, kill a node, OOM a pod, or blackhole the database. *Ship:* Detect it via your alerts, diagnose it via your dashboards, fix it, then write a blameless postmortem: timeline, impact, root cause, action items. **This is the strongest single artifact in your portfolio.**

**Day 21 — Prove you can restore** *Ship:* Automated Postgres backups to object storage, encrypted, with a scheduled *restore test*. Document RTO and RPO, then actually restore into a fresh environment and time it.

---

## Week 4 — Security, secrets, supply chain

**Day 22 — Kill every plaintext secret** *Ship:* SOPS \+ age (or Vault in dev mode) for repo secrets, External Secrets Operator for k8s, OIDC for CI. Then rotate one secret end to end and document how long it took.

**Day 23 — Supply chain** *Ship:* Generate an SBOM (syft), scan images (trivy), fail the build on critical CVEs with a documented exception process, sign images (cosign), and enforce signature verification at admission.

**Day 24 — Shift left** *Ship:* gitleaks as a pre-commit hook *and* in CI, CodeQL or Semgrep SAST, Renovate for dependency updates, branch protection with required checks. Commit a fake AWS key and watch it get blocked.

**Day 25 — Host hardening** *Scenario:* You once got an abuse notice for an exposed Redis. Make that structurally impossible. *Ship:* Ansible hardening role (SSH keys only, nftables default-deny, fail2ban/CrowdSec, unattended upgrades, private network for all datastores). Verify with lynis locally and nmap from outside.

**Day 26 — Assume the pod is compromised** *Scenario:* An attacker has a shell in one container. What can they reach? *Ship:* RBAC least privilege, default-deny NetworkPolicies, Pod Security Standards (restricted), no privileged containers, resource limits everywhere. Then try to escape/pivot and document what stopped you.

**Day 27 — AWS IAM done properly** *Ship:* Roles over users, scoped policies, no wildcards, IAM Access Analyzer clean, MFA, cost budget \+ anomaly alert. Write the "why" next to each policy.

**Day 28 — Threat model** *Ship:* One-page threat model of the whole platform (trust boundaries, top risks, mitigations). Fix the top three findings you find.

---

## Days 29–30 — Make it hireable

**Day 29 — Package the story** *Ship:* Top-level README (what it is, architecture diagram, run-from-zero instructions, monthly cost breakdown), the postmortem from Day 20 linked prominently, a 3-minute screen recording. Pin the repo on GitHub and rewrite your LinkedIn "Projects" section around it.

**Day 30 — Mock interview** *Ship:* Run three drills with your mentor project — (1) system design: "design CI/CD and observability for 50 microservices"; (2) troubleshooting: "the site is slow, you have SSH and Grafana, go"; (3) four STAR stories mined from this month's failures. Score yourself, list the three weakest answers, and put them at the top of next month's plan.

---

## Non-negotiables

- Commit every day, even when it's ugly. The contribution graph is evidence.  
- `JOURNAL.md` entries are your STAR-story raw material. Do not skip them.  
- Destroy cloud resources at the end of each day unless something must persist.  
- If you cannot explain a piece of config in one sentence, you do not own it yet.

