# Rollback runbook

Drilled live against `dev` on 2026-08-29 (Step 8.7). Never run this drill
against `prod`.

## The correct procedure

1. Identify the gitops "image bump" commit that introduced the bad release
   (`git log` on this repo - the promoter bot's commits are titled
   `chore: promote <app> to <sha> [skip ci]`).
2. `git revert <that commit's sha>` (not a manual hand-edit of the values
   files - revert gives you the exact prior tag+digest pair back atomically,
   with a clear audit trail of what happened and why).
3. `git push`. Argo picks this up on its own poll cycle - no manual sync
   needed, and none should be used (see "why not kubectl" below).
4. Watch `argocd app get <app>-dev` (or `kubectl get application <app>-dev -n
   argocd`) for `Synced` / `Healthy` at the reverted revision, and
   `kubectl -n app-dev get pods` for the old digest back on `Running`.
5. Confirm with a real smoke test against the public endpoint, not just pod
   status - a `Running` pod with a still-failing readiness probe is not a
   recovered service.

## Do NOT use `kubectl rollout undo`

Demonstrated live: with the backend already fixed via step 1-5 above,
running `kubectl rollout undo deployment/realworld-backend-dev` (no
`--to-revision`) rolled the *live* Deployment back to the Kubernetes-local
"previous revision" - which was the **broken** image, not a fix. Kubernetes'
own revision history and git's commit history are two different timelines
that can point in opposite directions once GitOps has intervened once.

The damage was real but extremely short-lived: the broken ReplicaSet was
scaled from 0->1 and its pod started, then Argo CD's `selfHeal` scaled it
straight back to 0 **about one second later** (confirmed via
`kubectl get events`: `ScalingReplicaSet ... from 0 to 1` and `... from 1 to
0` a single second apart). Argo watches the live cluster continuously, not
just on a poll interval - manual drift gets corrected almost immediately,
not "eventually." That speed is reassuring for *accidental* drift, but it
means `kubectl rollout undo` is actively useless as a recovery tool here: by
the time you've confirmed it worked, it's already been reverted back to
whatever git says - which might be the broken state you were trying to
escape, if you run it while the incident is still open.

**The only reliable rollback lever for a GitOps-managed app is git.**

## A rollback does not undo a schema migration

Proven concretely, not just asserted: the drilled "broken" release included
a genuinely backward-compatible migration (`V2__add_rollback_drill_marker.sql`,
a nullable `ALTER TABLE users ADD COLUMN`). After the full image revert (old
jar, old behavior, zero code referencing the new column), a direct query
against the live dev database confirmed:

```
flyway_schema_history: version 2, "add rollback drill marker", success=true
information_schema.columns: rollback_drill_marker still present on users
```

Flyway only ever migrates forward; reverting the application image does
nothing to the schema. This is exactly why expand/contract discipline
matters for anything that *isn't* backward-compatible - a genuinely breaking
migration (a column rename or drop, a new NOT NULL with no default) bundled
with a bad release would leave the reverted-to *old* code broken against the
*new* schema, and no `git revert` of the image bump fixes that. This drill
deliberately used a safe, additive migration so the revert would actually
work - a breaking one would have needed a second, hand-written migration to
undo the schema change too, which is precisely the scenario expand/contract
is designed to avoid ever needing.

## What actually broke, and a real gotcha found while fixing it

The deliberately-bad release did **not** cause an outage - worth stating
plainly, since the plan this runbook implements assumed one would happen.
`realworld-backend`'s Deployment uses `maxSurge: 1, maxUnavailable: 0` (Step
7.6): a new pod that never passes readiness is simply never allowed to
replace an old, healthy one. The bad pod sat at `0/1 Running` indefinitely;
the two old pods kept serving all traffic the entire time. `curl` against
the live ALB returned `200` throughout - the zero-downtime rollout strategy
did exactly its job, even against a genuinely bad deploy.

That is not the same as "nothing was wrong." A stuck rollout is still a real
incident:

- The extra surge pod (`limits.cpu: "1"`) sat there consuming capacity
  against `app-dev-quota` (`limits.cpu` hard-capped at `4`) alongside the 2
  healthy backend pods (`2` more) and the frontend pod (`200m`) - `3200m`
  used, `800m` free.
- When the *fix* (the reverted image) tried to sync, its PreSync migration
  Job also needed `limits.cpu: 1` - and there wasn't room. The migrate Job
  sat in a `FailedCreate` retry loop (`exceeded quota`) for several minutes,
  blocking the entire recovery.
- Deleting the stuck pod directly didn't help - its ReplicaSet immediately
  recreated an identical replacement (same broken template, since the
  Deployment spec itself hadn't been updated yet). Scaling the broken
  ReplicaSet to 0 directly didn't hold either - the Deployment controller's
  own rollout accounting overrode it. **The actual fix was a temporary quota
  bump** (`limits.cpu 4 -> 6`), which let every controller (Job, ReplicaSet,
  Deployment, HPA) reconcile normally without being fought individually;
  reverted back to `4` once the deployment settled.

**Lesson for next time**: a stuck rollout on a namespace already near its
CPU quota can block its own fix. If this recurs, check quota headroom
*before* pushing a revert, not after the migrate Job is already stuck.

## Measured recovery time

| Step | Timestamp (UTC) |
|---|---|
| Broken image pushed to gitops (dev promotion) | 2026-08-29T08:22:49Z |
| Fix: `git revert` pushed | 2026-08-29T08:30:18Z |
| Full recovery (Synced/Healthy, correct digest, smoke test passing) | 2026-08-29T08:39:47Z |
| **Elapsed, revert-push to recovery** | **~9m 29s** |

**Decision checkpoint**: is ~9.5 minutes acceptable? For this drill, yes -
but the bottleneck was *not* Argo's poll interval or image pull (both were
fast once unblocked); it was the quota-exhaustion gotcha above, which cost
several of those minutes in manual investigation. With quota headroom
confirmed upfront, the same recovery would likely land closer to 2-3
minutes (Argo poll + a ~20-30s Flyway/context-startup cycle + rollout
settle time), matching Step 8.5/8.6's own promotion timings.

`kubectl rollout undo`'s damage window, separately: under 2 seconds,
self-corrected by Argo without any human action.
