# rollouts-demo — progressive delivery through the tenant's own Argo CD

A Harness pipeline that canary-deploys a demo app into `team1-dev` through the
**tenant's** self-managed Argo CD (agent `team1_argo_agent`, PROJECT scope,
`gitopsdemo/selfmanagedargo`), using **Argo Rollouts** for the progressive part.

Read [`../self-managed-argo-architecture.txt`](../self-managed-argo-architecture.txt)
first. This folder assumes the tenancy model it describes and, in two places,
extends it.

## What lives here, and what does not

This folder holds only the two things the delivery chain cannot own: the
**workload manifests** and the **Harness entities**. Everything that is a wall,
an addon or an Argo Application is now part of the chain proper.

```
rollouts-demo/
├── app/                 tenant workload, synced into team1-dev
│   ├── kustomization.yaml
│   ├── rollout.yaml     Argo Rollouts Rollout (NOT a Deployment)
│   └── service.yaml
├── argo/                the Application the pipeline drives - SEEDED by
│   └── team1-rollouts-demo-application.yaml    ../applications/, not by hand
└── harness/             Harness entities, org gitopsdemo / project selfmanagedargo
    ├── environments/    team1_dev, team1_prod
    ├── pipelines/       team1_rollouts_canary
    └── services/        team1_rollouts_demo
```

Where the rest of it went, and why:

| Now lives in | What | Why there |
|---|---|---|
| [`../applications/argo-rollouts.yaml`](../applications/argo-rollouts.yaml) | the argo-rollouts controller + CRDs | Platform-tier addon. Flat in `applications/`, so `bootstrap/fleet-apps.yaml` delivers it like everything else. Sync wave **-1**. |
| [`../applications/team1-rollouts-demo.yaml`](../applications/team1-rollouts-demo.yaml) | seeds the demo Application into `team1-argo` | Wave **2**. Carries the `ignoreDifferences` contract that keeps the pipeline's image override alive. |
| [`../charts/tenant-platform`](../charts/tenant-platform) | the rollout-actions RBAC delta | It is part of WALL 1 and belongs with the other Roles, values-gated on `rolloutActions.enabled`. |
| [`../tenants/team1/values.yaml`](../tenants/team1/values.yaml) | `rolloutActions: true`, and this repo in `sourceRepos` | One file per tenant, and both of these are tenant contract. |

Nothing in this folder is applied by `kubectl` any more. `fleet-apps` reads
`eks-hub/applications/` **flat**, so this folder is invisible to it except
through the two Applications above, which point back into it by path.

---

## Who installs argo-rollouts — the platform, and it is not negotiable

**The platform installs it. The tenant cannot, and no tenant-side configuration
changes that.**

Three independent walls each refuse the install on their own:

1. **CRDs are cluster-scoped.** `rollouts.argoproj.io` and four siblings
   (`analysisruns`, `analysistemplates`, `clusteranalysistemplates`,
   `experiments`) are `CustomResourceDefinition` objects. Rendering chart
   `argo-rollouts:2.41.1` with `clusterInstall=false` **and**
   `installCRDs=true` still produces 5 CRDs — there is no namespaced CRD, and
   namespaced mode does not avoid them.
2. **The tenant's Argo holds zero ClusterRoles.** `createClusterRoles: false` in
   `../tenants/team1/values.yaml` drops all three. A cluster-scoped write needs a
   ClusterRoleBinding the tenant does not hold and cannot create — Kubernetes
   escalation prevention refuses to let an identity grant what it does not have,
   and EKS access-policy grants are invisible to that resolver.
3. **Policy agrees with enforcement.** AppProject `team1` sets
   `clusterResourceWhitelist: []` and the `team1-in-cluster` Secret sets
   `clusterResources: "false"`.

A tenant attempting it gets `Forbidden`, which is the PASS condition in section
8 of the architecture doc, not a defect.

### What RBAC the rollouts controller needs, and whether it breaks confinement

As configured (`clusterInstall: true`, `createClusterAggregateRoles: false`) the
render is **1 ClusterRole + 1 ClusterRoleBinding** — the three aggregate-to-
view/edit/admin roles are off because this cluster binds tenants through
platform-authored namespaced Roles, so aggregation grants nothing. The working
ClusterRole grants, cluster-wide:

