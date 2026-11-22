#!/usr/bin/env bash
# shellcheck disable=SC2016
# ============================================================================
# step3.0 클러스터 삭제 — 만든 순서의 반대로 (되돌릴 수 없다)
#   인스턴스 → 보안 그룹 → 라우팅 테이블 → 서브넷 → 인터넷 게이트웨이 → VPC → 키 페어 · 개인 키
#   태그 Organization=bus · Project=step3 로 찾는다. 만들다 중간에 실패한 경우에도 쓸 수 있다
#   마지막에 남은 자원 수를 출력한다 (0 이면 요금이 남지 않는다)
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
check_aws

echo "${PREFIX} 의 EC2 3대 · 디스크 · 네트워크를 모두 지웁니다. 클러스터도 함께 사라지고 되돌릴 수 없습니다."
echo "쉬는 동안이면 stop-cluster.sh 를 쓰세요."
read -rp "지우려면 delete 를 입력: " ans
[[ $ans == delete ]] || { echo "취소"; exit 0; }

# 1) 인스턴스 (디스크는 DeleteOnTermination 으로 함께 지워진다)
mapfile -t IDS < <(aws ec2 describe-instances --filters "${TAG_FILTERS[@]}" \
  Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n' | sed '/^$/d')
if ((${#IDS[@]})); then
  aws ec2 terminate-instances --instance-ids "${IDS[@]}" >/dev/null
  aws ec2 wait instance-terminated --instance-ids "${IDS[@]}"
  log "terminated: ${IDS[*]}"
fi

VPC=$(vpc_id)
if [[ -n $VPC ]]; then
  # 2) 보안 그룹 (자기 자신을 참조하는 규칙이 있어도 그룹째 지우면 된다)
  for sg in $(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" \
      --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
    aws ec2 delete-security-group --group-id "$sg" && log "deleted: $sg"
  done
  # 3) 라우팅 테이블 (기본 테이블 제외)
  for rtb in $(aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC" \
      --query 'RouteTables[?!(Associations[?Main==`true`])].RouteTableId' --output text); do
    for assoc in $(aws ec2 describe-route-tables --route-table-ids "$rtb" \
        --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text); do
      aws ec2 disassociate-route-table --association-id "$assoc"
    done
    aws ec2 delete-route-table --route-table-id "$rtb" && log "deleted: $rtb"
  done
  # 4) 서브넷
  for sn in $(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC" --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --subnet-id "$sn" && log "deleted: $sn"
  done
  # 5) 인터넷 게이트웨이
  for igw in $(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$VPC" \
      --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC"
    aws ec2 delete-internet-gateway --internet-gateway-id "$igw" && log "deleted: $igw"
  done
  # 6) VPC
  aws ec2 delete-vpc --vpc-id "$VPC" && log "deleted: $VPC"
fi

# 7) 키 페어 · 개인 키 · 접속 설정
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  aws ec2 delete-key-pair --key-name "$KEY_NAME" && log "deleted: key pair $KEY_NAME"
fi
rm -f "$KEY_FILE" "$SSH_CONFIG" && log "deleted: $KEY_FILE · $SSH_CONFIG"

# 8) 남은 자원 확인
left_i=$(aws ec2 describe-instances --filters "${TAG_FILTERS[@]}" Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'length(Reservations[].Instances[])' --output text)
left_v=$(aws ec2 describe-volumes --filters "${TAG_FILTERS[@]}" --query 'length(Volumes)' --output text)
left_n=$(aws ec2 describe-vpcs --filters "${TAG_FILTERS[@]}" --query 'length(Vpcs)' --output text)
left_k=$(aws ec2 describe-key-pairs --filters "${TAG_FILTERS[@]}" --query 'length(KeyPairs)' --output text)
log "남은 자원: 인스턴스 ${left_i} · 디스크 ${left_v} · VPC ${left_n} · 키 페어 ${left_k}"
