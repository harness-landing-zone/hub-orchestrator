# eks-hub/ — what the EKS hub owns for itself

The homelab hub bootstrapped this cluster (registration → HGA controller → agent
bundle). From here the EKS hub owns its own tenants, and everything in this
folder is read by the EKS hub's **own** Argo, not by the homelab hub.

Design, rationale and the security model:
[`self-managed-argo-architecture.txt`](self-managed-argo-architecture.txt) —
read it first. It records what was proven live in the NatWest POC
(`HPA-work/eks-natwest-poc`) and what is ours alone.

## Layout

| Path | What |
|---|---|
| `charts/tenant-platform/` | The **platform-authored** half of a tenant: namespaces, the Roles that are the actual security wall, the restricted cluster Secret, and the AppProjects. Tenants never author any of this. |
| `tenants/<team>/values.yaml` | One file per tenant. Adding a tenant is adding a file. |
| `applications/` | The Argo Applications this hub's Argo reconciles. **Read flat** by `bootstrap/fleet-apps.yaml` — anything here is applied, subfolders are ignored. |
| `rollouts-demo/` | Progressive-delivery demo for team1: workload manifests and Harness entities. Not applied directly; reached only through two Applications in `applications/`. |

`applications/` is read as **one** parent Application, so `argocd.argoproj.io/sync-wave`
orders its contents against each other. Current order: `argo-rollouts` (-1) →
`team1-platform` (0) → `team1-instance` (1) → `team1-rollouts-demo` (2).

## The two halves, and why they are separate

Kubernetes enforces this split — it is not a convention:

- **Platform half** (`charts/tenant-platform`) — ServiceAccounts, Roles,
  RoleBindings. A tenant *cannot* apply these. Kubernetes escalation prevention
  rejects any Role granting permissions the writer does not hold, and EKS
  access-policy grants are invisible to that resolver, so even a namespace-admin
  tenant can author no Roles at all.
- **Runtime half** (`applications/*-runtime.yaml`) — the Argo CD workload
  itself. A tenant can apply this with their own credentials.

Keep them in separate Applications so the boundary stays demonstrable.

## Argo CD version — do not change casually

The tenant runtime is pinned to **argo-cd chart 9.0.0**, the same chart version
the platform agent's bundled Argo came from. That is deliberate: Argo CRDs are
cluster-scoped and there is exactly **one** set on this cluster, installed by
the platform bundle. Pinning the tenant to the same chart version means the
tenant runs against CRDs it agrees with.

The tenant chart must always set `crds.install: false`. It does not own them.

## Adding a tenant

1. Copy `tenants/team1/values.yaml` to `tenants/<team>/values.yaml` and edit.
2. Copy the two Applications in `applications/`, repointing `values.yaml`.
3. Onboarding a new workload namespace later is three reviewable changes:
   add it to `workloadNamespaces`, and the Roles plus the cluster Secret
   allowlist follow automatically from that one list.
