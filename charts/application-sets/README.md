# application-sets — the fleet generator chart

Turns a **values catalogue** into one Argo CD `ApplicationSet` per enabled entry,
so adding an addon to a fleet is a values edit rather than a hand-written file.

It exists because **an ApplicationSet cannot generate ApplicationSets.** Fanning
one catalogue out into N appsets across N clusters is the only job here that
needs a templating layer — everything else Argo does natively.

Everything below was **verified by running the chart** on a throwaway k3d cluster
with upstream Argo CD v3.4.6 (no Harness agent), not read off upstream docs.
Where behaviour surprised us, the surprise is written down.

---

## The one thing to understand first: TWO evaluation stages

This is the source of nearly every confusion with this chart.

| | What happens | What `{{.metadata.annotations.x}}` is |
|---|---|---|
| **Stage 1** | `helm template` renders the chart into ApplicationSet manifests | **literal text.** It is Argo's template language, not Helm's — Helm copies it through untouched |
| **Stage 2** | the ApplicationSet controller resolves the clusters generator and those templates, **once per matched cluster Secret** | evaluated, against that Secret's metadata |

**Helm will happily render something that generates ZERO Applications at stage
2.** A clean `helm template` proves nothing about what a cluster will get.

Two consequences that shape how you use it:

- `mergeValues` and `applicationSetGroup` are **stage 1**, so they can never be
  driven by cluster metadata. Selecting a different catalogue per cluster is
  impossible in one render — hence **one wrapper Application per group** (below).
- Everything in `valueFiles`, `repoURLGit*` and the destination is **stage 2**,
  resolved per cluster.

## The cluster Secret is the only stage-2 input

Every generated ApplicationSet carries `goTemplateOptions: [missingkey=error]`.
Combined with the bare-field form used throughout, that makes a missing key
**fatal to the entire ApplicationSet — not to one Application.**

| Form | Behaviour when the key is absent |
|---|---|
| `.metadata.annotations.addons_repo_url` | **hard error** (also if `annotations` itself is absent) |
| `index .metadata.annotations "x"` | returns empty, no error |

So `index` is the deliberate safety valve for optional values; the bare form is a
hard requirement. **The `{{if .metadata.labels.tenant}}` guard in the default
ladder does NOT make `tenant` optional** — the `if` evaluates the missing key, so
the `if` is what fails.

**Required on every matched cluster Secret:**

```yaml
metadata:
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: np                    # REQUIRED — ladder + generated app label
    tenant: platform                   # REQUIRED — despite the {{if}}
    enable_<addon>: "true"             # per-addon gate (see useSelectors)
  annotations:
    addons_repo_url: https://…         # REQUIRED
    addons_repo_revision: main         # REQUIRED
    addons_repo_basepath: clusters/x   # REQUIRED, and must NOT be empty
```

**Convention: labels select, annotations carry values.** A label cannot hold a
URL — 63 characters.

`addons_repo_basepath` must be non-empty: an empty value renders `$values//…`
(double slash), and an *absent* one kills the ApplicationSet outright.

Selector `matchExpressions` are exempt from all of this — a missing `enable_*`
label simply fails to match. That is the *other* failure mode, and it is silent
in the opposite direction (see Failure modes).

## Values path formula

```
$values/{addons_repo_basepath}/{ladderRung}/{applicationSetGroup}/{chartName}/{valuesFileName|values.yaml}
```

with the three default ladder rungs, **last wins**:

```
{tenant}/defaults
{tenant}/environments/{environment}/defaults
{tenant}/environments/{environment}/clusters/{cluster}      ← wins
```

**The folder is `chartName`, not the component key.** Two catalogue entries
sharing a chart land in the *same* folder and are told apart only by
`valuesFileName`. Verified: `podinfo` and `podinfo-second` both resolved to
`…/podinfo/`, differing only as `values.yaml` vs `second.yaml`.

### ⚠️ `valuesObject` BEATS EVERY LADDER RUNG — silently

Argo applies `valuesObject` **after** `valueFiles`. So anything a catalogue puts
in `valuesObject` is **permanently unoverridable per cluster**, and the attempted
override fails with no error, no warning, and a `Synced/Healthy` Application.

Proven: with `ui.message` set at all three rungs *and* in the catalogue, the
running pod showed the catalogue value; removing only the catalogue's
`valuesObject` made the untouched rung-3 file win immediately.

**Therefore:** put in `valuesObject` only what must NEVER vary. Chart
coordinates, namespace, `releaseName`, selector and syncPolicy belong in the
catalogue; **fleet-wide *values* belong in a ladder `defaults` rung**, or no
cluster can ever correct them. The classic casualty is `kubeProxy` — scrapeable
on EKS, not on k3s.

