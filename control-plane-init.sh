#!/bin/bash

# 쿠버네티스 Control Plane 초기화 스크립트
# k8s-control2 (192.168.80.129)에서 실행

set -e

CONTROL_PLANE_IP="192.168.80.129"
POD_NETWORK_CIDR="10.244.0.0/16"

echo "========================================="
echo "Control Plane 초기화 시작"
echo "========================================="

# 1. kubeadm으로 클러스터 초기화
echo "[1/4] kubeadm으로 클러스터 초기화 중..."
sudo kubeadm init \
  --apiserver-advertise-address=$CONTROL_PLANE_IP \
  --pod-network-cidr=$POD_NETWORK_CIDR \
  --control-plane-endpoint=$CONTROL_PLANE_IP

# 2. kubectl 설정
echo "[2/4] kubectl 설정 중..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 3. Flannel CNI 설치
echo "[3/4] Flannel CNI 설치 중..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# 4. Join 명령어 생성 및 저장
echo "[4/4] Worker 노드 join 명령어 생성 중..."
echo ""
echo "========================================="
echo "Control Plane 초기화 완료!"
echo "========================================="
echo ""
echo "Worker 노드에서 아래 명령어를 실행하세요:"
echo "========================================="
kubeadm token create --print-join-command | tee ~/worker-join-command.sh
chmod +x ~/worker-join-command.sh
echo "========================================="
echo ""
echo "Join 명령어는 ~/worker-join-command.sh 파일에 저장되었습니다."
echo ""
echo "클러스터 상태 확인:"
kubectl get nodes
echo ""
echo "참고: 노드가 Ready 상태가 되려면 1-2분 정도 소요될 수 있습니다."
echo "========================================="