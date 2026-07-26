# harness-gitops-agent-bootstrap

Bootstrap a Harness GitOps Agent instance, or add a project mapping to an
existing shared agent, using the
[harness-gitops-agent-operator](../../README.md).

For a new instance, one release:

1. Creates a `HarnessGitopsAgent` custom resource (phase one).
2. The controller registers the agent with Harness, writes the agent token into
   the Secret named by `tokenSecretRef`, and creates the optional AppProject
   mapping.
3. On upgrade with `gitopsAgent.enabled=true` (phase two), installs the
   official [Harness gitops-helm chart](https://harness.github.io/gitops-helm/)
   (Argo CD + GitOps agent), which consumes the controller-written token via
   `agent.existingSecrets.agentToken`.

The agent token never appears in values, manifests, or Helm release state —
only the controller and the target-namespace Secret hold it.

For a shared agent, set `harnessAgent.spec.existingAgentIdentifier`, leave
`gitopsAgent.enabled=false`, and omit both token Secret values. The release then
contains only a mapping CR and, when enabled, an AppProject. Deleting that
release removes its mapping but never deregisters the shared agent.

## Prerequisites

- The operator (controller) is installed in the cluster and healthy
  (`charts/harness-gitops-agent-controller`).
- A Harness API key is available to the release. Either pre-create a Secret
  **in the release namespace** with the name from
  `harnessAgent.spec.apiKeySecretRef` (default `harness-api-key-secret`) and
  key `api_key`, or enable `harnessAgent.apiKeySecret.create`. For Harness CD,
  resolve the project secret directly into `harnessAgent.apiKeySecret.value`
  in the external values file. Harness resolves it before Helm rendering, and
  the chart writes it to the Kubernetes Secret `stringData` field. Do not put
  placeholder Harness expressions in values-file comments because Harness
  evaluates those too. Use a least-privilege service-account key and never
  commit or print it.
- One agent instance per namespace: the runtime chart uses fixed component
  names (`gitops-agent`, `argocd-*`), and Harness expects one agent runtime per
  namespace.
- On clusters that already have the Argo CRDs (an existing Argo CD or another
  agent instance), set `gitopsAgent.argo-cd.crds.install=false`.
- When installing more than one instance on the same cluster, give each release
  a unique `gitopsAgent.agent.harnessName` (it names the agent
  ClusterRole/ClusterRoleBinding) and a unique
  `gitopsAgent.harness.identity.agentIdentifier`.

## Install

See [values-example.yaml](values-example.yaml) for a commented starting point.

```sh
helm dependency build .

# Phase one: CR only — the controller registers the agent and writes the token
helm upgrade --install my-agent . \
  --namespace my-agent-ns --create-namespace \
  --values my-values.yaml

# Wait for the controller-written token Secret
kubectl get secret <tokenSecretRef> -n my-agent-ns

# Phase two: install the agent runtime
helm upgrade my-agent . --namespace my-agent-ns \
  --reuse-values --set gitopsAgent.enabled=true --wait
```

## Map a project to an existing shared agent

Install the chart into the existing agent's namespace. The API key Secret is
still required by the controller, but no agent token is created or consumed.

```sh
helm upgrade --install my-project-mapping . \
  --namespace shared-agent-namespace \
  --values my-mapping-values.yaml
```

The AppProject is an ordinary Helm-managed resource in this mode. It is also
managed normally for new instances when `gitopsAgent.argo-cd.crds.install` is
`false`. Only a fresh runtime that installs the Argo CRDs uses the post-install
hook needed to establish CRD ordering.

Uninstalling the release deletes the CR; the controller finalizer then
deregisters the agent from Harness.

## Key values

| Value | Meaning |
|---|---|
| `harnessAgent.spec.scope` | `PROJECT`, `ORG`, or `ACCOUNT`; drives which identity fields are required |
| `gitopsAgent.harness.identity.*` | Account/org/project/agent identifiers, used by both the CR and the runtime |
| `harnessAgent.spec.existingAgentIdentifier` | Existing shared agent to reuse for mapping-only mode; prevents agent creation and deletion |
| `harnessAgent.spec.tokenSecretRef` | Secret the controller writes for a new agent; **must equal** `gitopsAgent.agent.existingSecrets.agentToken`. Omit both in existing-agent mode |
| `harnessAgent.spec.projectMapping` | Optional Argo `AppProject` → Harness project mapping |
| `appProject.sourceRepos`, `appProject.destinations` | Argo tenant boundaries. Replace wildcard defaults for shared-agent tenants |
| `appProject.*ResourceWhitelist` | Resource-kind boundaries for the AppProject; shared tenants should grant only what their workloads need |
| `harnessAgent.apiKeySecret.value` | API-key value supplied only at deploy time from the CD secret manager |
| `harnessAgent.gitSecret.*` | Optional bootstrap-repo registration: renders an Argo CD repository Secret (GitHub App credential) in the release namespace. Accepts individual `githubApp*` fields or one single-line `githubAppJson` blob so the CD platform needs only one secret; private key as base64 (`githubAppPrivateKeyB64`) for CD-injected values |
| `hubCluster.*` | Optional hub self-registration: renders the argocd cluster Secret naming THIS cluster as a labeled Argo destination (default name `hub-cluster`, label `fleet_member: hub-cluster`, plus free-form labels/annotations). A plain resource, patched in place across upgrades |
| `rootAppSet.*` | Optional root ApplicationSet: with the runtime enabled, a post-install hook (after the AppProject) creates an ApplicationSet whose clusters generator stamps one root Application per hub-labeled cluster Secret, syncing a flat git folder (default `gitops/bootstrap` of the `gitSecret` repo) to that hub by name with an explicit `directory` source |
| `gitopsAgent.enabled` | Phase switch: `false` = CR only, `true` = install the runtime |
| `gitopsAgent.agent.harnessName` | Names the agent ClusterRole/Binding; unique per install |
| `gitopsAgent.upgrader.enabled` | Off by default: the upgrader breaks with `existingSecrets` and pinned installs should not self-upgrade |

## CI/CD usage

The repository's CD pipeline uses this chart as its functional end-to-end
test: it installs one PROJECT-scoped and one ORG-scoped instance in separate
namespaces, verifies the agents report CONNECTED/HEALTHY in Harness, then
uninstalls and verifies deregistration. Identity values are injected by the
pipeline at runtime; only this chart and the example values live in the
repository.
