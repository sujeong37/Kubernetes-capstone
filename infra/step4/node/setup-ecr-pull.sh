#!/usr/bin/env bash
# step4.0.3 — (worker1 · worker2 창에서 각각) kubelet 이 ECR 이미지를 받을 수 있게 한다
#   kubelet 은 이미지 주소가 *.dkr.ecr.*.amazonaws.com 이면 ecr-credential-provider 를 실행해
#   노드 역할(IMDS)로 ECR 토큰(12시간)을 받아 pull 한다. 토큰은 kubelet 이 알아서 다시 받는다 → Secret(imagePullSecrets) 불필요
#   KUBELET_EXTRA_ARGS 에 이미 있는 값(--node-ip 등)은 그대로 두고 두 플래그만 더한다. 여러 번 실행해도 같다
set -euo pipefail
BIN_DIR=/usr/local/libexec/kubelet-credential-providers
CONF=/etc/kubernetes/credential-provider.yaml
VERSIONS="v1.34.0 v1.33.0 v1.32.0 v1.31.0 v1.30.2"
echo "== $(hostname)"
sudo mkdir -p $BIN_DIR
if [ ! -x $BIN_DIR/ecr-credential-provider ]; then
  for v in $VERSIONS; do
    if sudo curl -fsSL -o $BIN_DIR/ecr-credential-provider \
       "https://storage.googleapis.com/k8s-staging-provider-aws/releases/$v/linux/amd64/ecr-credential-provider-linux-amd64"; then
      echo "  받음 ecr-credential-provider $v"; break; fi
  done
  sudo chmod 755 $BIN_DIR/ecr-credential-provider
fi
[ -x $BIN_DIR/ecr-credential-provider ] || { echo "ERROR: 바이너리 다운로드 실패"; exit 1; }
echo "  sha256 $(sha256sum $BIN_DIR/ecr-credential-provider | cut -c1-16)…  (두 worker 가 같아야 한다)"

sudo tee $CONF >/dev/null <<YAML
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
providers:
- name: ecr-credential-provider
  matchImages:
  - "*.dkr.ecr.*.amazonaws.com"
  defaultCacheDuration: "12h"
  apiVersion: credentialprovider.kubelet.k8s.io/v1
YAML
echo "  설정 $CONF (matchImages *.dkr.ecr.*.amazonaws.com)"

F=/etc/sysconfig/kubelet
add="--image-credential-provider-config=$CONF --image-credential-provider-bin-dir=$BIN_DIR"
cur=$(sudo sed -n 's/^KUBELET_EXTRA_ARGS=//p' $F 2>/dev/null | tr -d '"')
if [[ "$cur" == *image-credential-provider-config* ]]; then echo "  kubelet 플래그 이미 있음"
else
  echo "KUBELET_EXTRA_ARGS=\"${cur:+$cur }$add\"" | sudo tee $F >/dev/null
  echo "  kubelet 플래그 추가 (기존: ${cur:-없음})"
fi
sudo systemctl restart kubelet
sleep 3
echo "  kubelet $(systemctl is-active kubelet) · $(sudo cat $F)"
echo "  IMDS 역할 (노드에서 v2): $(T=$(curl -s -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token); curl -s -H "X-aws-ec2-metadata-token: $T" http://169.254.169.254/latest/meta-data/iam/security-credentials/)"
