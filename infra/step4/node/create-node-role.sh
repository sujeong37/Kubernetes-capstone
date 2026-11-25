#!/usr/bin/env bash
# step4.0.3 — (WSL) EC2 worker 2대에 「ECR 읽기 전용」 IAM 역할을 붙인다 + IMDS 를 v2 · 홉 1 로 잠근다
#   역할 bus-step4-ec2-node-role = 관리형 정책 AmazonEC2ContainerRegistryReadOnly 하나 (pull 만, push · 삭제 불가)
#   cp 에는 붙이지 않는다 — 앱 Pod 는 worker 에만 뜬다 (cp taint, 3.2)
#   IMDS: HttpTokens required(v1 금지) · 홉 1 → kubelet(노드)은 역할을 쓰지만 Pod 는 노드 역할에 닿지 못한다 (3.11 최소 권한 유지)
#   여러 번 실행해도 같다
set -euo pipefail
cd "$(dirname "$0")"; source ../lib.sh; need_aws
M="****${ACCOUNT: -4}"; hide() { sed -u "s/$ACCOUNT/$M/g"; }
ROLE=bus-step4-ec2-node-role
say "== 역할 $ROLE"
if ! aws iam get-role --role-name $ROLE >/dev/null 2>&1; then
  aws iam create-role --role-name $ROLE --tags Key=Project,Value=bus-capstone \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  say "  만듦 (신뢰: ec2.amazonaws.com)"
else say "  있음"; fi
aws iam attach-role-policy --role-name $ROLE --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
if ! aws iam get-instance-profile --instance-profile-name $ROLE >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name $ROLE >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name $ROLE --role-name $ROLE
  say "  인스턴스 프로파일 만듦 — IAM 전파를 15초 기다림"; sleep 15
fi
say "  정책: $(aws iam list-attached-role-policies --role-name $ROLE --query 'AttachedPolicies[].PolicyName' --output text)"

say "== worker 에 붙이기"
for n in worker1 worker2; do
  read -r id state < <(aws ec2 describe-instances --filters "Name=tag:Name,Values=*$n" "Name=instance-state-name,Values=running,stopped" \
     --query 'Reservations[0].Instances[0].[InstanceId,State.Name]' --output text)
  [ "$id" != "None" ] || die "$n 인스턴스를 못 찾음 (Name 태그가 …$n 인지)"
  cur=$(aws ec2 describe-iam-instance-profile-associations --filters Name=instance-id,Values=$id Name=state,Values=associated \
     --query 'IamInstanceProfileAssociations[0].IamInstanceProfile.Arn' --output text)
  if [ "$cur" = "None" ]; then
    aws ec2 associate-iam-instance-profile --instance-id $id --iam-instance-profile Name=$ROLE >/dev/null; act="붙임"
  elif [[ "$cur" == *"/$ROLE" ]]; then act="이미 붙어 있음"
  else die "$n 에 다른 역할이 있다: ${cur##*/}"; fi
  aws ec2 modify-instance-metadata-options --instance-id $id --http-tokens required --http-put-response-hop-limit 1 --http-endpoint enabled >/dev/null
  printf '  %-8s %s (%s) %s · IMDS v2만 · 홉 1\n' $n $id $state "$act"
done
say "== cp 는 역할 없음: $(aws ec2 describe-instances --filters 'Name=tag:Name,Values=*cp' 'Name=instance-state-name,Values=running,stopped' --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text | hide)"
