{{/*
Fail-fast guards.

This chart's failure mode is SILENCE. It renders happily and then generates
nothing, or generates far too much, and both look identical to "it worked" until
someone inspects the cluster. Every check below corresponds to a way that was
reproduced by rendering, not a hypothetical:

  1. mergeValues naming a file that does not exist -> ZERO ApplicationSets, no
     error. One typo ("monitorring") silently deletes a whole addon group.
  2. globalSelectors empty -> the selector degrades to
     `argocd.argoproj.io/secret-type: cluster`, which matches EVERY registered
     cluster, spokes and tenant instances included. Platform addons would be
     installed onto tenant clusters.
  3. releaseName empty -> the name template renders a LEADING HYPHEN, which is
     not a valid Kubernetes name, so every generated Application is rejected.
  4. A component enabled with no chart source -> the Application renders with an
     EMPTY repoURL and fails inside Argo, a long way from the cause.

Call this AFTER mergeValues has been folded in, so component checks see the
catalogue and not just the caller's overrides.
*/}}
{{- define "application-sets.validate" -}}

{{- /* 1. Every mergeValues key must name a real file under values/. */}}
{{- range $component, $config := .Values.mergeValues }}
  {{- if and $config (eq (toString (default false $config.use)) "true") }}
    {{- $file := printf "values/%s.yaml" $component }}
    {{- if not ($.Files.Get $file) }}
      {{- fail (printf "mergeValues.%s.use is true but %s does not exist in the chart. A mergeValues key must match a FILE NAME under values/. Nothing would render and there would be no error." $component $file) }}
    {{- end }}
  {{- end }}
{{- end }}

{{- /* 2. An unscoped cluster selector is almost never intended. */}}
{{- if not .Values.globalSelectors }}
  {{- if not .Values.allowUnscopedSelector }}
    {{- fail "globalSelectors is empty. Every generated ApplicationSet would select on `argocd.argoproj.io/secret-type: cluster` alone, matching EVERY registered cluster - including spokes and tenant Argo instances - and installing these addons onto all of them. Set globalSelectors (e.g. fleet_member: hub-cluster), or set allowUnscopedSelector: true if a fleet-wide match is genuinely what you want." }}
  {{- end }}
{{- end }}

{{- /* 3. releaseName is load-bearing for naming, not cosmetic. */}}
{{- if not .Values.releaseName }}
  {{- fail "releaseName is empty. Generated names begin '<releaseName>-<cluster>-...', so an empty value produces a LEADING HYPHEN and every Application is rejected as an invalid Kubernetes name. Set releaseName (conventionally 'default'; use a distinct value such as 'test' when rendering a branch so the output cannot collide with what is already running)." }}
{{- end }}

{{- /* 4. Every enabled component needs somewhere to fetch its chart from. */}}
{{- range $name, $cfg := .Values }}
  {{- if and (kindIs "map" $cfg) (hasKey $cfg "enabled") }}
    {{- if eq (toString $cfg.enabled) "true" }}
      {{- if ne (default "" $cfg.type) "manifest" }}
        {{- if not (or $cfg.chartRepository $cfg.path $cfg.resourceGroup) }}
          {{- fail (printf "component %q is enabled but defines no chart source. Set chartRepository (a Helm repo), or path (a directory in the git repo), or type: manifest. Without one the generated Application gets an EMPTY repoURL and fails inside Argo, far from this file." $name) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{- end -}}
