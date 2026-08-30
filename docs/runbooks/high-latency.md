# High latency runbook

**Not yet validated by drill** - Step 9.7 will inject the corresponding
failure and fix whatever in here turns out wrong or ambiguous. Treat this as
a reasonable starting point, not a proven procedure.

Covers: `BackendLatencySLOBreach` (p95 > 500ms for 10m).

## First three commands

```bash
kubectl -n app-dev top pods -l app.kubernetes.io/component=server
kubectl -n observability port-forward svc/observability-kube-prometh-prometheus 9090:9090
# then, in another shell:
curl -s --data-urlencode 'query=histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket{application="realworld-backend"}[5m])) by (le,uri))' http://localhost:9090/api/v1/query
```

The last command breaks p95 down **by endpoint** - the dashboard's own p95
panel is aggregate across all endpoints, so this is the fastest way to find
out whether one specific route is slow or the whole service is.

## Decision tree

- **One endpoint slow, others normal** - likely a slow query or missing
  index for that specific code path. Check `hikaricp_connections_active`
  (Database dashboard) - if it's near `hikaricp_connections_max`, requests
  may be queueing for a pool connection rather than the query itself being
  slow.
- **Every endpoint slow, CPU/memory normal (`kubectl top` above)** - likely
  downstream (RDS) - see `db-issues.md`.
- **Every endpoint slow, CPU near the pod's limit** - genuine load beyond
  what `maxReplicas:2` (HPA) can absorb, or a GC-pressure issue
  (`jvm_memory_used_bytes{area="heap"}` on the Service Overview dashboard).

## Dashboard

Grafana → **Service Overview** - "Latency Percentiles" panel (p50/p95/p99
together makes it obvious whether this is a tail-latency problem or the
whole distribution shifted).

## Escalation / rollback

If a recent deploy correlates with the onset: `docs/runbooks/rollback.md`.
