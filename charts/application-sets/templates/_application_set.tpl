{{/*
Normalise additionalResources to a LIST.

Accepts either shape and always returns a list, so callers never branch:

  additionalResources:              # legacy single-object form, still supported
    path: charts/fleet-secret
    type: ecr-token

  additionalResources:              # list form - multiple extra sources
    - path: charts/fleet-secret
      type: ecr-token
    - path: charts/fleet-secret
      type: grafana-admin

WHY THE LIST EXISTS: one component often needs more than one extra source -
several folders of the SAME chart rendered with different values (that is what
`type` selects, since it becomes a path segment in the valueFiles ladder), or
folders from different charts entirely. The single-object form could express
only one, so a second set of resources meant inventing a whole extra catalogue
component with a duplicate chart entry.

The legacy form is kept working on purpose: the prior-art catalogues in
reference-repos use it, and silently breaking them would make the comparison
worthless.
*/}}
{{- define "application-sets.normaliseAdditionalResources" -}}
{{- $ar := . -}}
{{- if kindIs "slice" $ar -}}
{{- toYaml $ar -}}
{{- else -}}
{{- toYaml (list $ar) -}}
{{- end -}}
{{- end }}

{{/*
Template to generate ONE additional resource's sources.

Takes a single `resource` (one entry of the normalised list) rather than
reaching into $chartConfig.additionalResources, which is what limited this to a
single entry before.
*/}}
{{- define "application-sets.additionalResources" -}}
{{- $chartName := .chartName -}}
{{- $chartConfig := .chartConfig -}}
{{- $valueFiles := .valueFiles -}}
{{- $resource := .resource -}}
{{- $additionalResourcesType := $resource.type -}}
{{- $values := .values -}}
{{- if $resource.path }}
- repoURL: {{ $values.repoURLGit | squote }}
  targetRevision: {{ $values.repoURLGitRevision | squote }}
  path: {{- if eq (default "" $additionalResourcesType) "manifests" }}
    '{{ $values.repoURLGitBasePath }}{{ if $values.useValuesFilePrefix }}{{ $values.valuesFilePrefix }}{{ end }}clusters/{{`{{.nameNormalized}}`}}/{{ $resource.manifestPath }}'
  {{- else }}
    {{ $resource.path | squote }}
  {{- end}}
{{- end }}
{{- if $resource.chart }}
- repoURL: '{{ $resource.repoURL }}'
  chart: '{{ $resource.chart }}'
  targetRevision: '{{ $resource.chartVersion }}'
{{- end }}
{{- if $resource.helm }}
  helm:
    releaseName: '{{`{{ .name }}`}}-{{ $resource.helm.releaseName }}'
    {{- if or $values.globalValuesObject $resource.helm.valuesObject }}
    {{/* Create a fresh copy for this resource only */}}
    {{- $chartValuesObject := dict }}
    {{- if $values.globalValuesObject }}
      {{- $chartValuesObject = deepCopy $values.globalValuesObject }}
    {{- end }}
    {{- if $resource.helm.valuesObject }}
      {{- $chartValuesObject = mergeOverwrite $chartValuesObject $resource.helm.valuesObject }}
    {{- end }}
    valuesObject:
      {{- toYaml $chartValuesObject | nindent 6 }}
    {{- end }}
    ignoreMissingValueFiles: true
    valueFiles:
    {{- /* chartConfig MUST be passed: application-sets.valueFiles dereferences
    $chartConfig.valuesFileName, and omitting it made this a nil-pointer render
    failure. It was never hit because nothing used additionalResources.helm. */}}
    {{- include "application-sets.valueFiles" (dict
      "nameNormalize" $chartName
      "chartConfig" $chartConfig
      "valueFiles" $valueFiles
      "values" $values
      "chartType" $additionalResourcesType) | nindent 6 }}
{{- end }}
{{- end }}

{{/*
Define the values path for reusability
*/}}
{{- define "application-sets.valueFiles" -}}
{{- $nameNormalize := .nameNormalize -}}
{{- $chartConfig := .chartConfig -}}
{{- $valueFiles := .valueFiles -}}
{{- $chartType := .chartType -}}
{{- $values := .values -}}
{{- $valuesFileName := default "values.yaml" $chartConfig.valuesFileName -}}
{{- $applicationSetGroup := default "" $values.applicationSetGroup -}}

{{- with .valueFiles }}
{{- range . }}
{{/* Path with applicationSetGroup if available */}}
{{- if ne $values.repoURLGitBasePath "" }}
- $values/{{$values.repoURLGitBasePath}}
{{- else}}
- $values{{$values.repoURLGitBasePath}}
{{- end }}
{{- if $values.useValuesFilePrefix -}}/{{$values.valuesFilePrefix}}{{- end -}}/{{.}}
{{- if $applicationSetGroup -}}/{{$applicationSetGroup}}{{- end -}}/{{$nameNormalize}}
{{- if $chartType -}}/{{$chartType}}{{- end -}}
{{- if $chartConfig.valuesFileName -}}/{{$chartConfig.valuesFileName}}
{{- else -}}/values.yaml{{- end -}}
{{- end }}
{{- end }}
{{- end }}
