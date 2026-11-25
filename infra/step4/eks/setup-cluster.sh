#!/usr/bin/env bash
# step4.2 — (WSL) 앱을 올리기 전 클러스터 단위 준비. 여러 번 실행해도 같은 상태가 된다
#   ① Gateway API 켜기 (EKS 가 CRD 를 설치 · 관리)   ② StorageClass ebs · GatewayClass eks-alb · NetworkPolicy 켜기
#   ③ namespace bus + Secret 2개 (비밀값은 Git 밖, 화면에는 이름 · 길이만)   ④ 상태 확인
set -euo pipefail
cd "$(dirname "$0")"; source ../lib.sh; need_aws
ROOT=$(cd ../../.. && pwd)
CLUSTER=bus-eks
command -v kubectl >/dev/null || die "bash infra/step4/eks/install-tools.sh 먼저"
st=$(aws eks describe-cluster --name $CLUSTER --query cluster.status --output text 2>/dev/null) || die "$CLUSTER 없음 → 4.1"
[ "$st" = ACTIVE ] || die "$CLUSTER 상태 $st (ACTIVE 가 아님)"
kubectl config use-context $CLUSTER >/dev/null 2>&1 || aws eks update-kubeconfig --name $CLUSTER --alias $CLUSTER >/dev/null
[ "$(kubectl config current-context)" = $CLUSTER ] || die "kubectl context 가 $CLUSTER 가 아니다"
say "== $CLUSTER ($(date '+%F %T')) · context $CLUSTER"

say "== ① Gateway API (EKS 관리형 CRD)"
gw=$(aws eks describe-cluster --name $CLUSTER --query 'cluster.kubernetesNetworkConfig.elasticLoadBalancing.gatewayApi.crds.managed' --output text 2>/dev/null || echo None)
if [ "$gw" = True ]; then say "  이미 켜짐 (managed=True)"
else
  t0=$SECONDS
  if ! uid=$(aws eks update-cluster-config --name $CLUSTER \
        --kubernetes-network-config '{"elasticLoadBalancing":{"enabled":true,"gatewayApi":{"crds":{"managed":true}}}}' \
        --query update.id --output text 2>&1); then
    say "  $uid"
    case "$uid" in *nknown*|*gatewayApi*) die "이 aws CLI($(aws --version | cut -d' ' -f1))는 gatewayApi(2026-10 기능)를 모른다 → bash infra/step4/install-aws-cli.sh --update 후 다시";; esac
    die "update-cluster-config 실패"
  fi
  say "  요청함 (update ${uid:0:8}…) — 끝날 때까지 기다린다"
  for i in $(seq 1 90); do
    s=$(aws eks describe-update --name $CLUSTER --update-id "$uid" --query update.status --output text)
    [ "$s" = InProgress ] || break; sleep 10
  done
  [ "$s" = Successful ] || die "update 상태 $s (aws eks describe-update --name $CLUSTER --update-id $uid)"
  say "  완료 $((SECONDS-t0))초"
fi
for i in $(seq 1 30); do kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 && break; sleep 10; done
kubectl wait --for condition=Established crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=5m >/dev/null
say "  CRD: $(kubectl get crd -o name | grep -c 'gateway.networking.k8s.io') 개 (gateway.networking.k8s.io) · 버전 $(kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}')"
say "  AWS 확장 (4.3 에서 ALB 설정에 씀): $(kubectl api-resources --api-group=gateway.k8s.aws -o name 2>/dev/null | tr '\n' ' ')"

say "== ② 클러스터 준비 (kubectl apply -k k8s/eks-cluster)"
kubectl apply -k "$ROOT/k8s/eks-cluster" | sed 's/^/  /'
kubectl wait --for=condition=Accepted gatewayclass/eks-alb --timeout=3m >/dev/null && say "  GatewayClass eks-alb Accepted"

say "== ③ namespace bus + Secret (ENV_FILE ~/.bus-step4/bus.env, 600)"
kubectl apply -f "$ROOT/k8s/step3/namespace.yaml" | sed 's/^/  /'
ENV_FILE="$HOME/.bus-step4/bus.env" bash "$ROOT/k8s/step3/create-secrets.sh" 2>&1 | sed 's/^/  /'

say "== ④ 상태"
say "  StorageClass:"; kubectl get storageclass | sed 's/^/    /'
say "  GatewayClass:"; kubectl get gatewayclass | sed 's/^/    /'
say "  NetworkPolicy 컨트롤러: $(kubectl get cm amazon-vpc-cni -n kube-system -o jsonpath='{.data.enable-network-policy-controller}')"
say "  Secret (bus): $(kubectl get secret -n bus -o name | tr '\n' ' ')"
say "  노드 $(kubectl get nodes --no-headers 2>/dev/null | wc -l)대 (Pod 가 없으면 0 — Auto Mode)"
