# Incident response / Argo Application unhealthy

**Not yet validated by drill** - Step 9.7 will inject the corresponding
failure and fix whatever in here turns out wrong or ambiguous. Treat this as
a reasonable starting point, not a proven procedure.

Covers: `ArgoApplicationUnhealthy` (an Application's `health_status` is
`Degraded`, or its `sync_status` is `OutOfSync` for longer than normal sync
churn - see the alert's own `for:` duration in
`charts/observability/templates/alerts.yaml`).

This is a different kind of alert than the other four: it fires on the
**deployment pipeline itself** being broken, not on the running application.
The application may be perfectly healthy while this fires (an Application
can go unhealthy for reasons unrelated to user-facing impact - a stuck
PreSync hook, a manifest that no longer applies cleanly).

## First three commands

```bash
kubectl get application -n argocd
kubectl get application <name> -n argocd -o jsonpath='{.status.conditions}'
kubectl get application <name> -n argocd -o jsonpath='{.status.operationState.phase}{"\n"}{.status.operationState.message}'
```

## Decision tree

- **`sync_status: OutOfSync`, no operation running** - a commit landed that
  Argo hasn't reconciled yet, or reconciliation is failing silently. Force a
  refresh: `kubectl patch application <name> -n argocd --type merge -p
  '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'`.
- **`operationState.phase: Running` for an extended period, message
  mentions "waiting for healthy state of"** - a stuck sync-wave deadlock (a
  resource that can never become healthy is blocking the rest of the sync).
  Identify the named resource and consider whether deleting it directly
  would let Argo recreate it correctly (safe for stateless resources; check
  before doing this to anything holding data).
- **`operationState.syncResult.revision` doesn't match the latest commit on
  `main`** - the operation is stale, working off an old commit despite
  `status.sync.revision` looking current. Clearing the stuck operation
  (`kubectl patch application <name> -n argocd --type merge -p
  '{"operation":null}'`) lets the automated-sync controller re-issue a fresh
  one against the current commit.
- **`health_status: Degraded`** - check the specific resource(s) Argo lists
  as unhealthy (`kubectl get application <name> -n argocd -o
  jsonpath='{.status.resources}'`) - this is usually a genuine pod/container
  problem underneath, in which case `backend-down.md` is probably also
  relevant.

## Escalation / rollback

If the Application is stuck mid-sync on a bad commit:
`docs/runbooks/rollback.md`. If it's a GitOps mechanics problem (stuck
operation, hook deadlock) rather than a bad application change, there may be
nothing to roll back - just unstick the sync.
