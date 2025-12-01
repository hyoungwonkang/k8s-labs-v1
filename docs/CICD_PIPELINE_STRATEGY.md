# Todo List CI/CD 파이프라인 전략

## 목차
1. [전체 아키텍처](#전체-아키텍처)
2. [Backend 파이프라인](#backend-파이프라인)
3. [Frontend 파이프라인](#frontend-파이프라인)
4. [ArgoCD 설치 및 설정](#argocd-설치-및-설정)
5. [ArgoCD 통합](#argocd-통합)
6. [트러블슈팅](#트러블슈팅)

---

## 전체 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitHub Repository                            │
│                    (k8s-labs-v1)                                 │
└────────────┬────────────────────────────────┬───────────────────┘
             │                                │
    Backend 변경                        Frontend 변경
    (apps/todo-list/backend/**)        (apps/todo-list/frontend/**)
             │                                │
             ▼                                ▼
    ┌────────────────┐              ┌────────────────┐
    │ ci-backend.yml │              │ci-frontend.yml │
    │                │              │                │
    │ 1. Gradle Build│              │ 1. npm Build   │
    │ 2. Docker Build│              │ 2. Docker Build│
    │ 3. Push to Hub │              │ 3. Push to Hub │
    └────────┬───────┘              └────────┬───────┘
             │                                │
             └────────────┬───────────────────┘
                          ▼
              ┌───────────────────────┐
              │  Manifests Repository │
              │ (k8s-labs-todo-list-  │
              │      manifests)       │
              │                       │
              │ todo-list-            │
              │  application.yaml     │
              │   ├─ backend.image.tag│
              │   └─ frontend.image.  │
              │      tag              │
              └───────────┬───────────┘
                          │
                          ▼
                  ┌───────────────┐
                  │   ArgoCD      │
                  │               │
                  │ Auto Sync     │
                  │ Self Heal     │
                  └───────┬───────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  Kubernetes Cluster   │
              │                       │
              │ ┌─────────────────┐  │
              │ │  Backend Pods   │  │
              │ └─────────────────┘  │
              │ ┌─────────────────┐  │
              │ │  Frontend Pods  │  │
              │ └─────────────────┘  │
              │ ┌─────────────────┐  │
              │ │ MySQL StatefulSet│ │
              │ └─────────────────┘  │
              └───────────────────────┘
```

---

## Backend 파이프라인

### 트리거
```yaml
on:
  push:
    branches: ["main"]
    paths:
      - "apps/todo-list/backend/**"
```

### 단계별 동작

#### 1. 소스 코드 체크아웃
```yaml
- name: Checkout source code
  uses: actions/checkout@v4
```

#### 2. 빌드 환경 설정
- **Runner**: self-hosted (k8s-control2)
- **JDK**: 17 (Temurin distribution)
- **Gradle**: Wrapper 사용 (gradlew)
- **캐싱**: Gradle 의존성 및 wrapper 캐시 (`~/.gradle/caches`, `~/.gradle/wrapper`)

```yaml
- name: Set up JDK 17
  uses: actions/setup-java@v4
  with:
    java-version: "17"
    distribution: "temurin"

- name: Gradle Caching
  uses: actions/cache@v4
  with:
    path: |
      ~/.gradle/caches
      ~/.gradle/wrapper
    key: ${{ runner.os }}-gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
```

#### 3. 애플리케이션 빌드
```bash
# gradlew 실행 권한 부여
chmod +x gradlew

# 테스트 제외하고 빌드
./gradlew build -x test
# 결과: build/libs/*.jar
```

#### 4. Docker 이미지 빌드 및 푸시
- **Docker Hub 로그인**: `docker/login-action@v3` 사용
- **이미지 태그**: 7자리 Git SHA (예: `2effa4f`)
- **Base Image**: `eclipse-temurin:17-jdk-alpine` (Dockerfile.prod)

```yaml
# 7자리 SHA 추출
- name: Export short SHA
  id: vars
  run: echo "SHORT_SHA=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"

# Docker 빌드 및 푸시
- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    context: ./apps/todo-list/backend
    file: ./apps/todo-list/backend/Dockerfile.prod
    push: true
    tags: hwplus/k8s-labs-todo-backend:${{ steps.vars.outputs.SHORT_SHA }}
```

**이미지 예시**:
- Commit SHA: `2effa4f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7`
- 이미지: `hwplus/k8s-labs-todo-backend:2effa4f`

#### 5. Manifests 저장소 업데이트
```yaml
# 1. Manifests 저장소 체크아웃
- name: Checkout manifests repository
  uses: actions/checkout@v4
  with:
    token: ${{ secrets.ACTION_PAT }}
    repository: hyoungwonkang/k8s-labs-todo-list-manifests
    path: manifests

# 2. yq 도구 설치
- name: Install yq
  run: |
    sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
    sudo chmod +x /usr/bin/yq

# 3. ArgoCD Application 매니페스트의 이미지 태그 업데이트
- name: Update image tag in ArgoCD Application manifest
  run: |
    NEW_TAG=${GITHUB_SHA:0:7}
    echo "Updating image tag to: $NEW_TAG"
    
    # 매니페스트 파일 존재 확인
    if [ ! -f manifests/todo-list-application.yaml ]; then
      echo "Error: Manifest file not found"
      exit 1
    fi
    
    # backend.image.tag 파라미터 업데이트
    yq e "(.spec.source.helm.parameters[] | select(.name == \"backend.image.tag\") | .value) = \"$NEW_TAG\"" \
      -i manifests/todo-list-application.yaml
    
    # 업데이트 결과 확인
    echo "Updated manifest:"
    yq e '.spec.source.helm.parameters[] | select(.name == "backend.image.tag")' \
      manifests/todo-list-application.yaml
```

#### 6. Git 변경사항 커밋 및 푸시
```bash
cd manifests
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .

# 변경사항이 있을 때만 커밋
if git diff --staged --quiet; then
  echo "No changes to commit"
else
  git commit -m "ci(backend): Update image tag to ${GITHUB_SHA:0:7}"
  git push
fi
```

#### 7. ArgoCD 자동 배포
- Manifests 저장소 변경 감지 (최대 3분)
- Helm Chart 렌더링 (새 이미지 태그 적용)
- Rolling Update 배포
- Health Check 완료

### 필요한 GitHub Secrets
- `DOCKERHUB_USERNAME`: Docker Hub 사용자명
- `DOCKERHUB_TOKEN`: Docker Hub 액세스 토큰
- `ACTION_PAT`: Manifests 저장소 접근용 Personal Access Token

---

## Frontend 파이프라인

### 트리거
```yaml
on:
  push:
    branches: ["main"]
    paths:
      - "apps/todo-list/frontend/**"
```

### 단계별 동작

#### 1. 소스 코드 체크아웃
```yaml
- name: Checkout source code
  uses: actions/checkout@v4
```

#### 2. 빌드 환경 설정
- **Runner**: self-hosted (k8s-control2)
- **Node.js**: 18
- **Package Manager**: npm
- **캐싱**: npm 의존성 캐시 (`package-lock.json` 기반)

```yaml
- name: Set up Node.js
  uses: actions/setup-node@v4
  with:
    node-version: "18"
    cache: "npm"
    cache-dependency-path: ./apps/todo-list/frontend/package-lock.json
```

#### 3. 의존성 설치
```bash
npm ci  # package-lock.json 기반 정확한 버전 설치
```

#### 4. 애플리케이션 빌드
```bash
npm run build  # Vite 빌드
# 결과: dist/ 디렉토리
```

**환경변수**:
```yaml
env:
  VITE_API_URL: http://192.168.80.200/api
```

> **중요**: 빌드 시점에 API URL이 정적으로 포함됨

#### 5. Docker 이미지 빌드 및 푸시
- **Docker Hub 로그인**: `docker/login-action@v3`
- **이미지 태그**: 7자리 Git SHA
- **Base Image**: `nginx:alpine` (Dockerfile.prod)

```yaml
# 7자리 SHA 추출
- name: Export short SHA
  id: vars
  run: echo "SHORT_SHA=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"

# Docker 빌드 및 푸시
- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    context: ./apps/todo-list/frontend
    file: ./apps/todo-list/frontend/Dockerfile.prod
    push: true
    tags: hwplus/k8s-labs-todo-frontend:${{ steps.vars.outputs.SHORT_SHA }}
```

**이미지 예시**: `hwplus/k8s-labs-todo-frontend:abc1234`

#### 6. Manifests 저장소 업데이트
```yaml
# 1. Manifests 저장소 체크아웃
- name: Checkout manifests repository
  uses: actions/checkout@v4
  with:
    token: ${{ secrets.ACTION_PAT }}
    repository: hyoungwonkang/k8s-labs-todo-list-manifests
    path: manifests

# 2. yq 설치 (이미 설치되어 있으면 스킵)
- name: Install yq
  run: |
    if ! command -v yq &> /dev/null; then
      sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
      sudo chmod +x /usr/bin/yq
    fi

# 3. frontend.image.tag 파라미터 업데이트
- name: Update image tag in ArgoCD Application manifest
  run: |
    NEW_TAG=${GITHUB_SHA:0:7}
    echo "Updating frontend image tag to: $NEW_TAG"
    
    if [ ! -f manifests/todo-list-application.yaml ]; then
      echo "Error: Manifest file not found"
      exit 1
    fi
    
    yq e "(.spec.source.helm.parameters[] | select(.name == \"frontend.image.tag\") | .value) = \"$NEW_TAG\"" \
      -i manifests/todo-list-application.yaml
    
    echo "Updated manifest:"
    yq e '.spec.source.helm.parameters[] | select(.name == "frontend.image.tag")' \
      manifests/todo-list-application.yaml
```

#### 7. Git 변경사항 커밋 및 푸시
```bash
cd manifests
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .

if git diff --staged --quiet; then
  echo "No changes to commit"
else
  git commit -m "ci(frontend): Update image tag to ${GITHUB_SHA:0:7}"
  git push
fi
```

#### 8. ArgoCD 자동 배포
Backend와 동일한 프로세스

---

## ArgoCD 설치 및 설정

### 1. ArgoCD 설치

#### 네임스페이스 생성 및 ArgoCD 설치
```bash
# ArgoCD 네임스페이스 생성
kubectl create namespace argocd

# ArgoCD 설치 (최신 안정 버전)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 설치 확인
kubectl get pods -n argocd
# 모든 Pod가 Running 상태가 될 때까지 대기 (약 1-2분)
```

#### ArgoCD Server 외부 노출 (NodePort)
```bash
# argocd-server 서비스를 NodePort로 변경
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'

# 할당된 NodePort 확인
kubectl get svc argocd-server -n argocd
# 출력 예시:
# NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
# argocd-server   NodePort   10.96.123.45    <none>        80:32053/TCP,443:31234/TCP   2m
```

또는 특정 NodePort 지정:
```bash
kubectl patch svc argocd-server -n argocd --type='json' -p='[
  {"op": "replace", "path": "/spec/type", "value": "NodePort"},
  {"op": "add", "path": "/spec/ports/0/nodePort", "value": 32053}
]'
```

### 2. ArgoCD UI 접속

#### 초기 admin 비밀번호 확인
```bash
# ArgoCD 초기 admin 비밀번호 조회
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# 출력 예시: mY8sEcUrEpAsSwOrD123
```

#### 브라우저 접속
```
URL: http://<control-plane-IP>:32053
사용자명: admin
비밀번호: (위에서 조회한 값)

예시: http://192.168.80.129:32053
```

#### 비밀번호 변경 (권장)
```bash
# ArgoCD CLI 설치 (선택사항)
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# ArgoCD 로그인
argocd login 192.168.80.129:32053 --insecure
# Username: admin
# Password: (초기 비밀번호 입력)

# 비밀번호 변경
argocd account update-password
# Current password: (초기 비밀번호)
# New password: (새 비밀번호)
# Confirm new password: (새 비밀번호 확인)
```

### 3. Application 생성 방법

#### 방법 1: kubectl로 YAML 적용 (권장)

**Manifests 저장소에 Application YAML 생성**:

1. `k8s-labs-todo-list-manifests` 저장소 생성 (아직 없는 경우)
2. `todo-list-application.yaml` 파일 생성 및 커밋

```bash
# Manifests 저장소 클론
git clone https://github.com/<your-account>/k8s-labs-todo-list-manifests.git
cd k8s-labs-todo-list-manifests

# Application YAML 작성 (아래 예시 참고)
vim todo-list-application.yaml

# Git에 커밋 및 푸시
git add todo-list-application.yaml
git commit -m "feat: Add ArgoCD Application manifest"
git push origin main
```

**Application 적용**:
```bash
# 로컬에서 적용
kubectl apply -f todo-list-application.yaml

# 또는 URL에서 직접 적용
kubectl apply -f https://raw.githubusercontent.com/<your-account>/k8s-labs-todo-list-manifests/main/todo-list-application.yaml

# 생성 확인
kubectl get application -n argocd
kubectl describe application todo-list-backend-app -n argocd
```

#### 방법 2: ArgoCD UI 사용

1. ArgoCD UI 접속 (`http://<control-plane-IP>:32053`)
2. 좌측 상단 **`+ NEW APP`** 버튼 클릭
3. Application 정보 입력:
   - **Application Name**: `todo-list-backend-app`
   - **Project**: `default`
   - **Sync Policy**: `Automatic` (Auto-Create Namespace 체크)
   - **Repository URL**: `https://github.com/hyoungwonkang/k8s-labs-v1.git`
   - **Revision**: `main`
   - **Path**: `apps/todo-list/todo-list-chart`
   - **Cluster**: `https://kubernetes.default.svc`
   - **Namespace**: `default`
4. **Helm Parameters** 섹션에서:
   - `backend.image.tag`: `initial` (CI가 업데이트)
   - `frontend.image.tag`: `initial` (CI가 업데이트)
5. **CREATE** 버튼 클릭

#### 방법 3: ArgoCD CLI 사용

```bash
# ArgoCD 로그인 (이미 했다면 생략)
argocd login 192.168.80.129:32053 --insecure

# Application 생성
argocd app create todo-list-backend-app \
  --repo https://github.com/hyoungwonkang/k8s-labs-v1.git \
  --path apps/todo-list/todo-list-chart \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --helm-set backend.image.tag=initial \
  --helm-set frontend.image.tag=initial \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# 생성 확인
argocd app get todo-list-backend-app
```

### 4. 초기 동기화

```bash
# Application 수동 동기화 (최초 1회)
kubectl patch application todo-list-backend-app -n argocd \
  --type merge -p '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {}}}'

# 또는 CLI로
argocd app sync todo-list-backend-app

# 또는 UI에서 SYNC 버튼 클릭

# 동기화 상태 확인
kubectl get application todo-list-backend-app -n argocd
argocd app get todo-list-backend-app

# Pod 배포 확인
kubectl get pods -n default
```

---

## ArgoCD 통합

### Application 구조

**저장소**: `k8s-labs-todo-list-manifests`

**파일**: `todo-list-application.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: todo-list-backend-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/hyoungwonkang/k8s-labs-v1.git
    targetRevision: main
    path: apps/todo-list/todo-list-chart  # Umbrella Helm Chart 경로
    helm:
      valueFiles:
        - values.yaml
      parameters:
        - name: backend.image.tag
          value: "2effa4f"      # CI가 자동 업데이트
        - name: frontend.image.tag
          value: "abc1234"      # CI가 자동 업데이트
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true      # 삭제된 리소스 자동 정리
      selfHeal: true   # 수동 변경 자동 복구
    syncOptions:
      - CreateNamespace=true
```

### Helm Values 구조

**파일**: `apps/todo-list/todo-list-chart/values.yaml` (Umbrella Chart)

```yaml
backend:
  replicaCount: 2
  image:
    repository: hwplus/k8s-labs-todo-backend
    tag: "latest"  # ArgoCD parameters가 이 값을 덮어씀
  service:
    type: ClusterIP
    port: 8080
    targetPort: 8080
  env:
    - name: SPRING_DATASOURCE_URL
      value: "jdbc:mysql://todo-db-service:3306/tododb?useSSL=false&allowPublicKeyRetrieval=true&characterEncoding=UTF-8&serverTimezone=UTC"
    - name: SPRING_DATASOURCE_USERNAME
      value: "todouser"
    - name: CORS_ALLOWED_ORIGINS
      value: "http://192.168.60.129:30000"

frontend:
  replicaCount: 2
  image:
    repository: hwplus/k8s-labs-todo-frontend
    tag: "latest"  # ArgoCD parameters가 이 값을 덮어씀
  service:
    type: ClusterIP
    port: 80
    targetPort: 80

database:
  enabled: true
  name: tododb
  user: todouser
  password: "todo1234"
  rootPassword: "root1234"
  storageClass: "todo-db-storage"
  persistence:
    size: "1Gi"

ingress:
  enabled: true
  className: nginx
  host: todo.example.com
  frontend:
    path: /
    serviceName: frontend-service
    servicePort: 80
```

> **참고**: 위 구조는 umbrella chart 방식으로, backend, frontend, database를 단일 chart로 관리합니다.

### 동기화 정책

**Automated Sync**:
- Manifests 변경 감지 → 3분 이내 자동 배포
- Git이 Single Source of Truth

**Self Heal**:
- `kubectl edit`로 수동 변경 시 자동 롤백
- Git의 상태로 복구

**Prune**:
- Git에서 삭제된 리소스를 클러스터에서도 삭제

---

## 배포 흐름 예시

### 시나리오: Backend 코드 변경

```bash
# 1. 개발자가 코드 수정
git add apps/todo-list/backend/src/main/java/...
git commit -m "feat: Add new API endpoint"
git push origin main

# 2. GitHub Actions 트리거 (자동)
# Commit SHA: 2effa4f3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9
# Short SHA: 2effa4f

# 3. CI 파이프라인 실행 (자동, 약 3-5분)
✓ Checkout source code
✓ Set up JDK 17
✓ Gradle Caching (의존성 캐시 복원)
✓ Grant execute permission for gradlew
✓ Build with Gradle (-x test)
✓ Login to Docker Hub
✓ Export short SHA (2effa4f)
✓ Build and push Docker image
  → hwplus/k8s-labs-todo-backend:2effa4f
✓ Checkout manifests repository
✓ Install yq
✓ Update image tag in ArgoCD Application manifest
  backend.image.tag: "old_tag" → "2effa4f"
✓ Commit and push changes
  → "ci(backend): Update image tag to 2effa4f"

# 4. Manifests 저장소 업데이트 완료
# Repository: k8s-labs-todo-list-manifests
# File: todo-list-application.yaml
# Changed: spec.source.helm.parameters[backend.image.tag]

# 5. ArgoCD 배포 (자동, 1-3분)
✓ 변경 감지 (Polling 또는 Webhook)
✓ Helm Chart 렌더링
  - values.yaml + parameters 병합
  - backend.image.tag: "2effa4f" 적용
✓ Deployment 업데이트 (Rolling Update)
  - 새 ReplicaSet 생성
  - 새 Pod 시작 (이미지: hwplus/k8s-labs-todo-backend:2effa4f)
  - Health Check (Readiness Probe 성공)
  - 이전 Pod 종료
✓ Sync 완료 (Status: Synced, Healthy)

# 6. 배포 확인
kubectl get pods -l app.kubernetes.io/name=todo-list-chart
# NAME                              READY   STATUS    IMAGE
# todo-backend-xxxxxx-yyyyy        1/1     Running   hwplus/k8s-labs-todo-backend:2effa4f
# todo-backend-xxxxxx-zzzzz        1/1     Running   hwplus/k8s-labs-todo-backend:2effa4f

kubectl describe pod todo-backend-xxxxxx-yyyyy | grep Image:
# Image: hwplus/k8s-labs-todo-backend:2effa4f
```

### 전체 소요 시간
- CI 빌드: 3~5분
- ArgoCD 동기화: 1~3분
- **총**: 약 5~8분

---

## 롤백 전략

### 방법 1: Git Revert (권장)
```bash
# Manifests 저장소에서
git revert HEAD
git push

# ArgoCD가 자동으로 이전 이미지로 배포
```

### 방법 2: ArgoCD UI
1. ArgoCD UI 접속
2. Application 선택
3. History 탭
4. 이전 버전 선택 → Rollback

### 방법 3: ArgoCD CLI
```bash
# ArgoCD CLI 설치 (필요시)
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argocd-cmd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# ArgoCD 로그인
argocd login 192.168.80.129:32053 --insecure

# 이전 revision으로 롤백
argocd app rollback todo-list-backend-app 0
# 0 = 이전 revision
# 특정 revision: argocd app rollback todo-list-backend-app 5
```

### 방법 4: 수동 패치 (긴급)
```bash
# 특정 이미지 태그로 즉시 변경
kubectl patch application todo-list-backend-app -n argocd \
  --type=json \
  -p='[{"op": "replace", "path": "/spec/source/helm/parameters/0/value", "value": "2effa4f"}]'

# 또는 kubectl edit으로 직접 수정
kubectl edit application todo-list-backend-app -n argocd
# spec.source.helm.parameters[].value 수정
```

---

## 모니터링

### ArgoCD 상태 확인
```bash
# Application 상태
kubectl get application -n argocd

# 상세 정보
kubectl describe application todo-list-backend-app -n argocd

# Sync 상태
argocd app get todo-list-backend-app
```

### 배포된 리소스 확인
```bash
# Pod 이미지 확인
kubectl get pods -l app.kubernetes.io/name=todo-list-chart \
  -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n'

# 예상 출력:
# hwplus/k8s-labs-todo-backend:2effa4f
# hwplus/k8s-labs-todo-frontend:abc1234
# mysql:8.0

# 특정 Pod의 상세 이미지 정보
kubectl describe pod <pod-name> | grep -A 5 "Containers:"
```

### GitHub Actions 워크플로우 확인
```bash
# 저장소 페이지에서
# Actions 탭 → 최근 워크플로우 실행 확인
# 또는 직접 URL:
# https://github.com/hyoungwonkang/k8s-labs-v1/actions

# 실행 중인 워크플로우 로그 보기
# 각 step의 성공/실패 확인
# Docker 이미지 태그 출력 확인
```

---

## 트러블슈팅

### 1. CI 실패: "Manifest file not found"

**원인**: Manifests 저장소가 비어있거나 파일명 오타

**해결**:
```bash
# Manifests 저장소 확인
curl -s https://api.github.com/repos/hyoungwonkang/k8s-labs-todo-list-manifests/contents | jq -r '.[].name'

# 파일명 확인 (대소문자, 하이픈)
# todo-list-application.yaml (O)
# todo-list-applicaion.yaml (X - i 하나 빠짐)
```

### 2. ArgoCD: "Namespace is missing"

**원인**: Helm 템플릿에 `metadata.namespace` 없음

**해결**:
```yaml
# 모든 템플릿 파일에 추가
metadata:
  namespace: {{ .Release.Namespace }}
  name: ...
```

### 3. 이미지 Pull 실패

**원인**: Docker Hub에 해당 태그가 없음

**확인**:
```bash
# Docker Hub API로 태그 확인
curl -s "https://hub.docker.com/v2/repositories/hwplus/k8s-labs-todo-backend/tags?page_size=100" | jq -r '.results[].name'

# 최근 10개 태그만 보기
curl -s "https://hub.docker.com/v2/repositories/hwplus/k8s-labs-todo-backend/tags?page_size=10" | jq -r '.results[] | "\(.name) - \(.last_updated)"'

# 또는 브라우저에서
# https://hub.docker.com/r/hwplus/k8s-labs-todo-backend/tags
```

**해결**:
```bash
# 1. CI 워크플로우 로그에서 이미지 푸시 확인
# GitHub → Actions → 해당 워크플로우 → "Build and push Docker image" step
# 출력에서 "pushed" 메시지 확인

# 2. ArgoCD Application의 image.tag 값 확인
kubectl get application todo-list-backend-app -n argocd -o yaml | grep -A 3 "parameters:"

# 3. values.yaml의 태그와 일치하는지 확인
yq e '.backend.image.tag' apps/todo-list/backend/helm/todo-list-chart/values.yaml
```

### 4. ArgoCD Out of Sync

**원인**: 
- 수동으로 리소스 변경
- Git과 클러스터 상태 불일치

**해결**:
```bash
# 강제 동기화
argocd app sync todo-list-backend-app --force

# 또는 UI에서 HARD REFRESH
```

### 5. Self-hosted Runner 연결 안 됨

**확인**:
```bash
# Runner 서비스 상태
sudo systemctl status github.actions.*

# 또는 특정 서비스명으로 확인 (서비스명은 설치 시 생성됨)
sudo systemctl status actions.runner.hyoungwonkang-k8s-labs-v1.k8s-control2.service

# Runner 로그 확인
sudo journalctl -u github.actions.* -f
```

**재시작**:
```bash
# 서비스 재시작
sudo systemctl restart github.actions.*

# 또는 수동 실행 (테스트용)
cd ~/actions-runner
./run.sh
```

**재설치** (문제 지속 시):
```bash
# 기존 Runner 제거 (GitHub 설정에서도 제거)
cd ~/actions-runner
./config.sh remove --token <REMOVAL_TOKEN>

# 새로 설치
# GitHub → Settings → Actions → Runners → New self-hosted runner
# 화면의 지시사항 따라 재설치
```

### 6. Gradle 빌드 실패

**원인**: 의존성 다운로드 실패 또는 캐시 손상

**해결**:
```bash
# Gradle 캐시 정리 (로컬 테스트)
cd apps/todo-list/backend
./gradlew clean build --refresh-dependencies

# GitHub Actions에서 캐시 삭제
# GitHub → Settings → Actions → Caches
# 해당 캐시 항목 삭제 후 재실행
```

### 7. yq 명령어 실패

**원인**: yq가 설치되지 않았거나 구버전

**해결**:
```bash
# 현재 버전 확인
yq --version

# 최신 버전으로 업데이트
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
sudo chmod +x /usr/bin/yq

# 정상 작동 확인
yq --version
# yq (https://github.com/mikefarah/yq/) version v4.x.x
```

---

## 보안 고려사항

### Secrets 관리
1. **GitHub Actions Secrets**
   - Repository Settings → Secrets and variables → Actions
   - 필수 Secrets:
     - `DOCKERHUB_USERNAME`: Docker Hub 사용자명 (예: hwplus)
     - `DOCKERHUB_TOKEN`: Docker Hub Access Token (Hub에서 생성)
     - `ACTION_PAT`: GitHub Personal Access Token (Manifests 저장소 접근용)

2. **Kubernetes Secrets**
   ```bash
   # ArgoCD가 관리하지 않고 수동으로 생성
   kubectl create secret generic db-secret \
     --from-literal=MYSQL_ROOT_PASSWORD=root1234 \
     --from-literal=MYSQL_PASSWORD=todo1234 \
     -n default
   
   # 또는 Helm values.yaml에서 관리 (현재 방식)
   # database.password, database.rootPassword
   ```

3. **Docker Hub Access Token 생성**
   ```
   1. Docker Hub 로그인 → Account Settings
   2. Security → New Access Token
   3. Description: "GitHub Actions CI"
   4. Permissions: Read, Write, Delete
   5. 생성된 토큰을 GitHub Secrets에 저장
   ```

### ACTION_PAT 권한
- **최소 권한**: `repo` (Full control of private repositories)
- **필요 이유**: Manifests 저장소에 커밋 및 푸시
- **유효기간**: 90일 권장 (정기 갱신 필요)
- **생성 방법**:
  ```
  GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
  → Generate new token → 'repo' 체크 → Generate token
  ```

### 환경 변수 보안
```yaml
# CI 워크플로우에서 환경변수 사용 시
env:
  VITE_API_URL: http://192.168.80.200/api  # 공개 정보 (OK)
  # API_KEY: ${{ secrets.API_KEY }}        # 비밀 정보 (Secret 사용)
```

---

## 다음 단계

### 즉시 테스트 가능한 항목

1. **Backend CI 트리거 테스트**
   ```bash
   # 간단한 변경으로 CI 트리거
   echo "// Test CI pipeline" >> apps/todo-list/backend/src/main/resources/application.yml
   git add apps/todo-list/backend/
   git commit -m "test: Trigger backend CI pipeline"
   git push origin main
   
   # GitHub Actions 진행 상황 확인
   # https://github.com/hyoungwonkang/k8s-labs-v1/actions
   ```

2. **Frontend CI 트리거 테스트**
   ```bash
   # Frontend 파일 변경
   echo "/* Test */" >> apps/todo-list/frontend/src/App.jsx
   git add apps/todo-list/frontend/
   git commit -m "test: Trigger frontend CI pipeline"
   git push origin main
   ```

3. **ArgoCD 자동 동기화 확인**
   ```bash
   # Manifests 저장소 변경 감지 대기 (최대 3분)
   watch kubectl get application -n argocd
   
   # Sync 상태 확인
   kubectl describe application todo-list-backend-app -n argocd | grep -A 5 "Status:"
   ```

### 개선 사항

1. ✅ **테스트 자동화**
   ```yaml
   # .github/workflows/ci-backend.yml에 추가
   - name: Run tests
     run: ./gradlew test
     working-directory: ./apps/todo-list/backend
   
   - name: Test Report
     uses: dorny/test-reporter@v1
     if: always()
     with:
       name: Gradle Tests
       path: apps/todo-list/backend/build/test-results/test/*.xml
       reporter: java-junit
   ```

2. ✅ **Multi-stage Docker Build** (이미지 크기 최적화)
   ```dockerfile
   # Dockerfile.prod 개선
   FROM gradle:8.5-jdk17 AS builder
   WORKDIR /app
   COPY . .
   RUN gradle build -x test --no-daemon
   
   FROM eclipse-temurin:17-jre-alpine  # JRE만 사용 (더 작음)
   WORKDIR /app
   COPY --from=builder /app/build/libs/*.jar app.jar
   ENTRYPOINT ["java", "-jar", "app.jar"]
   ```

3. ✅ **Canary 배포** (ArgoCD Rollouts)
   ```bash
   # Argo Rollouts 설치
   kubectl create namespace argo-rollouts
   kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
   
   # Deployment를 Rollout으로 변경
   # 점진적 트래픽 전환 (10% → 50% → 100%)
   ```

4. ✅ **Slack/Discord 알림**
   ```yaml
   # .github/workflows/ci-backend.yml에 추가
   - name: Notify Slack
     if: failure()
     uses: 8398a7/action-slack@v3
     with:
       status: ${{ job.status }}
       text: 'Backend CI failed'
       webhook_url: ${{ secrets.SLACK_WEBHOOK }}
   ```

5. ✅ **Image Vulnerability Scanning**
   ```yaml
   # CI에 Trivy 추가
   - name: Run Trivy vulnerability scanner
     uses: aquasecurity/trivy-action@master
     with:
       image-ref: hwplus/k8s-labs-todo-backend:${{ steps.vars.outputs.SHORT_SHA }}
       format: 'sarif'
       output: 'trivy-results.sarif'
   
   - name: Upload Trivy results to GitHub Security
     uses: github/codeql-action/upload-sarif@v2
     with:
       sarif_file: 'trivy-results.sarif'
   ```

### 성능 최적화

1. **Gradle Build Cache 개선**
   ```yaml
   # 빌드 시간 단축 (현재 3-5분 → 1-2분 목표)
   - name: Gradle Caching
     uses: actions/cache@v4
     with:
       path: |
         ~/.gradle/caches
         ~/.gradle/wrapper
         apps/todo-list/backend/.gradle
         apps/todo-list/backend/build
   ```

2. **Docker Layer Caching**
   ```yaml
   - name: Build and push Docker image
     uses: docker/build-push-action@v5
     with:
       context: ./apps/todo-list/backend
       file: ./apps/todo-list/backend/Dockerfile.prod
       push: true
       tags: hwplus/k8s-labs-todo-backend:${{ steps.vars.outputs.SHORT_SHA }}
       cache-from: type=registry,ref=hwplus/k8s-labs-todo-backend:cache
       cache-to: type=registry,ref=hwplus/k8s-labs-todo-backend:cache,mode=max
   ```

---

## 참고 자료

- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)
- [GitHub Actions 문서](https://docs.github.com/en/actions)
- [Helm 차트 작성 가이드](https://helm.sh/docs/chart_template_guide/)
