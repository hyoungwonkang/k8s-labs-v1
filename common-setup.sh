#!/bin/bash

# 쿠버네티스 클러스터 구축 - 공통 설정 스크립트
# 모든 노드(Control Plane, Worker)에서 실행

set -e

echo "========================================="
echo "쿠버네티스 노드 공통 설정 시작"
echo "========================================="

# 1. Swap 비활성화
echo "[1/7] Swap 비활성화 중..."
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# 2. 커널 모듈 로드
echo "[2/7] 커널 모듈 설정 중..."
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 3. 커널 파라미터 설정
echo "[3/7] 커널 파라미터 설정 중..."
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

# 4. containerd 설치
echo "[4/7] containerd 설치 중..."
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Docker 공식 GPG 키 추가
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Docker 저장소 추가
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y containerd.io

# containerd 설정
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

# 5. 쿠버네티스 패키지 저장소 추가
echo "[5/7] 쿠버네티스 저장소 추가 중..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# 6. kubeadm, kubelet, kubectl 설치
echo "[6/7] kubeadm, kubelet, kubectl 설치 중..."
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 7. kubelet 활성화
echo "[7/7] kubelet 활성화 중..."
sudo systemctl enable kubelet

echo "========================================="
echo "공통 설정 완료!"
echo "========================================="
echo ""
echo "다음 단계:"
echo "- Control Plane 노드: control-plane-init.sh 실행"
echo "- Worker 노드: 대기 후 join 명령어 실행"
echo "========================================="
