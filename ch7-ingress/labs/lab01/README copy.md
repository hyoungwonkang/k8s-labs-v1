# Lab 01: `todo-list` 데이터베이스 영속성 확보하기

`exercises`에서 우리는 `PVC`와 `StatefulSet`이라는 강력한 도구를 배웠습니다. 이제 이론을 넘어, 실제 프로젝트에 이 기술을 적용해 볼 시간입니다\!
현재 `todo-list`의 데이터베이스는 `Deployment`로 배포되어 있어, Pod이 재시작될 때마다 모든 할 일 목록이 사라지는 치명적인 문제가 있습니다.
이번 랩에서는 `Deployment`를 `StatefulSet`으로 전환하여, `todo-list`의 데이터가 영구적으로 보존되도록 업그레이드하는 작업을 진행합니다.

-----

### 📂 최종 파일 구조

이 랩을 완료하면 여러분의 `lab01` 디렉토리는 다음과 같은 구조를 갖게 됩니다.

```
lab01/
├── todo-db-headless-svc.yaml
└── todo-db-statefulset.yaml
```

-----

### 🎯 랩 목표

1.  기존 `Deployment`로 배포된 데이터베이스를 `StatefulSet`으로 전환할 수 있다.
2.  `Headless Service`를 생성하고 `StatefulSet`에 연결할 수 있다.
3.  `volumeClaimTemplates`를 사용하여 데이터베이스 Pod을 위한 영구 저장 공간(PVC)을 동적으로 생성할 수 있다.
4.  애플리케이션 데이터를 성공적으로 보존하고, Pod 재시작 후에도 데이터가 남아있는 것을 직접 검증한다.

-----

## 🛠️ 실습 가이드

### Step 0: 준비 및 기존 리소스 정리

가장 먼저, 실습을 방해할 수 있는 기존 `todo-list`의 데이터베이스 관련 리소스를 깨끗이 삭제해야 합니다.

```bash
# 이전에 배포했던 todo-list의 DB Deployment와 Service를 삭제합니다.
# 파일 경로는 여러분의 프로젝트 구조에 맞게 수정해주세요.
kubectl delete -f ../../../ch5-config/labs/lab01/todo-db-deployment.yaml
kubectl delete -f ../../../ch4-service/labs/lab01/todo-db-svc.yaml

# 삭제되었는지 확인합니다. 'Not Found' 메시지가 나오면 정상입니다.
kubectl get deployment todo-db-deployment
kubectl get service todo-db-svc
```

### Step 1: Headless 서비스 생성하기

`StatefulSet`의 Pod들이 서로를 찾고 고유한 네트워크 주소를 가질 수 있도록, 가장 먼저 `Headless Service`를 만들어야 합니다.

**📄 `todo-db-headless-svc.yaml` 파일을 생성하고 아래 내용을 작성하세요.**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: todo-db-svc # 이전 Service와 동일한 이름을 사용해도 됩니다. 백엔드는 이 이름으로 DB를 찾습니다.
spec:
  # clusterIP: None 으로 설정하여 Headless 서비스로 만듭니다.
  clusterIP: None
  selector:
    # 이 서비스가 어떤 Pod을 찾을지 라벨을 지정합니다.
    # StatefulSet의 Pod 라벨과 일치해야 합니다.
    app: todo-db
  ports:
    - protocol: TCP
      port: 5432
      targetPort: 5432
```

### Step 2: Deployment를 StatefulSet으로 전환하기

이 랩의 가장 핵심적인 부분입니다. 기존 `Deployment` YAML을 기반으로 `StatefulSet` YAML을 만들어 보겠습니다.

**📄 `todo-db-statefulset.yaml` 파일을 생성하고 아래 내용을 작성하세요.**

```yaml
apiVersion: apps/v1
# 1. kind를 Deployment에서 StatefulSet으로 변경
kind: StatefulSet
metadata:
  name: todo-db