| Resource | Verbs | Why |
|---|---|---|
| `argoproj.io` rollouts (+ `/status`, `/finalizers`) | get list watch update patch | the object it drives |
| `argoproj.io` analysisruns, experiments | full | analysis / experiment support |
| `apps` replicasets | full | how a canary is actually performed |
| `apps` deployments, podtemplates | get list watch update | `workloadRef` support |
| core services | get list watch patch create delete | canary/stable/active/preview selector patching |
| core pods | list update watch, `pods/eviction` create | restart |
| core secrets | get list watch | analysis templates that reference secrets |
| core configmaps | get list watch create update | |
| core events | create update patch | |
| `networking.k8s.io` ingresses, `networking.istio.io`, `split.smi-spec.io`, `getambassador.io` | create/get/list/watch/update/patch | traffic routers (unused here) |
| `batch` jobs | full | job-metric analysis |
| `coordination.k8s.io` leases | create get update | leader election |

**Does that conflict with the tenant confinement model? No — and the distinction
matters.** The model confines what the **tenant** can cause to happen. A
platform-owned controller with cluster privilege is the same category as
kube-controller-manager or the CSI driver: the tenant does not control it,
cannot reconfigure it, and cannot make it act outside `team1-dev` /
`team1-prod`, because the only Rollout objects the tenant can create are the
ones its own Argo can write — and that Argo is confined to those two namespaces
by Roles it cannot author. Walls 1, 2 and 4 are untouched.

What genuinely changes is the **trusted-component list**: it grows by one, and
that component can read Secrets in every namespace. State it, do not hide it.

### The narrower option, and what it costs

`clusterInstall: false` runs the controller with `--namespaced` and swaps the
ClusterRoles for a single namespaced Role + RoleBinding (verified by rendering
the chart both ways). But:

- `--namespaced` restricts the controller to **the namespace it runs in**. There
  is no multi-namespace list flag, so `team1-dev` and `team1-prod` need **one
  controller deployment each**.
- Those Roles must still be **platform-applied** — a tenant cannot author a Role
  either, for exactly the same escalation-prevention reason.
- The CRDs are still cluster-scoped and still platform-owned.

So namespaced mode reduces the controller's blast radius to one namespace at the
cost of N controller deployments and N more platform-authored RBAC bundles. It
does **not** move ownership to the tenant. Cluster-wide is the default here
because the CRD half is unavoidable anyway, and a second half-measure buys less
than it costs on a POC cluster with the node-headroom concern already recorded
as Q4.

---

## The second dependency nobody expects: rollout ACTIONS need extra RBAC

Now folded into the chart as `rolloutActions.enabled` (default **false**, set
**true** for team1). This is the reasoning it encodes.

The GitOps Rollout step's `autoRolloutAction` values (`promote-full`, `resume`,
`retry`, `abort`, `restart`) are exactly Argo CD's built-in resource actions for
`argoproj.io/Rollout`. Traced in argo-cd `v3.3.10` (the version this cluster
runs):

- `server/application/application.go:2593` `RunResourceActionV2` runs the Lua
  action and calls `s.patchResource(ctx, config, …)`.
- `patchResource` (≈ line 2708) patches the **status subresource first**, then
  the spec.
- `config` is the destination cluster's rest.Config. For `team1-in-cluster`
  (`https://kubernetes.default.svc`, no credential material) that resolves to
  the in-cluster ServiceAccount of the process running the code — and that
  process is **argocd-server**.

The base `team1-argocd-server` Role grants `get/list/watch` on `*`, `pods/log`
get, and `pods` delete. **No patch verb.**

