{{/*
Fail fast on the values that have no safe default. Every one of these is
load-bearing for the security model, so a silent empty is worse than no render.
*/}}
{{- define "tenant-platform.validate" -}}
{{- if not .Values.team }}
{{- fail "team is required - it names every namespaced object for this tenant" }}
{{- end }}
{{- if not .Values.argocdNamespace }}
{{- fail "argocdNamespace is required - it is where the tenant's Argo CD runs" }}
{{- end }}
{{- if not .Values.workloadNamespaces }}
{{- fail "workloadNamespaces is required and must not be empty - it drives BOTH the Roles and the cluster Secret allowlist" }}
{{- end }}
{{- if not .Values.projectName }}
{{- fail "projectName is required - it is the AppProject mapped to the tenant's Harness project" }}
{{- end }}
{{- if has .Values.argocdNamespace .Values.workloadNamespaces }}
{{- fail "argocdNamespace must NOT appear in workloadNamespaces - the instance namespace is not a deploy target, and making it one hands the tenant write access to its own Argo CD" }}
{{- end }}
{{- if and .Values.deployableKinds.enabled (not .Values.deployableKinds.rules) }}
{{- fail "deployableKinds.enabled is true but rules is empty - that would grant the application-controller nothing and the instance would fail every sync" }}
{{- end }}
{{- /*
The two dials interact. rolloutActions lets argocd-server PATCH a Rollout;
deployableKinds decides whether the application-controller may touch the kind at
all. Enabling the first without allowing the kind in the second gives a tenant
who can resume a rollout but whose controller cannot create one - and Argo's
cluster cache enumerates every allowed kind and hard-fails wholesale on the 403,
which surfaces as an instance-wide outage that looks nothing like an RBAC
problem. Catch it at render time instead.
*/}}
{{- if and .Values.rolloutActions.enabled .Values.deployableKinds.enabled }}
{{- $rolloutsAllowed := false }}
{{- range .Values.deployableKinds.rules }}
{{- if and (or (has "argoproj.io" .apiGroups) (has "*" .apiGroups)) (or (has "rollouts" .resources) (has "*" .resources)) }}
{{- $rolloutsAllowed = true }}
{{- end }}
{{- end }}
{{- if not $rolloutsAllowed }}
{{- fail "rolloutActions.enabled is true but deployableKinds.rules does not allow argoproj.io/rollouts - the application-controller could not manage the Rollout that argocd-server is being allowed to patch, and Argo's cluster cache hard-fails on the 403 it gets enumerating the kind. Add rollouts to the rules, or set resource.inclusions and both together." }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "tenant-platform.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: tenant-platform
team: {{ .Values.team }}
{{- end -}}
