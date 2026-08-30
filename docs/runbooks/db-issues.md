# Database issues runbook

**Not yet validated by drill** - Step 9.7 will inject the corresponding
failure and fix whatever in here turns out wrong or ambiguous. Treat this as
a reasonable starting point, not a proven procedure.

Covers: `RDSStorageOrConnectionsNearLimit` (free storage < 20% of the 20GiB
allocated, or connections > ~80% of the ~112 max_connections this
`db.t4g.micro` instance computes to - both real, not round numbers, see
`charts/observability/templates/alerts.yaml` for the derivation).

## First three commands

```bash
aws rds describe-db-instances --db-instance-identifier realworld-aws-dev-db \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Storage:AllocatedStorage,Class:DBInstanceClass}'
kubectl -n app-dev exec deploy/realworld-backend-dev -- wget -qO- http://localhost:8081/actuator/prometheus | grep hikaricp_connections_active
aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=realworld-aws-dev-db \
  --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 300 --statistics Average
```

## Decision tree

- **Storage low, no autoscaling configured** (confirmed: `MaxAllocatedStorage`
  is unset on this instance) - this does **not** self-heal. Either grow
  `allocated_storage` via Terraform (`terraform/envs/dev/data`, expect a
  short storage-modification window, not downtime for gp3) or find and clear
  what's consuming it (check `flyway_schema_history` growth, orphaned WAL if
  replication was ever configured - it hasn't been, so this is unlikely
  here).
- **Connections near limit, Hikari pool (above) shows low active count** -
  something OTHER than this app's own backend pods is holding connections
  (a stray debugging session, a leaked connection from a one-off Job like
  the database-bootstrap ones from step 8.6). Check
  `pg_stat_activity` directly if you have DB access.
- **Connections near limit, Hikari active count is also high** - the app
  itself is the cause - check for a connection leak (a code path not
  releasing connections) or a genuine traffic spike (cross-reference the
  Service Overview dashboard's request-rate panel).

## Dashboard

Grafana → **Database** - Hikari pool usage (app-side) next to the RDS
CloudWatch panels (instance-side) on the same screen, so a mismatch between
the two is immediately visible.

## Escalation / rollback

Storage/connection exhaustion isn't fixed by a code rollback - it's an
infrastructure change (`terraform/envs/dev/data`) or an operational cleanup,
not `docs/runbooks/rollback.md`.