Consequence, and it is a nasty failure shape: every *wait* succeeds (waits read
the application-controller's cached resource tree and need no extra RBAC), and
then the first *action* 403s. The pipeline gets all the way to
`Suspended / CanaryPauseStep` and dies on `resume`.

With the flag on, the chart appends one rule to that same Role, in the workload
namespaces only:

```yaml
  - apiGroups: ["argoproj.io"]
    resources: ["rollouts", "rollouts/status"]
    verbs: ["get", "patch"]
```

`patch` is the entire delta — `get` is already covered by the wildcard read rule
above it. This grants argocd-server strictly less than the
application-controller beside it already holds (`*`/`*`/`*` in the same
namespace). No new Role, no new RoleBinding, no new namespace, no cluster-scoped
object, no wall moved.

The chart hard-fails the render if `rolloutActions` is on while
`deployableKinds` is on but does not allow `argoproj.io/rollouts` — that
combination gives a tenant who can resume a rollout their controller may not
manage, and Argo's cluster cache hard-fails wholesale on the 403 it gets
enumerating the kind.

---

## Who creates the demo Application, and the trap in the answer

The Application must end up in **the tenant's** Argo: namespace `team1-argo`,
AppProject `team1`, destination `team1-in-cluster`/`team1-dev`. The obvious move
— drop it flat in `../applications/` — is **wrong**, and silently so.

`bootstrap/fleet-apps.yaml` syncs that directory with `selfHeal: true`. The
pipeline's `UpdateGitOpsApp` step writes `spec.source.kustomize.images` onto the
Application object. A self-healing parent reverts that within seconds: green
step, green sync, old image still running.

So it is delivered one level down, by
[`../applications/team1-rollouts-demo.yaml`](../applications/team1-rollouts-demo.yaml),
which declares the mutable fields as not-its-business:

- `ignoreDifferences` on `/spec/source/kustomize` and
  `/spec/source/targetRevision` — the parent never sees the pipeline's write as
  drift, so selfHeal never fires on it;
- `RespectIgnoreDifferences=true` — a sync that runs for some *other* reason (a
  real git change) leaves those fields alone instead of re-applying the git
  value over them.

Both are required: the first stops revert-on-drift, the second stops
revert-on-sync. It is also the only Application in the chain **without**
`ServerSideApply`, deliberately — SSA would make Argo the field manager for the
one field we have just declared we do not own.

Everything else about the Application stays declarative and self-healing, which
is the point of doing it this way rather than creating it by hand.

### The repo access decision, which is still open

The demo Application sources **this repo**, which is private.
`https://github.com/harness-landing-zone/hub-orchestrator.git` is now in the
tenant AppProject's `sourceRepos`, so it passes admission — but **listing a repo
permits it, it does not grant access**. The tenant's Argo still has no
credential for it.

Do **not** close the gap with the platform's `bootstrap-repo` credential: that
is read access to the entire monorepo, and it is risk R3 in the architecture
doc. The clean answers are a dedicated demo repo, or a repo-scoped deploy key
registered as a Harness GitOps Repository in `gitopsdemo/selfmanagedargo`.

---

## Why canary, not blue-green

Canary, replica-based, no traffic router.

- **Blue-green needs `activeService` + `previewService`, and the controller
  patches Service selectors to cut over.** Basic canary needs neither: one
  Service selects both ReplicaSets and kube-proxy splits traffic by pod count,
  so `setWeight: 25` moves real traffic with nothing but ReplicaSet arithmetic.
- **Traffic-managed canary is off the table anyway.** It needs an ingress
  controller or a service mesh; both are cluster-scoped installs, and this
  tenant holds zero ClusterRoles. Basic canary is the only progressive strategy
  that works *entirely inside* the confinement model.
- **Blue-green doubles the pod count** for the duration of the cutover. Q4 in
  the architecture doc already flags node headroom for two Argo runtimes on one
  cluster.
- **Canary gives graded gates; blue-green gives one.** Two indefinite
  `pause: {}` steps become two pipeline control points where verification, an
  Approval step or a smoke test can sit. That is the entire point of driving
  progressive delivery from a pipeline instead of letting the controller
  self-promote.

The Rollout uses `pause: {}` (indefinite), never `pause: {duration: …}`. A timed
pause self-promotes and reduces the pipeline to a spectator.

---

## The Harness entities, and the one that has no YAML

`harness/` mirrors the repo-root `harness/` layout, but for a **different org
and project**: these are `gitopsdemo/selfmanagedargo`, while the root folder is
`harness_controllers/hub_orchistrator`. Do not mix them.

| File | Entity | Note |
|---|---|---|
| `harness/services/team1_rollouts_demo.yaml` | Service | `gitOpsEnabled: true`, `spec: {}`. No Release Repo manifest — see below. |
| `harness/environments/team1_dev.yaml` | Environment | PreProduction. Used by the pipeline. |
| `harness/environments/team1_prod.yaml` | Environment | Production. Declared to match `workloadNamespaces`; no stage targets it yet. |
| `harness/pipelines/team1_rollouts_canary.yaml` | Pipeline | The canary driver. |

**There is no Infrastructure Definition, and looking for one is the mistake.**
In a GitOps stage the third element of the service/environment/cluster triple is
a **GitOps Cluster**, referenced from the stage as:

```yaml
environment:
  environmentRef: team1_dev
  deployToAll: false
  gitOpsClusters:
    - identifier: team1incluster
      agentIdentifier: team1_argo_agent
```

The UI labels that selector "Infrastructure", which is where the confusion comes
from. `infrastructureDefinition` is a CD-stage concept: it names a delegate, a
connector and a namespace so Harness can push. In GitOps nothing is pushed, so
there is nothing to define.

Pinned rather than `deployToAll: true` on purpose — `deployToAll` targets
whatever clusters happen to be attached to the environment, so attaching a
second one later silently widens the stage. Naming it binds the stage to the
restricted destination, which is WALL 2.

**The GitOps Cluster itself is the one entity with no importable YAML.** It is
created through the UI (Environment → GitOps Clusters → + Cluster) or the GitOps
API and attached to the environment there. Importing the environment file alone
gives you an environment with zero clusters and a stage that cannot resolve one.

When you create it, **check what Harness linked**: it can create a cluster entry
of its own instead of adopting the restricted `team1-in-cluster` Secret already
in the namespace, and an unrestricted duplicate is a hole straight through WALL
2. It adopted ours — keep it that way.

---

## Which Harness GitOps steps are used, and which were rejected

Used:

| Step | Role |
|---|---|
| `UpdateGitOpsApp` | sets `kustomize.images` on the Application — no Git write. Limit: **once per stage**. |
| `GitOpsSync` | the actual deployment; this is what starts the rollout. |
| `GitOpsRollout` ×2 | wait for `Suspended`/`CanaryPauseStep`, then `resume`. |
| `GitOpsRollout` ×1 | wait for `Healthy` after full promotion. |
| `GitOpsRollout` (rollback) | `abort` — scales the canary to zero, stable keeps serving. |

Rejected, with reasons:

- **`GitOpsUpdateReleaseRepo` + `MergePR`** — the canonical PR-pipeline pair, but
  Update Release Repo *requires a Release Repo manifest on a GitOps service* and
  a Git connector with **push** rights, and it would commit a demo image tag
  into the private platform monorepo on every run. `UpdateGitOpsApp` achieves the
  same image change with none of that. **Trade-off, stated honestly:** the
  desired image then lives in the Application spec rather than in Git, so it is
  not reconstructible from the repo alone. If that matters more than the blast
  radius, swap in `GitOpsUpdateReleaseRepo` → `MergePR` → `GitOpsSync` against a
  dedicated app repo (not this monorepo) and give that service a Release Repo
  manifest first.
- **`GitOpsFetchLinkedApps`** — only discovers apps generated by an
  **ApplicationSet**. This is a standalone Application; the step would fail
  because neither Deployment Repo details nor ApplicationSet references are
  configured on the service.
- **`GitOpsGetAppDetails`** — useful, but gated behind the
  `GITOPS_GET_APP_DETAILS_STEP` feature flag. Not included so the pipeline saves
  and runs without a support ticket. Add it between sync and the first rollout
  gate if the flag is on.
- **`GitOpsRollback`** — rolls the *Application* back to a previous sync
  revision. For a canary that is the wrong lever: the stable ReplicaSet never
  went away, so `abort` is instant and touches nothing else. Kept as a manual
  escape (hence `revisionHistoryLimit: 5` on the Application).

---

## Order of operations

**Feature flag first.** `CDS_GITOPS_ENABLE_ROLLOUTS_PIPELINE_UX` must be enabled
on account `qIYsos1ZQO6fJMG1Ip6KJA`, or the GitOps Rollout step does not exist in
the step library.

**Cluster side — one commit, then let the chain run.** Everything below is
delivered by `fleet-apps-eks-hub` from `eks-hub/applications/`, in sync-wave
order, with no `kubectl` at any point:

| Wave | Application | Delivers |
|---|---|---|
| -1 | `argo-rollouts` | controller + 5 CRDs |
| 0 | `team1-platform` | namespaces, Roles (**incl. the rollout-actions patch rule**), cluster Secret, AppProjects |
| 1 | `team1-instance` | the tenant's Argo CD + Harness agent |
| 2 | `team1-rollouts-demo` | the demo Application into `team1-argo` |

Waves are enforcement here, not documentation: these four are resources of one
parent Application, so Argo will not start a wave until the previous one is
Healthy.

Verify after: `kubectl get crd rollouts.argoproj.io`,
`kubectl -n argo-rollouts get deploy argo-rollouts`,
`kubectl -n team1-dev get role team1-argocd-server -o yaml`,
`kubectl -n team1-argo get application team1-rollouts-demo`.

**Then the open decision:** give the tenant's Argo a read credential for whatever
repo the demo Application sources (see above). Until then the Application exists
and cannot sync.

**Harness side — by hand, in this order.** These are live changes and this
folder does not make them:

1. Import `harness/services/team1_rollouts_demo.yaml`.
2. Import both files in `harness/environments/`.
3. Create the GitOps **Cluster** `team1incluster` on agent `team1-argo-agent`
   and attach it to `team1_dev`. Confirm it adopted the restricted
   `team1-in-cluster` Secret rather than creating an unrestricted one.
4. Confirm the GitOps **Application** `team1-rollouts-demo` is visible in
   `gitopsdemo/selfmanagedargo` — it arrives through the `team1` AppProject
   mapping, so it should already be there once the agent is healthy.
5. Import `harness/pipelines/team1_rollouts_canary.yaml`.

Steps 3–5 fail in confusing ways if done out of order: the pipeline's
`gitOpsClusters` reference will not resolve without the cluster, and
`UpdateGitOpsApp` cannot find an Application that has not surfaced yet.

---

## How to run

1. Sync the Application once so the Rollout exists and is `Healthy` at the
   baseline tag (`blue`). A first rollout has no stable version to canary
   against, so it goes straight to 100% — that is Argo Rollouts behaving
   correctly, not the pipeline being skipped.
2. Run **Team1 Rollouts Canary** with `image_tag` = anything other than the
   current tag (`green` is the default).
3. Watch it:
   ```bash
   kubectl argo rollouts get rollout rollouts-demo -n team1-dev --watch
   kubectl -n team1-dev port-forward svc/rollouts-demo 8080:80   # visual split
   ```
   Expected: 25% → step pauses → pipeline resumes → 50% → pauses → resumes →
   100% → `Healthy`.
4. Prove the rollback path: run again with `image_tag=bad-green`. Those pods
   never pass readiness, the rollout never reaches a pause, the first gate times
   out (`failOnTimeout: true`), the stage rolls back, and `abort` returns 100%
   of traffic to the stable version.

---

## Traps already paid for

- **The image name in `rollout.yaml` must have NO `docker.io/` prefix.**
  Kustomize matches image overrides on the image name string *exactly* as
  written in the manifest. `UpdateGitOpsApp` sends
  `argoproj/rollouts-demo:<tag>`, so a manifest saying
  `docker.io/argoproj/rollouts-demo` makes the override a **silent no-op** —
  step green, sync green, old image still running. Reproduced and fixed here:

  ```
  manifest docker.io/argoproj/rollouts-demo + override argoproj/rollouts-demo
      -> image: docker.io/argoproj/rollouts-demo:blue        (unchanged)
  manifest argoproj/rollouts-demo          + override argoproj/rollouts-demo
      -> image: argoproj/rollouts-demo:yellow                (applied)
  ```

  If you ever change the image, change `rollout.yaml`, `kustomization.yaml`
  `images[].name` and the pipeline's `kustomize.images` **together**.
- **A self-healing parent above the demo Application breaks the pipeline
  silently.** See "Who creates the demo Application" — `ignoreDifferences` +
  `RespectIgnoreDifferences=true` are both load-bearing, and removing either
  produces green steps and an unchanged image.
- **`waitTillHealthy: false` on the sync step is load-bearing.** The rollout
  parks at its first pause almost immediately, which Argo CD reports as
  `Suspended`, never `Healthy`. A sync told to wait for healthy burns its whole
  timeout on correct behaviour and fails before any rollout step runs. Waiting
  for `Healthy` is the *last* step's job.
- **`healthMessage: CanaryPauseStep` is not decoration.** `Suspended` alone also
  matches a manually paused rollout. Argo Rollouts writes the pause condition
  reason into `status.message`, and Argo CD's Rollout health check surfaces
  `status.message` verbatim. `healthMessage` supports regex if you need to widen
  it.
- **`ServerSideApply=true` on the argo-rollouts Application — for the right
  reason.** The usual justification (the Rollout CRD blows the 262144-byte
  `last-applied-configuration` limit) does **not** hold for chart 2.41.1:
  measured, the largest CRD serialises to 69,424 bytes, because argo-rollouts
  ships description-stripped CRDs. Keep SSA anyway — it avoids the annotation
  entirely, which is what protects the next chart bump.
- **Do not `prune` the argo-rollouts Application.** Pruning deletes the CRDs, and
  deleting a CRD deletes every Rollout object on the cluster with it — across
  every tenant. Same reasoning as `applications/team1-instance.yaml`.
- **Actions are state-dependent.** `resume` is unavailable when not paused;
  `abort`/`retry` are unavailable once fully promoted; `promote-full` is
  unavailable when there is nothing left to promote. An unavailable action fails
  the step — which is why the rollback `abort` ignores its own failure.
- **If `deployableKinds.enabled` is ever turned on** in
  `../tenants/team1/values.yaml`, the allowlist must include
  `argoproj.io/rollouts` **and** the matching `resource.inclusions` must go into
  the tenant's `argocd-cm`. Argo's cluster cache enumerates every kind in its
  allowed namespaces and hard-fails the whole cache on a 403. The chart now
  refuses to render that combination, so you get a clear error instead.

---

## Not verified here — verify live before trusting

- **The `team1-argocd-server` patch requirement.** The reasoning is traced
  through argo-cd v3.3.10 source, not observed on this cluster. Prove it the
  cheap way: set `rolloutActions.enabled: false` in
  `../tenants/team1/values.yaml`, let it sync, run the pipeline and confirm the
  first `resume` fails with `Forbidden`; then set it back. `Forbidden` = RBAC
  denied; `Unauthorized` = credential rejected.
- **Which identity Harness uses for the rollout action.** If Harness routes the
  action through the *application-controller* rather than argocd-server, the
  extra rule is harmless and unnecessary. The test above settles it either way.
- **`docker.io/argoproj/rollouts-demo` running as UID 1000.** The pod spec is
  written for PSA `restricted` (`runAsNonRoot`, UID 1000). If the pods
  `CrashLoopBackOff` on startup, drop `runAsUser`/`runAsGroup`/`fsGroup` and
  keep the rest — `team1-dev` only *enforces* `baseline`.
- **argo-rollouts v1.9.1 on Kubernetes 1.36.** Chart 2.41.1 is the newest
  published version, declares no `kubeVersion` constraint, and renders clean at
  `--kube-version 1.36.0` using only GA APIs. But v1.9.1 builds against
  `k8s.io/client-go v0.34.1` — two minors behind this cluster. Nothing newer
  exists to move to; watch for CRD/API surprises on first install.
- **`agentIdentifier` inside `gitOpsClusters`.** It appears in Harness's own
  exported pipeline YAML in the docs, but is absent from `ClusterYaml` in
  `harness-schema/v0/pipeline.json`. The schema does not forbid extra keys, so it
  validates — but if Harness ever rejects it, drop to `identifier` alone and let
  the environment's single attached cluster disambiguate.
- **Whether `RespectIgnoreDifferences` behaves as documented on this Argo
  build.** The contract is right in principle; confirm it by running the pipeline
  twice and checking that `spec.source.kustomize.images` on
  `team1-rollouts-demo` survives a parent refresh.
