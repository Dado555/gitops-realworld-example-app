# gitops-realworld-example-app

Argo CD `Application` manifests and Helm charts for the RealWorld demo app on EKS — the GitOps
half of the deployment. For the full architecture (diagram, AWS setup, design decisions, known
gaps), see [infrastructure-realworld-example-app](https://github.com/Dado555/infrastructure-realworld-example-app)'s
README rather than duplicating it here.

## What's here

- `bootstrap/root-app.yaml` — the app-of-apps root. Argo is pointed at this once; every other
  deployable is added later by committing a file under `apps/`, never by running `kubectl`.
- `apps/` — one Argo CD `Application` per deployable: `realworld-backend-dev`,
  `realworld-backend-prod`, `realworld-frontend-dev`, `realworld-frontend-prod`, `observability`.
- `charts/realworld-backend`, `charts/realworld-frontend` — the app Helm charts. Values are
  inlined in each Application's `valuesObject` (what Argo actually deploys) and mirrored in
  `envs/<env>/*-values.yaml` (a reference copy that CI's promotion step and `validate.yml` check
  against — the two are meant to stay identical).
- `charts/observability` — thin wrapper around kube-prometheus-stack plus
  `prometheus-cloudwatch-exporter`. Values live directly in `charts/observability/values.yaml`
  instead of being inlined — too large for that to stay readable.
- `docs/runbooks/` — one runbook per alert (`backend-down.md`, `high-latency.md`,
  `db-issues.md`), plus `incident-response.md` and `rollback.md`.

## How a change here reaches the cluster

- Each app repo's CI (backend/frontend) builds, tests, scans, and pushes to ECR, then — only on
  a push to its own main branch — mints a short-lived GitHub App token scoped to this repo and
  pushes a tag+digest bump straight to `envs/dev/*-values.yaml` and `apps/realworld-*-dev.yaml`.
  That's the entire dev auto-promotion.
- The same CI run opens (never merges) a PR bumping the `envs/prod/*-values.yaml` and
  `apps/realworld-*-prod.yaml` equivalents. `CODEOWNERS` requires review before merge — merging
  that PR *is* the production deploy, nothing else triggers it.
- Every PR against this repo runs `.github/workflows/validate.yml`: `helm lint`, `helm template`,
  `kubeconform`, and `trivy config` against the rendered manifests.
- Argo CD polls `main` and reconciles whatever's there (`prune: true`, `selfHeal: true`). There's
  no `kubectl apply` anywhere in this flow — a merged commit is the only way a change reaches the
  cluster.
