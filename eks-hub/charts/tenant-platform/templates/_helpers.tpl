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
{{- end -}}

{{- define "tenant-platform.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: tenant-platform
team: {{ .Values.team }}
{{- end -}}