## Catalogues and groups

A catalogue is a file under `values/`, selected by name:

```yaml
mergeValues:
  monitoring: { use: true }     # reads values/monitoring.yaml
```

A key with no matching file renders **nothing at all, silently** — `_validate.tpl`
turns that into a render failure.

Because `mergeValues` is stage 1, **a group == a wrapper Application**. To run
two groups, apply two Applications that both render this chart with different
`applicationSetGroup` / `mergeValues`:

```yaml
helm:
  valuesObject:
    releaseName: default
    applicationSetGroup: monitoring
    useSelectors: "true"
    globalSelectors: { fleet_member: hub-cluster }
    mergeValues: { monitoring: { use: true } }
```

Group wrappers isolate **stage-1 render** failures only. They do **not** isolate
stage-2 metadata failures — removing one referenced label from one cluster Secret
took down every ApplicationSet in *both* groups at once, because the failing
template lives in the shared ladder. Already-generated Applications are not
deleted, and it self-heals when the label returns.

## Guards (`templates/_validate.tpl`)

This chart's natural failure mode is silence, so four conditions fail the render
instead:

1. a `mergeValues` key with no matching file under `values/`
2. empty `globalSelectors` — would match **every** registered cluster, tenants
   included (override with `allowUnscopedSelector: true`, as the test fixture
   does, since a fixture has no fleet)
3. empty `releaseName` — names would start with a hyphen and every Application
   would be rejected
4. an enabled component with no chart source at all

## Traps

- **`useSelectors` defaults to `"false"`, which DROPS every `enable_*` gate.**
  Verified: with it false, an addon installed onto a cluster carrying no gate
  label at all. Set `"true"` whenever the catalogue uses gates.
- **`useVersionSelectors` defaults `"true"` but is inert** unless a catalogue
  defines `releases:`. None here does. It becomes a silent no-match the day
  someone adds release lanes without labelling every cluster Secret to match.
- **`releaseName` is load-bearing**, not cosmetic: it is both the ApplicationSet
  name suffix and the Application name prefix. Render a branch with
  `releaseName=test` so output cannot collide with what is running.
- **`appSetName` omits `{{.name}}`** from the generated Application name, so two
  clusters collide. Avoid it until fixed.
- **Bump `version:` in `Chart.yaml` for ANY change, including files under
  `values/`** — they compile in via `$.Files.Get`, so a catalogue edit changes
  what renders exactly as much as a template edit does.

## Failure modes, and how to tell them apart

| Symptom | Cause |
|---|---|
| ApplicationSet says *"All applications have been generated successfully"*, **zero Applications exist** | the clusters selector matched nothing. Check the Secret's labels. **Verify with `kubectl get app`, never with appset status.** |
| `failed to execute go template … map has no entry for key "x"` | a referenced label/annotation is missing from a matched Secret. Kills the whole ApplicationSet. |
| Per-cluster values ignored, app still Synced/Healthy | the catalogue set that key in `valuesObject`. See above. |
| Addon installed on a cluster that never opted in | `useSelectors` is `"false"`. |

## Testing it

`helm template` only exercises stage 1. To exercise stage 2 you need a real
ApplicationSet controller — a throwaway k3d cluster with upstream Argo CD is
enough, and needs no Harness agent.

```bash
helm lint --strict . -f test-values.yaml
helm template rn . -f test-values.yaml            # fixture; renders standalone
helm template rn . --set mergeValues.test1.use=true --set globalSelectors.fleet_member=hub-cluster
```

`test-values.yaml`, `values/test.yaml` and `values/test1.yaml` are **executable
documentation — keep them.** After any change, render before and after and show
the only differences are intended.

When installing Argo CD for such a test, apply it with `--server-side`: the
`ApplicationSet` CRD exceeds the 262144-byte annotation limit and a client-side
apply fails with `metadata.annotations: Too long`. If the CRD is missing when the
applicationset-controller starts, its informer never recovers and every git
generator silently returns **zero** results while still reporting success —
restart the controller after installing the CRD.

## Provenance

Forked from `gitops-bridge-dev/gitops-bridge-helm-charts` (`charts/application-sets`,
base 0.3.3) and diverged materially. This copy owns its own version lineage
starting at 1.0.0 — see the comments in `Chart.yaml`.

Cloud-specific machinery has been removed to keep this a generic fleet generator:
the ACK pod-identity template and its `ackPodIdentity`/`enableAckPodIdentity`
wiring, and the AWS catalogues (`ack`, `addons`, `fleet-bootstrap`, `resources`,
`spoke-addons`). Generic-but-currently-unused features (`gitMatrix`,
`environments`, `additionalResources`, `useVersionSelectors`) were kept.
