# hub-orchestrator

Repo for the main hub cluster orchestrator. Private.

This is the desired state and Harness configuration for **bootstrap-0** — the
permanent hub cluster that registers and bootstraps every other cluster. It is
deliberately separate from the demo repos: demo orgs get rebuilt, renamed and
broken during workshops, and none of that should be able to reach this cluster.

## Layout

```
charts/
  harness-gitops-agent-controller/   0.5.0, image v0.3.0
  harness-gitops-agent-bootstrap/    0.8.0, gitops-helm 1.2.7 vendored
harness/
  pipelines/         the day-0 bootstrap pipeline
  services/          Harness Service definitions (what gets deployed)
  environments/      the hub environment
  infrastructure/    deploy targets — connector + namespace per component
values/              this hub's Helm values, one file per component
hub-clusters/        one desired-state root per self-administering hub
terraform/           the GitHub App credential secret, own state
```

**`hub-clusters/<hub>/bootstrap/` is where day 0 hands that hub over to
GitOps.** Each hub's Account Agent uses a fixed `rootAppSet.path` from its own
values or Service Override, so it can reconcile only its hub folder. The root
Application reads that folder flat (`recurse: false`). Adding another hub means
adding its folder and binding its Agent values to that folder; the deployment
pipeline remains cluster-agnostic.

**The `default` AppProject is the admin project.** A Harness agent files each
Application under the Harness project mapped to its AppProject, so
`harnessAgent.spec.projectMapping` pairing `hub_orchistrator` with AppProject
`default` — and `rootAppSet.project` naming that same `default` — is what makes
`hub_orchistrator` the project everything is bootstrapped from. The two sides
have to agree: change one without the other and the root Applications are filed
somewhere else, with nothing failing to say so.

**Charts, values and pipeline live together on purpose.** Each Service fetches
its chart and its values from this repo at ONE pinned commit, so they cannot
drift apart — a values file written for chart 0.8.0 can never be applied to a
different one. The bootstrap chart's `gitops-helm` dependency is vendored under
`charts/` with a `Chart.lock`, so nothing is fetched from the internet at deploy
time, which is the usual reason Native Helm fails on a locked-down cluster.

`hub_bootstrap_cd` takes its **environment and infrastructure as runtime
inputs**, so bootstrapping a second permanent cluster means selecting a
different Infrastructure at run time rather than cloning the pipeline. It also
verifies the outcome rather than trusting Helm: a green `helm upgrade` only means
the pods are steady, and says nothing about whether the controller actually
registered the agent or recorded its project mapping.

## Prerequisites

1. **Kubernetes connector** `hub_bootstrap0` in `harness_controllers/hub_orchistrator`,
   using the in-cluster credentials of the delegate that already runs on the hub.
2. **Secret `hub_orchistrator_token`** — the service-account API key the
   controller uses to register agents. Needs create-agent permission at
   **account scope**, since this hub's job is creating agents in other orgs.
3. **Secret `github_app`** — one single-line JSON object:
   `{"githubAppID":"...","githubAppInstallationID":"...","githubAppPrivateKeyB64":"..."}`
   with the ids as **strings** and the private key base64-encoded. Single-line is
   not stylistic: an expression resolved inside a fetched values file cannot span
   lines, which is exactly why the key is base64 rather than raw PEM.
4. **The GitHub App installed on this repo**, before the agent is deployed — the
   `gitSecret` block registers the Argo repository during the install, and an App
   that cannot read the repo yields a repository error rather than a clean failure.

## Install order

Charts and repo first, then controller, then agent. `hub_bootstrap_cd` does both
in one run — stage `Deploy Controller`, then stage `Deploy Account Agent`.

1. `hub_controller` → namespace `hga-system`. Installs the CRD and the operator.
   It does **not** create the API-key Secret: chart 0.5.0 dropped that template,
   and the bootstrap chart writes it instead — see *Where the API key comes from*
   below.
2. `hub_account_agent` → namespace `hub-account-agent`. The bootstrap chart creates
   the API-key Secret and the CR, the controller registers the agent with Harness
   and writes the token Secret, and the bundled gitops-helm runtime mounts that
   Secret and connects. `account-agent-day0.yaml` ships `gitopsAgent.enabled: true`,
   so this is a single shot, not two passes.

Verify: `MappingReady: True / MappingVerified`, and the agent shows
**CONNECTED / HEALTHY** in the Harness UI. The pipeline's `Verify Agent
Registration` step asserts exactly that, so a green run already means it.

**Why one shot is safe.** The controller re-verifies mapping state against live
Harness on every reconcile rather than trusting its own status, so an agent whose
runtime is not yet CONNECTED/HEALTHY just sits at `MappingReady: False /
AgentNotHealthy` until it comes up, and records the mapping then. Expect that
condition transiently mid-install — it is the controller refusing to record a
mapping it cannot verify, not a failure.

**Splitting it in two is a debugging technique, not the normal path.** Installing
with `gitopsAgent.enabled=false`, confirming `status.agentIdentifier`, then
flipping to `true` cleanly separates a registration problem from a runtime one.
It needs a values override to do: the pipeline has no phase toggle. To install the
controller alone, set the pipeline variable `deploy_agent=false` instead.

## Two things that bite

**`tokenSecretRef` must equal `agent.existingSecrets.agentToken`.** Both come from
the `token_secret` Service variable so they cannot drift, and the chart refuses to
render on a mismatch — deliberately, because a mismatch would run the agent with a
blank token.

**ACCOUNT scope means BOTH `orgIdentifier` and `projectIdentifier` are omitted**,
not set to `""`. The values file leaves them out entirely.

## Where the API key comes from, and why it moved

Controller **0.4.0** created the API-key Secret itself. **0.5.0 does not** — it
dropped that template and now only reads a Secret someone else wrote, in the
namespace named by `manager.apiKeySecretNamespace`. The **bootstrap chart**
creates it instead, via `harnessAgent.apiKeySecret.create`.

So the two charts pair like this, and neither half works alone:

- `controller-day0.yaml` leaves `apiKeySecretNamespace` **empty**, meaning "look
  in each agent CR's own namespace".
- `account-agent-day0.yaml` sets `apiKeySecret.create: true`, which writes the
  Secret into that same namespace.

Set `apiKeySecretNamespace: hga-system` without also arranging for something to
create the Secret there, and the controller waits forever on a Secret nobody
writes.

**Hardening, later:** a copy of the key per agent namespace is not ideal, since
this credential can create agents account-wide. Centralising it in `hga-system`
is better once there is more than one agent here — it just needs an Apply step
or a small chart to put it there.

## Upstream drift to watch

These charts were taken from two different repos — the controller from
`harness-gitops-agent-operator` (0.5.0) and the bootstrap chart from
`hga-bootstrap` (0.8.0), each being the newer of its two copies. Both charts
still exist in both repos at different versions, so they will drift again.
When updating, take each from the repo it is actually developed in rather than
whichever is to hand.
