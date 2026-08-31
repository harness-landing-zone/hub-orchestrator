# hub-clusters/local-dev/tenants/ — one file per tenant

`bootstrap/tenants-bootstrap.yaml` globs `*/values.yaml` here and turns each
match into two Applications on this hub:

| Application | Chart | What it creates |
| --- | --- | --- |
| `<tenant>-platform` | `charts/tenant-platform` | namespaces + PSA labels, the namespaced Roles that are the real wall, the restricted in-cluster Secret, the AppProject |
| `<tenant>-instance` | `charts/harness-gitops-agent-bootstrap` | the tenant's own namespaced Argo CD, the `HarnessGitopsAgent` CR, and any `HarnessGitopsProjectMapping`s |

Platform runs first and must be Healthy before the instance starts
(`strategy: RollingSync`).

## The agent is created at the scope this file declares

That is the whole point of the file. `harnessAgent.spec.scope` drives it and the
chart refuses to render an inconsistent combination:

| `scope` | Required identity | Mapping rule (`projectMappings[]`) |
| --- | --- | --- |
| `ACCOUNT` | neither org nor project | `orgId` **and** `projectId` required on every entry |
| `ORG` | `orgId` | `projectId` required; `orgId` omitted or equal to the agent's |
| `PROJECT` | `orgId` + `projectId` | must match the agent's org/project |

`gitopsAgent.harness.identity.*` must agree with `harnessAgent.spec.*` — the two
blocks are read by two different charts and the render fails on a mismatch.

Phase 1 of the IDP flow requests **ORG** scope: one Argo CD instance per Harness
organization, mapped into the project the developer picked. `PROJECT` scope
works today too — it is a different value in this file, nothing else.

## Two alphabets, deliberately

Kubernetes names are DNS-safe (`demostests-argo-agent`); the Harness agent
identifier uses underscores (`demostests_argo_agent`). Do not mix them.

## Non-negotiables

Every tenant file must keep these, and the IDP pipeline refuses to write or
update a tenant that loses any of them:

```yaml
gitopsAgent.harness.createClusterRoles: false   # 0 ClusterRoles - the namespace is the wall
gitopsAgent.argo-cd.crds.install:      false    # CRDs are cluster-scoped, the platform owns them
harnessAgent.apiKeySecret.create:      false    # never copy the platform credential into a tenant namespace
```

The agent reads `harness-api-key-secret` from the controller's namespace
(`hga-system`, set by `--api-key-secret-namespace`), so nothing has to exist in
the tenant's namespace.

`argocdNamespace` must NOT appear in `workloadNamespaces`: the platform owns the
instance, and making it a deploy target hands the tenant write access to its own
Argo's config and RBAC. The chart hard-fails if it appears in both.

## Hand-authored vs pipeline-written

Files here are read by Argo as YAML. The IDP pipeline
(`idp_request_argo_instance`) writes them as JSON — valid YAML, and the marker it
uses to know it owns the file. It **fails closed** on a hand-authored tenant
rather than reformatting it, so a file written here by hand stays owned by
whoever wrote it and needs platform review before the pipeline can manage it.
