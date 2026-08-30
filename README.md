# gitops-realworld-example-app

Argo CD manifests and Helm charts for the RealWorld demo on EKS. The full picture — diagram, setup, design decisions, known gaps — lives in [infrastructure-realworld-example-app](https://github.com/Dado555/infrastructure-realworld-example-app)'s README instead of getting duplicated here.

## What's in here

`bootstrap/root-app.yaml` is the one thing Argo actually points at. Everything else gets added by committing a file under `apps/`, never by running kubectl against the cluster.

`apps/` has one Argo Application per thing that gets deployed — backend and frontend, each in dev and prod, plus observability.

The two app charts (`charts/realworld-backend`, `charts/realworld-frontend`) get their values inlined straight into each Application's `valuesObject`, which is what actually deploys. There's also a mirrored copy under `envs/<env>/*-values.yaml` that CI's promotion step and the validate workflow check against — the two are supposed to stay identical, and validate.yml is what keeps them honest.

`charts/observability` is different — it's a wrapper around kube-prometheus-stack plus the CloudWatch exporter, and its values live directly in `values.yaml` instead of being inlined, because there's just too much of it for that to stay readable.

`docs/runbooks/` has one file per alert, plus an incident-response doc and a rollback doc.

## How a commit here actually reaches the cluster

Each app repo's CI builds, tests, scans, pushes to ECR, and — only on a push to its own main — mints a short-lived GitHub App token and pushes a tag/digest bump straight into this repo's dev files. That's the entire dev auto-promotion, no PR involved.

The same CI run also opens (never merges) a PR bumping the prod equivalents. CODEOWNERS requires a review before that can merge, and merging it *is* the prod deploy — nothing else triggers one.

Every PR against this repo runs `validate.yml`: helm lint, helm template, kubeconform, trivy config, all against the rendered manifests.

Argo just polls main and reconciles whatever's there, prune and selfHeal both on. There's no kubectl apply anywhere in this flow — a merged commit is the only way anything reaches the cluster.
