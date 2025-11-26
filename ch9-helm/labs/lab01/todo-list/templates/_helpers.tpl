{{/*
Expand the name of the chart.
*/}}
{{- define "todo-list.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "todo-list.fullname" -}}
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
{{- define "todo-list.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "todo-list.labels" -}}
helm.sh/chart: {{ include "todo-list.chart" . }}
{{ include "todo-list.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "todo-list.selectorLabels" -}}
app.kubernetes.io/name: {{ include "todo-list.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "todo-list.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "todo-list.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Backend component name
*/}}
{{- define "todo-list.backend.fullname" -}}
{{ include "todo-list.fullname" . }}-backend
{{- end }}

{{/*
Backend selector labels
*/}}
{{- define "todo-list.backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "todo-list.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: backend
{{- end }}

{{/*
Frontend component name
*/}}
{{- define "todo-list.frontend.fullname" -}}
{{ include "todo-list.fullname" . }}-frontend
{{- end }}

{{/*
Frontend selector labels
*/}}
{{- define "todo-list.frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "todo-list.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: frontend
{{- end }}

{{/*
Database component name
*/}}
{{- define "todo-list.database.fullname" -}}
{{ include "todo-list.fullname" . }}-mysql
{{- end }}

{{/*
Database selector labels
*/}}
{{- define "todo-list.database.selectorLabels" -}}
app.kubernetes.io/name: {{ include "todo-list.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
{{- end }}

{{/*
ConfigMap name
*/}}
{{- define "todo-list.configmap.name" -}}
{{ include "todo-list.fullname" . }}-config
{{- end }}

{{/*
Secret name
*/}}
{{- define "todo-list.secret.name" -}}
{{ include "todo-list.fullname" . }}-secret
{{- end }}

{{/*
PVC name
*/}}
{{- define "todo-list.pvc.name" -}}
{{ include "todo-list.fullname" . }}-mysql-pvc
{{- end }}

{{/*
PV name
*/}}
{{- define "todo-list.pv.name" -}}
{{ include "todo-list.fullname" . }}-mysql-pv
{{- end }}

{{/*
StorageClass name
*/}}
{{- define "todo-list.storageclass.name" -}}
{{ include "todo-list.fullname" . }}-mysql-storage
{{- end }}