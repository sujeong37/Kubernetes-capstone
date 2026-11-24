#!/usr/bin/env bash
# step4.1 — bus-eks 만들기 (약 15~20분). 점검 → eksctl create → context 이름 bus-eks → 요약
#   eksctl 출력에 계정 ID 가 섞여 나오므로 화면에는 뒤 4자리만 남긴다 (sed)
set -euo pipefail
cd "$(dirname "$0")"; source ../lib.sh; need_aws
CLUSTER=bus-eks
M="****${ACCOUNT: -4}"
say "== 점검"
command -v eksctl >/dev/null && command -v kubectl >/dev/null || die "bash infra/step4/eks/install-tools.sh 먼저"
if aws eks describe-cluster --name $CLUSTER >/dev/null 2>&1; then die "$CLUSTER 가 이미 있다 (status.sh 로 확인)"; fi
vpcs=$(aws ec2 describe-vpcs --query 'length(Vpcs)' --output text)
eips=$(aws ec2 describe-addresses --query 'length(Addresses)' --output text)
say "  VPC $vpcs/5 · 탄력적 IP $eips/5 (각각 1개씩 더 만든다)"
[ "$vpcs" -lt 5 ] && [ "$eips" -lt 5 ] || die "리전 한도 부족"
say "  계정 $M · 리전 $REGION · 클러스터 $CLUSTER · 점검 통과"

say "== 만들기 $(date +%T) — eksctl 이 CloudFormation 스택 2개(VPC · 역할 / 클러스터)를 만든다"
start=$SECONDS
eksctl create cluster -f cluster.yaml 2>&1 | sed -u "s/$ACCOUNT/$M/g"
say "== 걸린 시간 $(( (SECONDS-start)/60 ))분 $(( (SECONDS-start)%60 ))초"

ctx=$(kubectl config current-context)
[ "$ctx" = "$CLUSTER" ] || kubectl config rename-context "$ctx" "$CLUSTER" >/dev/null
kubectl config use-context "$CLUSTER" >/dev/null
say "== kubectl context: $CLUSTER"
bash ./status.sh
