# shellcheck shell=bash disable=SC2034,SC2054,SC2016
# ============================================================================
# step3.0 공통 설정 · 함수 — create / stop / start / delete-cluster.sh 가 source 한다
# 수업 Kubernetes Core 01-04 [부록] 클라우드 VM 실습 환경의 구성을 Bus 프로젝트에 맞췄다.
#   이름  {Organization}-{Project}-{capability}-{identity}  →  bus-step3-vpc, bus-step3-instance-cp ...
#   태그  Name · Organization=bus · Project=step3  (정지 · 기동 · 삭제는 두 태그로 자원을 찾는다)
#   비밀  개인 키 · ssh_config 는 레포 밖 ~/.bus-step3/ (권한 700 / 600)
# ============================================================================

ORG="bus"
PROJECT="step3"
PREFIX="${ORG}-${PROJECT}"

export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
export AWS_PAGER=""                      # aws 출력이 less 로 넘어가 멈추지 않게
AZ="${AZ:-${AWS_REGION}a}"

VPC_CIDR="192.168.0.0/16"
SUBNET_CIDR="192.168.56.0/24"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
DISK_GB=30

# 노드 이름 · 사설 IP (수업 로컬 VM 과 같게 고정 → 이후 수업 명령 · 출력을 그대로 쓴다)
NODES=(cp worker1 worker2)
declare -A NODE_IP=([cp]=192.168.56.10 [worker1]=192.168.56.11 [worker2]=192.168.56.12)

STATE_DIR="${HOME}/.bus-step3"           # 레포 밖. 키 · 접속 설정 · (3.2) join 명령
KEY_NAME="key-${PREFIX}"
KEY_FILE="${STATE_DIR}/${KEY_NAME}.pem"
SSH_CONFIG="${STATE_DIR}/ssh_config"

# 태그로 찾을 때 쓰는 필터
TAG_FILTERS=(Name=tag:Organization,Values="${ORG}" Name=tag:Project,Values="${PROJECT}")

log()  { printf '%s\n' "$*"; }
die()  { printf '오류: %s\n' "$*" >&2; exit 1; }

# 리소스 태그 (Name 은 자원마다 다르다)
tags() {   # tags <resource-type> <name>
  printf 'ResourceType=%s,Tags=[{Key=Name,Value=%s},{Key=Organization,Value=%s},{Key=Project,Value=%s}]' \
    "$1" "$2" "$ORG" "$PROJECT"
}

check_aws() {
  command -v aws >/dev/null || die "aws 명령이 없습니다 (Runbook 0번: AWS CLI v2 설치)"
  aws sts get-caller-identity --query Account --output text >/dev/null 2>&1 \
    || die "AWS 자격 증명이 없습니다 (aws configure 또는 aws sso login)"
}

my_ip() {   # 내 공인 IP (보안 그룹의 SSH · NodePort 허용 대상)
  local ip
  ip=$(curl -fsS --max-time 5 https://checkip.amazonaws.com | tr -d '[:space:]') || true
  [[ $ip =~ ^[0-9]+(\.[0-9]+){3}$ ]] || die "내 공인 IP를 확인하지 못했습니다 (MY_IP=x.x.x.x 로 직접 지정 가능)"
  printf '%s' "$ip"
}

vpc_id() {
  aws ec2 describe-vpcs --filters "${TAG_FILTERS[@]}" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null | sed 's/^None$//'
}

sg_id() {
  aws ec2 describe-security-groups --filters "${TAG_FILTERS[@]}" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null | sed 's/^None$//'
}

# 노드 이름 → 인스턴스 ID (상태 조건: 기본은 삭제된 것 제외)
instance_id() {   # instance_id <node> [state,...]
  local states="${2:-pending,running,stopping,stopped}"
  aws ec2 describe-instances --filters "${TAG_FILTERS[@]}" \
    Name=tag:Name,Values="${PREFIX}-instance-$1" Name=instance-state-name,Values="$states" \
    --query 'Reservations[].Instances[].InstanceId' --output text
}

print_table() {
  aws ec2 describe-instances --filters "${TAG_FILTERS[@]}" \
    Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'sort_by(Reservations[].Instances[], &PrivateIpAddress)[].[Tags[?Key==`Name`]|[0].Value, State.Name, PrivateIpAddress, PublicIpAddress]' \
    --output table
}

# ~/.bus-step3/ssh_config 를 현재 공인 IP 로 다시 쓴다 → ssh cp / ssh worker1 / ssh worker2
#   HostKeyAlias: 기동할 때마다 공인 IP 가 바뀌어도 호스트 키는 노드 이름으로 기억한다
write_ssh_config() {
  local n ip tmp
  tmp=$(mktemp)
  {
    echo "# bus-step3 노드 접속 — start-cluster.sh 가 공인 IP 를 갱신한다. ~/.ssh/config 맨 위에 Include 한 줄"
    for n in "${NODES[@]}"; do
      ip=$(aws ec2 describe-instances --filters "${TAG_FILTERS[@]}" \
            Name=tag:Name,Values="${PREFIX}-instance-${n}" Name=instance-state-name,Values=running \
            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
      [[ $ip == None || -z $ip ]] && continue
      cat <<EOF

Host ${n}
  HostName ${ip}
  User rocky
  IdentityFile ${KEY_FILE}
  IdentitiesOnly yes
  HostKeyAlias ${PREFIX}-${n}
  StrictHostKeyChecking accept-new
EOF
    done
  } > "$tmp"
  install -m 600 "$tmp" "$SSH_CONFIG"
  rm -f "$tmp"
}

# 보안 그룹의 "내 IP" 규칙(22 · NodePort)을 지금 IP 로 바꾼다 (집 · 학원 등 IP 가 바뀔 때)
update_my_ip_rules() {   # update_my_ip_rules <sg-id> <ip>
  local sg=$1 ip=$2 old
  for old in $(aws ec2 describe-security-groups --group-ids "$sg" \
      --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' --output text); do
    [[ $old == "${ip}/32" ]] && continue
    aws ec2 revoke-security-group-ingress --group-id "$sg" --protocol tcp --port 22 --cidr "$old" >/dev/null
    aws ec2 revoke-security-group-ingress --group-id "$sg" --protocol tcp --port 30000-32767 --cidr "$old" >/dev/null 2>&1 || true
  done
  aws ec2 authorize-security-group-ingress --group-id "$sg" --protocol tcp --port 22 --cidr "${ip}/32" >/dev/null 2>&1 || true
  aws ec2 authorize-security-group-ingress --group-id "$sg" --protocol tcp --port 30000-32767 --cidr "${ip}/32" >/dev/null 2>&1 || true
}
