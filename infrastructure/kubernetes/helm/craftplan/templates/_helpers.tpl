#!/usr/bin/env yaml2json
# Helm Chart Helpers for Craftplan Integration
#
# This file contains common template helpers for the Craftplan Integration Helm chart.

{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "craftplan.name" -}}
{{- default .Chart.Name .Values.global.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "craftplan.fullname" -}}
{{- if .Values.global.fullnameOverride -}}
{{- .Values.global.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.global.name -}}
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
{{- define "craftplan.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "craftplan.labels" -}}
helm.sh/chart: {{ include "craftplan.chart" . }}
{{ include "craftplan.selectorLabels" . }}
{{- if .Chart.AppVersion -}}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: craftplan-integration
app.kubernetes.io/component: {{ .Release.Name }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "craftplan.selectorLabels" -}}
app.kubernetes.io/name: {{ include "craftplan.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "craftplan.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "craftplan.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the secret to use
*/}}
{{- define "craftplan.secretName" -}}
{{- default (printf "%s-secrets" .Release.Name) .Values.secrets.name -}}
{{- end -}}

{{/*
Create the name of the configmap to use
*/}}
{{- define "craftplan.configMapName" -}}
{{- default (printf "%s-config" .Release.Name) .Values.configMap.name -}}
{{- end -}}

{{/*
Create the name of the persistent volume claim to use
*/}}
{{- define "craftplan.pvcName" -}}
{{- default (printf "%s-pvc" .Release.Name) .Values.persistence.name -}}
{{- end -}}

{{/*
Create the name of the ingress to use
*/}}
{{- define "craftplan.ingressName" -}}
{{- default (include "craftplan.fullname" .) .Values.ingress.name -}}
{{- end -}}

{{/*
Generate the image pull secret name
*/}}
{{- define "craftplan.imagePullSecretName" -}}
{{- default (printf "%s-image-pull-secret" .Release.Name) .Values.global.imagePullSecrets.name -}}
{{- end -}}

{{/*
Generate the image pull secret
*/}}
{{- define "craftplan.imagePullSecret" -}}
imagePullSecrets:
  - name: {{ include "craftplan.imagePullSecretName" . }}
{{- end -}}

{{/*
Get the environment-specific replica count
*/}}
{{- define "craftplan.replicaCount" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].replicas | default .Values.global.replicas -}}
{{- else -}}
{{- .Values.global.replicas -}}
{{- end -}}
{{- else -}}
{{- .Values.global.replicas -}}
{{- end -}}
{{- end -}}

{{/*
Get the environment-specific resource limits
*/}}
{{- define "craftplan.resources" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].resources | default .Values.global.resources -}}
{{- else -}}
{{- .Values.global.resources -}}
{{- end -}}
{{- else -}}
{{- .Values.global.resources -}}
{{- end -}}
{{- end -}}

{{/*
Get the environment-specific monitoring settings
*/}}
{{- define "craftplan.monitoring" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].monitoring | default .Values.global.monitoring -}}
{{- else -}}
{{- .Values.global.monitoring -}}
{{- end -}}
{{- else -}}
{{- .Values.global.monitoring -}}
{{- end -}}
{{- end -}}

{{/*
Generate the database connection URL
*/}}
{{- define "craftplan.databaseUrl" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].database.url | default .Values.global.database.url -}}
{{- else -}}
{{- .Values.global.database.url -}}
{{- end -}}
{{- else -}}
{{- .Values.global.database.url -}}
{{- end -}}
{{- end -}}

{{/*
Generate the cache connection URL
*/}}
{{- define "craftplan.cacheUrl" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].cache.url | default .Values.global.cache.url -}}
{{- else -}}
{{- .Values.global.cache.url -}}
{{- end -}}
{{- else -}}
{{- .Values.global.cache.url -}}
{{- end -}}
{{- end -}}

{{/*
Generate the storage backend URL
*/}}
{{- define "craftplan.storageUrl" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].storage.url | default .Values.global.storage.url -}}
{{- else -}}
{{- .Values.global.storage.url -}}
{{- end -}}
{{- else -}}
{{- .Values.global.storage.url -}}
{{- end -}}
{{- end -}}

