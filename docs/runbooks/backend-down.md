# Backend down / crash-looping runbook

**Not yet validated by drill** - Step 9.7 will inject the corresponding
failure and fix whatever in here turns out wrong or ambiguous. Treat this as
a reasonable starting point, not a proven procedure.

Covers: `BackendAvailabilitySLOBreach`, `PodCrashLooping`.

## First three commands

```bash
kubectl -n app-dev get pods -l app.kubernetes.io/component=server
kubectl -n app-dev logs -l app.kubernetes.io/component=server --tail=50 --previous
kubectl -n app-dev describe pod -l app.kubernetes.io/component=server | grep -A5 "Last State\|Events"
```

## Decision tree

- **Pods `Running` but availability SLI still low** - the process is up but
  requests are failing (5xx). Check the CloudWatch Logs Insights query below
  for the actual error, not just the symptom.
- **Pods `CrashLoopBackOff`** - `logs --previous` (above) shows the last
  crash's own output, not the current restart attempt's (which may not have
  logged anything yet). Check for a bad config value, a missing/rotated
  secret (`kubectl -n app-dev get externalsecret`), or a migration failure
  (`kubectl -n app-dev logs job/realworld-backend-dev-migrate`).
- **Readiness probe failing, liveness passing** - the process is up but
  can't reach a dependency (most likely RDS - see `db-issues.md`).

## Correlated logs (step 9.2)

CloudWatch Logs Insights, `/aws/containerinsights/realworld-aws-dev-eks/application`:

```
fields @timestamp, level, message, requestId
| filter kubernetes.namespace_name = "app-dev"
| filter level = "ERROR"
| sort @timestamp desc
| limit 50
```

If a specific `requestId` is already known (e.g. from a user report), filter
on it directly instead to get every log line for that one request.

## Dashboard

Grafana → **Service Overview** (`realworld-service-overview`) - availability
SLI, error budget, pod count/restarts all on one screen.

## Escalation / rollback

If a recent deploy caused this: `docs/runbooks/rollback.md` in this repo -
`git revert` the gitops promotion commit, not a manual values edit or
`kubectl rollout undo` (that runbook explains why the latter is actively
counterproductive under Argo's `selfHeal`).
