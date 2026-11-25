#!/usr/bin/env bash
# step4.1 — 지금 상태와 요금이 붙는 자원 (계정 ID 는 가린다). 읽기만 한다
set -euo pipefail
cd "$(dirname "$0")"; source ../lib.sh; need_aws
CLUSTER=bus-eks
say "== 클러스터 $CLUSTER ($(date '+%F %T'))"
if ! aws eks describe-cluster --name $CLUSTER >/dev/null 2>&1; then say "  없음"; exit 0; fi
aws eks describe-cluster --name $CLUSTER --query 'cluster.[status,version,computeConfig.enabled,join(`,`,computeConfig.nodePools),storageConfig.blockStorage.enabled,kubernetesNetworkConfig.elasticLoadBalancing.enabled,resourcesVpcConfig.vpcId]' --output text \
 | awk '{printf "  상태 %s · 버전 %s · AutoMode compute %s (%s) · EBS %s · ELB %s · %s\n",$1,$2,$3,$4,$5,$6,$7}'
vpc=$(aws eks describe-cluster --name $CLUSTER --query cluster.resourcesVpcConfig.vpcId --output text)
say "== 노드 · Pod"
kubectl --context $CLUSTER get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type 2>/dev/null | sed 's/^/  /' || true
say "  Pod 전체 $(kubectl --context $CLUSTER get pods -A --no-headers 2>/dev/null | wc -l)개"
say "== 요금이 붙는 자원"
nat=$(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$vpc Name=state,Values=available --query 'length(NatGateways)' --output text)
lb=$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?VpcId=='$vpc'])" --output text)
ebs=$(aws ec2 describe-volumes --filters Name=tag-key,Values=kubernetes.io/created-for/pvc/name --query 'length(Volumes)' --output text)
# Auto Mode 노드는 EC2 관리형 인스턴스라 describe-instances 집계가 0으로 나왔다(4.1) → 노드 수는 kubectl 로 센다
inst=$(kubectl --context $CLUSTER get nodes --no-headers 2>/dev/null | wc -l)
printf '  %-22s %s\n' "EKS 클러스터" "1 (시간당 약 \$0.10)" "NAT 게이트웨이" "$nat (1개 시간당 약 \$0.06 + 처리 데이터)" "노드(EC2)" "$inst" "로드밸런서" "$lb" "EBS(PVC)" "$ebs"