spec:
  # 2. serviceName을 추가하여 위에서 만든 Headless Service와 연결
  serviceName: "todo-db-svc"
  replicas: 1
  selector:
    matchLabels:
      app: todo-db
  template:
    metadata:
      labels:
        app: todo-db
    spec:
      containers:
        - name: postgres
          image: postgres:13
          ports:
            - containerPort: 5432
          envFrom:
            - secretRef:
                name: todo-db-secret
          # 3. volumeMounts 추가: 컨테이너의 데이터 디렉토리에 볼륨을 연결
          volumeMounts:
            - name: todo-db-data # 아래 volumeClaimTemplates의 이름과 일치
              mountPath: /var/lib/postgresql/data
  # 4. volumeClaimTemplates 추가: 각 Pod을 위한 PVC 템플릿 정의
  volumeClaimTemplates:
    - metadata:
        name: todo-db-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "standard" # ex02에서 확인한 StorageClass
        resources:
          requests:
            storage: 1Gi
```

**주요 변경점:**

1.  `kind`를 `StatefulSet`으로 변경
2.  `StatefulSet`을 제어할 `serviceName` 지정
3.  컨테이너의 실제 데이터 디렉토리(`/var/lib/postgresql/data`)에 볼륨을 마운트하는 `volumeMounts` 추가
4.  각 Pod에 대한 `PVC`를 자동으로 생성해 줄 `volumeClaimTemplates` 추가

### Step 3: 배포 및 상태 확인

이제 새로운 리소스들을 클러스터에 배포하고, 모든 것이 정상적으로 생성되었는지 확인합니다.

```bash
# Headless Service와 StatefulSet을 배포합니다.
kubectl apply -f todo-db-headless-svc.yaml
kubectl apply -f todo-db-statefulset.yaml

# 잠시 기다린 후, Pod과 PVC가 잘 생성되었는지 확인합니다.
kubectl get pods -l app=todo-db
kubectl get pvc

# 예상 출력:
# NAME        READY   STATUS    RESTARTS   AGE
# todo-db-0   1/1     Running   0          1m

# NAME                     STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# todo-db-data-todo-db-0   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   1Gi        RWO            standard       1m
```

Pod의 이름이 `todo-db-0` 처럼 안정적인 이름으로 생성되고, `todo-db-data-todo-db-0` 이라는 이름의 PVC가 생성되어 `Bound` 상태인 것을 확인하세요.

### Step 4: 최종 테스트 - 데이터는 살아있다\! ✅

이제 대망의 순간입니다. 정말 데이터가 영구적으로 보존되는지 테스트해 봅시다.

1.  **데이터 생성:** `todo-list`의 프론트엔드와 백엔드 Pod들이 모두 실행 중인지 확인하고, `todo-list` 웹 애플리케이션에 접속하여 **새로운 할 일 2\~3개**를 추가합니다.

2.  **Pod 강제 삭제:** 아래 명령어로 데이터베이스 Pod을 강제로 삭제합니다. `StatefulSet`이 즉시 Pod을 복구할 것입니다.

    ```bash
    kubectl delete pod todo-db-0
    ```

3.  **Pod 복구 확인:** `kubectl get pods` 명령어를 계속 실행하여 `todo-db-0` Pod이 `Terminating` 상태를 거쳐 다시 `Running` 상태가 되는 것을 지켜보세요.

4.  **데이터 보존 확인:** Pod이 완전히 복구된 후, `todo-list` 웹 애플리케이션 페이지를 **새로고침**합니다.

만약 이전에 추가했던 할 일 목록이 **사라지지 않고 그대로 화면에 나타난다면**, 여러분은 성공적으로 데이터 영속성을 확보한 것입니다\!

-----

### 🎉 축하합니다\!

여러분은 `StatefulSet`과 `PVC`를 사용하여 `todo-list` 프로젝트의 데이터베이스를 한 단계 업그레이드했습니다. 이제 이 지식을 바탕으로, 다음 랩에서는 더 복잡한 우리의 메인 프로젝트, `ddoddo-market`에 도전해 보겠습니다.