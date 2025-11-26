# Todo List Helm Chart 리팩토링 완벽 가이드

## 목차
1. [프로젝트 개요](#프로젝트-개요)
2. [리팩토링 전후 비교](#리팩토링-전후-비교)
3. [핵심 개념 설명](#핵심-개념-설명)
4. [실전 사용법](#실전-사용법)

---

## 프로젝트 개요

### 목적
하드코딩된 Kubernetes 매니페스트를 **재사용 가능한 Helm 차트**로 변환

### 주요 달성 목표
- ✅ 여러 환경(dev/staging/prod)에서 동일 차트 사용
- ✅ 컴포넌트별 선택적 배포 (backend/frontend/db)
- ✅ 동적 이름 생성으로 다중 릴리스 지원
- ✅ Kubernetes 표준 레이블 자동 적용
- ✅ 설정 값 중앙 관리 (values.yaml)

### 차트 구조
```
todo-list/
├── Chart.yaml                    # 차트 메타데이터
├── values.yaml                   # 설정 값 저장소
└── templates/
    ├── _helpers.tpl              # 헬퍼 함수 (재사용 코드)
    ├── backend-deployment.yaml
    ├── backend-service.yaml
    ├── frontend-deployment.yaml
    ├── frontend-service.yaml
    ├── db-deployment.yaml
    ├── db-service.yaml
    ├── configmap.yaml
    ├── secret.yaml
    ├── ingress.yaml
    ├── mysql-pv.yaml
    ├── mysql-pvc.yaml
    └── mysql-storageclass.yaml
```

---

## 리팩토링 전후 비교

### BEFORE (하드코딩)
```yaml
# backend-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-deployment  # ← 고정된 이름
spec:
  replicas: 2  # ← 하드코딩
  selector:
    matchLabels:
      app: backend  # ← 단순 레이블
  template:
    spec:
      containers:
        - image: captainyun/k8s-labs-todo-backend:v1.0  # ← 버전 고정
          envFrom:
            - configMapRef:
                name: app-config  # ← 고정 이름
```

**문제점:**
- ❌ 같은 네임스페이스에 중복 배포 불가 (이름 충돌)
- ❌ 환경별로 별도 파일 필요
- ❌ 버전/설정 변경 시 파일 직접 수정
- ❌ 여러 환경 동시 운영 불가

### AFTER (Helm 템플릿)
```yaml
# backend-deployment.yaml
{{- if .Values.backend.enabled }}  # ← 조건부 렌더링
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "todo-list.backend.fullname" . }}  # ← 동적 이름
  labels:
    {{- include "todo-list.labels" . | nindent 4 }}  # ← 표준 레이블
spec:
  replicas: {{ .Values.backend.replicaCount }}  # ← values 주입
  template:
    spec:
      containers:
        - image: "{{ .Values.backend.image.repository }}:{{ .Values.backend.image.tag }}"
          envFrom:
            - configMapRef:
                name: {{ include "todo-list.configmap.name" . }}
{{- end }}
```

**개선 결과:**
- ✅ 릴리스별 고유 이름 (todo-dev-backend, todo-prod-backend)
- ✅ values.yaml 하나로 모든 설정 관리
- ✅ 컴포넌트 enable/disable 가능
- ✅ 다중 환경 동시 운영 가능

---

## 핵심 개념 설명

### 1. _helpers.tpl - 헬퍼 함수

#### 왜 필요한가?
중복 코드 제거 + 일관된 네이밍 + 표준 레이블 적용

#### 주요 함수들

**1) 이름 생성 함수**
```yaml
{{- define "todo-list.backend.fullname" -}}
{{ include "todo-list.fullname" . }}-backend
{{- end }}
```
→ `helm install my-todo todo-list/` 실행 시 `my-todo-todo-list-backend` 생성

**2) 레이블 함수**
```yaml
{{- define "todo-list.labels" -}}
helm.sh/chart: {{ include "todo-list.chart" . }}
app.kubernetes.io/name: {{ include "todo-list.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

**Kubernetes 표준 레이블의 중요성:**
- Prometheus, Grafana 등 모니터링 도구 호환
- `kubectl get all -l app.kubernetes.io/instance=my-todo`로 관련 리소스 조회
- ArgoCD, Flux 등 GitOps 도구와 호환

---

### 2. values.yaml - 설정 중앙화

```yaml
backend:
  enabled: true  # ← 컴포넌트 활성화 여부
  replicaCount: 2
  image:
    repository: captainyun/k8s-labs-todo-backend
    tag: "v1.0"
  service:
    type: NodePort
    port: 8080
    nodePort:
      enabled: true
      port: 32080

frontend:
  enabled: true
  # ...

database:
  enabled: true
  persistence:
    enabled: true
    size: 2Gi
  # ...
```

**활용 예시:**
```bash
# Backend만 배포
helm install my-backend todo-list/ \
  --set frontend.enabled=false \
  --set database.enabled=false

# 개발 환경: replica 1개, 작은 디스크
helm install todo-dev todo-list/ \
  --set backend.replicaCount=1 \
  --set database.persistence.size=1Gi

# 프로덕션: replica 5개, 큰 디스크
helm install todo-prod todo-list/ \
  --set backend.replicaCount=5 \
  --set database.persistence.size=50Gi
```

---

### 3. 템플릿 문법 핵심

#### 조건부 렌더링
```yaml
{{- if .Values.backend.enabled }}
# 이 블록은 backend.enabled: true 일 때만 렌더링
{{- end }}
```

#### 값 주입
```yaml
replicas: {{ .Values.backend.replicaCount }}
image: "{{ .Values.backend.image.repository }}:{{ .Values.backend.image.tag }}"
```

#### indent vs nindent 차이 (중요!)
```yaml
# ❌ 잘못된 예 - nindent는 새 줄 추가
labels:
  {{- include "todo-list.labels" . | nindent 4 }}
# 결과:
# labels:
#
#   app: todo  ← 들여쓰기 깨짐

# ✅ 올바른 예 - indent는 들여쓰기만
labels:
{{ include "todo-list.labels" . | indent 2 }}
# 결과:
# labels:
#   app: todo  ← 정상
```

---

## 실전 사용법

### 기본 설치
```bash
helm install todo-dev todo-list/
```

### 환경별 배포

**개발 환경:**
```bash
helm install todo-dev todo-list/ \
  --set backend.replicaCount=1 \
  --set backend.service.nodePort.port=30080 \
  --set ingress.enabled=false
```

**프로덕션 환경:**
```bash
helm install todo-prod todo-list/ -f values-prod.yaml
```

**values-prod.yaml:**
```yaml
backend:
  replicaCount: 5
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi

database:
  persistence:
    size: 50Gi
    storageClass: "fast-ssd"

ingress:
  enabled: true
  tls:
    - secretName: todo-tls
```

### 컴포넌트 선택적 배포
```bash
# Frontend 없이
helm install my-todo todo-list/ --set frontend.enabled=false

# Backend만
helm install backend-only todo-list/ \
  --set frontend.enabled=false \
  --set database.enabled=false
```

### 업그레이드 & 롤백
```bash
# 이미지 버전 업그레이드
helm upgrade todo-dev todo-list/ --set backend.image.tag=v2.0

# 롤백
helm rollback todo-dev 1
```

### 디버깅
```bash
# 렌더링 결과 확인 (배포 없이)
helm template my-todo todo-list/

# 문법 검사
helm lint todo-list/

# 실제 배포된 manifest 확인
helm get manifest todo-dev
```

---

## 주요 트러블슈팅

### 문제 1: Ingress port 에러
```
Error: port name or number is required
```

**원인:** `.backend.port` 대신 `$.Values.backend.service.port` 사용해야 함

**해결:**
```yaml
# ingress.yaml
backend:
  service:
    name: {{ include "todo-list.backend.fullname" $ }}
    port:
      number: {{ $.Values.backend.service.port }}  # ← $ 사용!
```

### 문제 2: 레이블 들여쓰기 오류
```
Error: YAML parse error
```

**원인:** `nindent` vs `indent` 잘못 사용

**해결:**
```yaml
# ❌ 잘못
labels:
  {{- include "labels" . | nindent 4 }}

# ✅ 올바름
labels:
{{ include "labels" . | indent 2 }}
```

### 문제 3: 이름 충돌
```
Error: Service "backend-service" already exists
```

**원인:** 하드코딩된 이름 사용

**해결:** 헬퍼 함수로 동적 이름 생성

---

## 재사용성 극대화 예제

### 블루-그린 배포
```bash
helm install todo-blue todo-list/
helm install todo-green todo-list/ --set backend.image.tag=v2.0

# 테스트 후
helm uninstall todo-blue
```

### A/B 테스트
```bash
helm install todo-variant-a todo-list/ --set backend.env.feature=A
helm install todo-variant-b todo-list/ --set backend.env.feature=B
```

### 다중 환경 동시 운영
```bash
helm install todo-dev todo-list/ -f values-dev.yaml
helm install todo-staging todo-list/ -f values-staging.yaml
helm install todo-prod todo-list/ -f values-prod.yaml

# 모두 같은 네임스페이스에서 동시 실행 가능!
```

---

## 베스트 프랙티스

### 1. 명시적 버전 사용
```yaml
# ✅ 좋음
tag: "v1.0.0"

# ❌ 나쁨
tag: "latest"
```

### 2. 리소스 제한 설정
```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi
```

### 3. 보안: Secret 외부 관리
```bash
# Sealed Secrets 사용
kubectl create secret generic mysql-pass \
  --from-literal=password=secret \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > sealed-secret.yaml
```

### 4. 환경별 values 파일 관리
```
environments/
├── values-dev.yaml
├── values-staging.yaml
└── values-prod.yaml
```

---

## 검증 체크리스트

- [ ] `helm lint` 통과
- [ ] `helm template` 정상 렌더링
- [ ] 컴포넌트 enable/disable 동작
- [ ] 다중 릴리스 동시 설치 가능
- [ ] 표준 레이블 적용 확인
- [ ] 리소스 추적 가능 (`kubectl get all -l app.kubernetes.io/instance=릴리스명`)

---

## 참고 자료

- [Helm 공식 문서](https://helm.sh/docs/)
- [Kubernetes 권장 레이블](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Go Template 문법](https://pkg.go.dev/text/template)

---

**작성일:** 2025-11-25  
**버전:** 1.0  
**작성자:** Claude Code Assistant