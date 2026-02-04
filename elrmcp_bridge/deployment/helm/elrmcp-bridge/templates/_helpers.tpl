{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "elrmcp-bridge.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "elrmcp-bridge.fullname" -}}
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
{{- define "elrmcp-bridge.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "elrmcp-bridge.labels" -}}
helm.sh/chart: {{ include "elrmcp-bridge.chart" . }}
{{ include "elrmcp-bridge.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "elrmcp-bridge.selectorLabels" -}}
app.kubernetes.io/name: {{ include "elrmcp-bridge.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "elrmcp-bridge.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "elrmcp-bridge.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "elrmcp-bridge.image" -}}
{{- $registryName := .Values.global.imageRegistry | default "" }}
{{- $repositoryName := .Values.image.repository }}
{{- $tag := .Values.image.tag | default .Chart.AppVersion }}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag }}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag }}
{{- end }}
{{- end }}

{{/*
Create the name of the service to use
*/}}
{{- define "elrmcp-bridge.serviceName" -}}
{{- if .Values.service.nameOverride }}
{{- .Values.service.nameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "elrmcp-bridge.fullname" . }}
{{- end }}
{{- end }}

{{/*
Check if there are explicitly enabled horizontal pod autoscalers
*/}}
{{- define "elrmcp-bridge.hpaEnabled" -}}
{{- if and .Values.autoscaling.enabled .Values.autoscaling.enabled }}
{{- true }}
{{- else }}
{{- false }}
{{- end }}
{{- end }}

{{/*
Check if there are custom metrics defined
*/}}
{{- define "elrmcp-bridge.customMetricsEnabled" -}}
{{- if .Values.autoscaling.customMetrics }}
{{- true }}
{{- else }}
{{- false }}
{{- end }}
{{- end }}

{{/*
Create configmap name
*/}}
{{- define "elrmcp-bridge.configMapName" -}}
{{- if .Values.configMap.nameOverride }}
{{- .Values.configMap.nameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "elrmcp-bridge.fullname" . }}-config
{{- end }}
{{- end }}

{{/*
Create service monitor name
*/}}
{{- define "elrmcp-bridge.serviceMonitorName" -}}
{{- if .Values.monitoring.prometheus.serviceMonitor.nameOverride }}
{{- .Values.monitoring.prometheus.serviceMonitor.nameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "elrmcp-bridge.fullname" . }}-prometheus
{{- end }}
{{- end }}

{{/*
Returns true if the podDisruptionBudget is enabled
*/}}
{{- define "elrmcp-bridge.pdbEnabled" -}}
{{- if .Values.pdb.enabled }}
{{- true }}
{{- else }}
{{- false }}
{{- end }}
{{- end }}