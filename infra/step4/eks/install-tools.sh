#!/usr/bin/env bash
# step4.1 — WSL 에 kubectl · eksctl 설치 (이미 있으면 버전만 보여 준다)
#   3단계는 cp 노드 안에서 kubectl 을 썼다. EKS 는 API 서버가 AWS 에 있어 WSL 에서 IAM 으로 바로 접속한다
set -euo pipefail
mkdir -p ~/.local/bin; export PATH="$HOME/.local/bin:$PATH"
grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
if ! command -v kubectl >/dev/null; then
  v=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  curl -fsSL -o ~/.local/bin/kubectl "https://dl.k8s.io/release/$v/bin/linux/amd64/kubectl"
  chmod +x ~/.local/bin/kubectl
fi
if ! command -v eksctl >/dev/null; then
  curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C ~/.local/bin eksctl
fi
echo "== kubectl $(kubectl version --client -o json | python3 -c 'import json,sys;print(json.load(sys.stdin)["clientVersion"]["gitVersion"])')"
echo "== eksctl $(eksctl version)"
echo "== aws $(aws --version 2>&1 | cut -d' ' -f1)"
