{{/*
Expand the name of the chart.
*/}}
{{- define "craftplan.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "craftplan.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "craftplan.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "craftplan.labels" -}}
helm.sh/chart: {{ include "craftplan.chart" . }}
{{ include "craftplan.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "craftplan.selectorLabels" -}}
app.kubernetes.io/name: {{ include "craftplan.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "craftplan.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "craftplan.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Replica count
*/}}
{{- define "craftplan.replicaCount" -}}
{{- if .Values.replicaCount }}
{{- .Values.replicaCount }}
{{- else }}
{{- if eq .Values.global.environment "production" }}
3
{{- else if eq .Values.global.environment "staging" }}
2
{{- else }}
1
{{- end }}
{{- end }}
{{- end }}

{{/*
Helper function for liveness probe
*/}}
{{- define "craftplan.livenessProbe" -}}
{{- if .Values.livenessProbe }}
{{- toYaml .Values.livenessProbe | nindent 8 }}
{{- else }}
{{- if .Values.global.monitoring.enabled }}
httpGet:
  path: /health
  port: {{ .Values.service.port | default 4000 }}
initialDelaySeconds: 30
periodSeconds: 10
timeoutSeconds: 5
failureThreshold: 3
{{- else }}
exec:
  command:
    - /bin/sh
    - -c
    - "exit 0"
{{- end }}
{{- end }}
{{- end }}

{{/*
Helper function for readiness probe
*/}}
{{- define "craftplan.readinessProbe" -}}
{{- if .Values.readinessProbe }}
{{- toYaml .Values.readinessProbe | nindent 8 }}
{{- else }}
{{- if .Values.global.monitoring.enabled }}
httpGet:
  path: /health
  port: {{ .Values.service.port | default 4000 }}
initialDelaySeconds: 5
periodSeconds: 5
timeoutSeconds: 5
failureThreshold: 3
{{- else }}
exec:
  command:
    - /bin/sh
    - -c
    - "exit 0"
{{- end }}
{{- end }}
{{- end }}

{{/*
Helper function for security context
*/}}
{{- define "craftplan.securityContext" -}}
runAsUser: {{ .Values.podSecurityContext.runAsUser | default 1000 }}
runAsGroup: {{ .Values.podSecurityContext.runAsGroup | default 1000 }}
fsGroup: {{ .Values.podSecurityContext.fsGroup | default 1000 }}
{{- end }}

{{/*
Helper function for image pull secrets
*/}}
{{- define "craftplan.imagePullSecret" -}}
{{- if .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.global.imagePullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Helper function for secret name
*/}}
{{- define "craftplan.secretName" -}}
{{- if .Values.global.secretName }}
{{ .Values.global.secretName }}
{{- else }}
{{ include "craftplan.fullname" . }}
{{- end }}
{{- end }}

{{/*
Helper function for configmap name
*/}}
{{- define "craftplan.configMapName" -}}
{{- if .Values.global.configMapName }}
{{ .Values.global.configMapName }}
{{- else }}
{{ include "craftplan.fullname" . }}
{{- end }}
{{- end }}

{{/*
Helper function for pvc name
*/}}
{{- define "craftplan.pvcName" -}}
{{- if .Values.global.pvcName }}
{{ .Values.global.pvcName }}
{{- else }}
{{ include "craftplan.fullname" . }}
{{- end }}
{{- end }}

{{/*
Helper function for metrics path
*/}}
{{- define "craftplan.metricsPath" -}}
{{- if .Values.global.metricsPath }}
{{ .Values.global.metricsPath }}
{{- else }}
/metrics
{{- end }}
{{- end }}