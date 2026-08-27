{{/*
Name helpers for realworld-frontend. Standard helm-create-style boilerplate,
kept here so later steps (7.2 Deployment/Service, 7.4 PDB/ServiceAccount
wiring) have consistent naming/labels to reuse instead of re-deriving them.
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "realworld-frontend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name, truncated to fit Kubernetes name limits.
*/}}
{{- define "realworld-frontend.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "realworld-frontend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "realworld-frontend.labels" -}}
helm.sh/chart: {{ include "realworld-frontend.chart" . }}
{{ include "realworld-frontend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels.
*/}}
{{- define "realworld-frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "realworld-frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Name of the ServiceAccount to use.
*/}}
{{- define "realworld-frontend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "realworld-frontend.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