{{/*
Check if a value is true
*/}}
{{- define "craftplan.isTrue" -}}
{{- eq .Values.global.environment "production" -}}
{{- end -}}

{{/*
Check if a value is false
*/}}
{{- define "craftplan.isFalse" -}}
{{- ne .Values.global.environment "production" -}}
{{- end -}}

{{/*
Check if debug mode is enabled
*/}}
{{- define "craftplan.isDebug" -}}
{{- eq .Values.global.environment "dev" -}}
{{- end -}}

{{/*
Generate the health check path
*/}}
{{- define "craftplan.healthPath" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].health.path | default "/health" -}}
{{- else -}}
{{- "/health" -}}
{{- end -}}
{{- else -}}
{{- "/health" -}}
{{- end -}}
{{- end -}}

{{/*
Generate the metrics path
*/}}
{{- define "craftplan.metricsPath" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].metrics.path | default "/metrics" -}}
{{- else -}}
{{- "/metrics" -}}
{{- end -}}
{{- else -}}
{{- "/metrics" -}}
{{- end -}}
{{- end -}}

{{/*
Generate the readiness probe configuration
*/}}
{{- define "craftplan.readinessProbe" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].readinessProbe | default .Values.global.readinessProbe -}}
{{- else -}}
{{- .Values.global.readinessProbe -}}
{{- end -}}
{{- else -}}
{{- .Values.global.readinessProbe -}}
{{- end -}}
{{- end -}}

{{/*
Generate the liveness probe configuration
*/}}
{{- define "craftplan.livenessProbe" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].livenessProbe | default .Values.global.livenessProbe -}}
{{- else -}}
{{- .Values.global.livenessProbe -}}
{{- end -}}
{{- else -}}
{{- .Values.global.livenessProbe -}}
{{- end -}}
{{- end -}}

{{/*
Generate the deployment strategy
*/}}
{{- define "craftplan.deploymentStrategy" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].deploymentStrategy | default .Values.global.deploymentStrategy -}}
{{- else -}}
{{- .Values.global.deploymentStrategy -}}
{{- end -}}
{{- else -}}
{{- .Values.global.deploymentStrategy -}}
{{- end -}}
{{- end -}}

{{/*
Generate the autoscaling configuration
*/}}
{{- define "craftplan.autoscaling" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].autoscaling | default .Values.global.autoscaling -}}
{{- else -}}
{{- .Values.global.autoscaling -}}
{{- end -}}
{{- else -}}
{{- .Values.global.autoscaling -}}
{{- end -}}
{{- end -}}

{{/*
Generate the storage configuration
*/}}
{{- define "craftplan.storage" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].storage | default .Values.global.storage -}}
{{- else -}}
{{- .Values.global.storage -}}
{{- end -}}
{{- else -}}
{{- .Values.global.storage -}}
{{- end -}}
{{- end -}}

{{/*
Generate the logging configuration
*/}}
{{- define "craftplan.logging" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].logging | default .Values.global.logging -}}
{{- else -}}
{{- .Values.global.logging -}}
{{- end -}}
{{- else -}}
{{- .Values.global.logging -}}
{{- end -}}
{{- end -}}

{{/*
Generate the security configuration
*/}}
{{- define "craftplan.security" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].security | default .Values.global.security -}}
{{- else -}}
{{- .Values.global.security -}}
{{- end -}}
{{- else -}}
{{- .Values.global.security -}}
{{- end -}}
{{- end -}}

{{/*
Generate the cost optimization configuration
*/}}
{{- define "craftplan.costOptimization" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].costOptimization | default .Values.global.costOptimization -}}
{{- else -}}
{{- .Values.global.costOptimization -}}
{{- end -}}
{{- else -}}
{{- .Values.global.costOptimization -}}
{{- end -}}
{{- end -}}

{{/*
Generate the network policy configuration
*/}}
{{- define "craftplan.networkPolicy" -}}
{{- if .Values.global.environments -}}
{{- if .Values.global.environments.[.Values.global.environment] -}}
{{- .Values.global.environments.[.Values.global.environment].networkPolicy | default .Values.global.networkPolicy -}}
{{- else -}}
{{- .Values.global.networkPolicy -}}
{{- end -}}
{{- else -}}
{{- .Values.global.networkPolicy -}}
{{- end -}}
{{- end -}}