{{/*
Expand the name of the chart.
*/}}
{{- define "hpc-midas.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hpc-midas.fullname" -}}
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
{{- define "hpc-midas.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hpc-midas.labels" -}}
helm.sh/chart: {{ include "hpc-midas.chart" . }}
{{ include "hpc-midas.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $value := .Values.labels }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- range $key, $value := .Values.additionalLabels }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hpc-midas.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hpc-midas.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ .Values.labels.app }}
{{- end }}

{{/*
Create the name of the deployment
*/}}
{{- define "hpc-midas.deploymentName" -}}
{{- default (include "hpc-midas.fullname" .) .Values.deployment.name }}
{{- end }}

{{/*
Create the name of the service
*/}}
{{- define "hpc-midas.serviceName" -}}
{{- default (printf "%s-svc" (include "hpc-midas.fullname" .)) .Values.service.name }}
{{- end }}
