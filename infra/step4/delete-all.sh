#!/usr/bin/env bash
# step4.9 — (WSL) 4단계에서 만든 과금 자원을 CLI 로 모두 지운다. 지우는 순서가 중요하다 (VPC 안에 남은 것이 있으면 VPC 를 못 지운다)
#   1 RDS (4.5) → 2 앱 namespace bus (Gateway → ALB, PVC → EBS) → 3 EKS 클러스터 + VPC · NAT (eksctl) → 4 ECR
#   → 5 3단계 EC2 의 ECR 역할 떼기 · 역할 삭제 (EC2 자체는 수업 delete-cluster.ps1) → 6 남은 것 확인
#   되돌릴 수 없다. 처음에 지금 있는 것을 보여 주고 「delete」를 입력해야 시작한다. 다시 실행해도 된다 (없는 것은 건너뜀)
set -euo pipefail
cd "$(dirname "$0")"; source ./lib.sh; need_aws
HERE=$(pwd); CLUSTER=bus-eks; t0=$SECONDS
el() { printf '%dm%02ds' $(((SECONDS-t0)/60)) $(((SECONDS-t0)%60)); }

bash "$HERE/check-leftovers.sh" || true
say ""
read -rp "위 자원 중 4단계(bus-eks · RDS · ECR · 역할)를 모두 지운다. 계속하려면 delete 입력: " ans
[ "$ans" = delete ] || die "취소"

say "== 1. RDS ($(el))"
bash "$HERE/rds/delete-rds.sh" | sed 's/^/  /'

say "== 2. 앱 (namespace bus → ALB · EBS 가 지워질 때까지) ($(el))"
if aws eks describe-cluster --name $CLUSTER >/dev/null 2>&1; then
  aws eks update-kubeconfig --name $CLUSTER --alias $CLUSTER >/dev/null
  VPC=$(aws eks describe-cluster --name $CLUSTER --query cluster.resourcesVpcConfig.vpcId --output text)
  kubectl --context $CLUSTER delete namespace bus step42-test --ignore-not-found --wait=true --timeout=10m | sed 's/^/  /'
  for i in $(seq 1 60); do
    lb=$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?VpcId=='$VPC'])" --output text)
    pv=$(kubectl --context $CLUSTER get pv --no-headers 2>/dev/null | wc -l)
    [ "$lb" = 0 ] && [ "$pv" = 0 ] && break; sleep 10
  done
  say "  VPC 안 로드 밸런서 $lb · PV $pv"
  [ "$lb" = 0 ] || die "ALB 가 남아 있다 → aws elbv2 describe-load-balancers 확인 후 다시 실행"
else say "  클러스터 없음 — 건너뜀"; fi

say "== 3. EKS 클러스터 · VPC · NAT · IAM 역할 (eksctl, 10~15분) ($(el))"
if aws eks describe-cluster --name $CLUSTER >/dev/null 2>&1; then
  eksctl delete cluster -f "$HERE/eks/cluster.yaml" --wait 2>&1 | sed 's/^/  /'
else say "  클러스터 없음"; fi
STACKS=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED ROLLBACK_COMPLETE \
  --query "StackSummaries[?starts_with(StackName,'eksctl-$CLUSTER')].StackName" --output text)
for s in $STACKS; do say "  남은 스택 $s → 삭제"; aws cloudformation delete-stack --stack-name "$s"; aws cloudformation wait stack-delete-complete --stack-name "$s" || say "  $s 삭제 실패 — 콘솔 CloudFormation 이벤트 확인"; done
kubectl config delete-context $CLUSTER >/dev/null 2>&1 || true

say "== 4. ECR ($(el))"
for r in "${REPOS[@]}"; do
  if aws ecr delete-repository --repository-name "$r" --force >/dev/null 2>&1; then say "  $r 삭제 (이미지 포함)"; else say "  $r 없음"; fi
done

say "== 5. 3단계 EC2 에 붙인 ECR 읽기 역할 ($(el))"
ROLE=bus-step4-ec2-node-role
for a in $(aws ec2 describe-iam-instance-profile-associations --query "IamInstanceProfileAssociations[?ends_with(IamInstanceProfile.Arn,'/$ROLE')].AssociationId" --output text); do
  aws ec2 disassociate-iam-instance-profile --association-id "$a" >/dev/null; say "  인스턴스에서 떼어 냄 $a"
done
if aws iam get-role --role-name $ROLE >/dev/null 2>&1; then
  aws iam remove-role-from-instance-profile --instance-profile-name $ROLE --role-name $ROLE 2>/dev/null || true
  aws iam delete-instance-profile --instance-profile-name $ROLE 2>/dev/null || true
  aws iam detach-role-policy --role-name $ROLE --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>/dev/null || true
  aws iam delete-role --role-name $ROLE; say "  역할 · 인스턴스 프로파일 삭제"
else say "  역할 없음"; fi
ec2=$(aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running,stopping,stopped --query 'length(Reservations[].Instances[])' --output text)
[ "$ec2" = 0 ] || say "  ⚠ EC2 $ec2 대 남음 (3단계 kubeadm) → PowerShell 에서 수업 스크립트 .\\delete-cluster.ps1"

say "== 6. 확인 ($(el))"
bash "$HERE/check-leftovers.sh" || true
say "== 로컬 비밀 파일 ~/.bus-step4 (DB · RDS 비밀번호 · TAGO 키) 는 남겨 두었다. 필요 없으면: rm -rf ~/.bus-step4"
