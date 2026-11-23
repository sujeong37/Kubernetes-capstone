#!/usr/bin/env bash
# shellcheck disable=SC2016
# ============================================================================
# step3.0 클러스터용 EC2 3대와 네트워크 만들기
#   VPC 192.168.0.0/16 → 인터넷 게이트웨이 → 서브넷 192.168.56.0/24 → 라우팅 테이블
#   → 보안 그룹(노드끼리 모두, 내 IP 에서만 22 · NodePort) → 키 페어 → 인스턴스 3대
#
#   bash infra/step3/ec2/create-cluster.sh
#
# 수업 스크립트(Kubernetes Core 01-04 부록 create-cluster.sh)에서 바꾼 것
#   - IMDSv2 만 · 홉 제한 1, IAM 역할 없음  → Pod 가 노드의 메타데이터(자격 증명)를 못 가져가게
#   - 디스크 DeleteOnTermination=true 명시   → 삭제 후 EBS 요금이 남지 않게
#   - ~/.bus-step3/ssh_config 생성           → ssh cp 로 접속 (공인 IP 가 바뀌어도)
#   - 이름 · 태그 bus-step3, 키는 레포 밖 ~/.bus-step3/
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

check_aws
[[ -z "$(vpc_id)" ]] || die "이미 ${PREFIX} VPC 가 있습니다. 다시 만들려면 delete-cluster.sh 먼저"

install -d -m 700 "$STATE_DIR"
# AWS 에 키 페어만 남고 개인 키 파일이 없으면 접속할 수 없다 → 아무것도 만들기 전에 멈춘다
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1 && [[ ! -f $KEY_FILE ]]; then
  die "AWS 에 $KEY_NAME 은 있는데 $KEY_FILE 이 없습니다. delete-cluster.sh 로 정리 후 다시"
fi
MY_IP="${MY_IP:-$(my_ip)}"

# 1) AMI — Rocky Linux 공식 계정(792107900819)의 Rocky 9 x86_64 최신
AMI=$(aws ec2 describe-images --owners 792107900819 \
  --filters 'Name=name,Values=Rocky-9-EC2-Base-9.*x86_64*' Name=architecture,Values=x86_64 Name=state,Values=available \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
[[ $AMI == ami-* ]] || die "Rocky Linux 9 AMI 를 찾지 못했습니다"
ROOT_DEV=$(aws ec2 describe-images --image-ids "$AMI" --query 'Images[0].RootDeviceName' --output text)
log "AMI: $AMI ($(aws ec2 describe-images --image-ids "$AMI" --query 'Images[0].Name' --output text))"

# 2) VPC (DNS 이름 켜기)
VPC=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" \
  --tag-specifications "$(tags vpc "${PREFIX}-vpc")" --query Vpc.VpcId --output text)
aws ec2 wait vpc-available --vpc-ids "$VPC"
aws ec2 modify-vpc-attribute --vpc-id "$VPC" --enable-dns-hostnames
log "VPC: $VPC ($VPC_CIDR)"

# 3) 인터넷 게이트웨이 — 패키지 받기 · SSH
IGW=$(aws ec2 create-internet-gateway \
  --tag-specifications "$(tags internet-gateway "${PREFIX}-igw")" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC"
log "IGW: $IGW"

# 4) 서브넷 — 노드가 놓이는 곳, 공인 IP 자동 할당
SUBNET=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block "$SUBNET_CIDR" --availability-zone "$AZ" \
  --tag-specifications "$(tags subnet "${PREFIX}-subnet-public-a")" --query Subnet.SubnetId --output text)
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET" --map-public-ip-on-launch
log "Subnet: $SUBNET ($SUBNET_CIDR, $AZ)"

# 5) 라우팅 테이블 — 0.0.0.0/0 → 인터넷 게이트웨이
RTB=$(aws ec2 create-route-table --vpc-id "$VPC" \
  --tag-specifications "$(tags route-table "${PREFIX}-rtb-public")" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$RTB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB" --subnet-id "$SUBNET" >/dev/null
log "Route table: $RTB"

# 6) 보안 그룹
#    노드끼리: 모든 프로토콜(-1). Calico IP-in-IP 는 IP 프로토콜 4 라서 "모든 TCP" 로는 Pod 통신이 안 된다
#    밖에서:   내 공인 IP 에서만 SSH(22) · NodePort(30000-32767). 6443(apiserver)은 밖에 열지 않는다
SG=$(aws ec2 create-security-group --vpc-id "$VPC" --group-name "${PREFIX}-sg-node" \
  --description "bus step3 nodes" \
  --tag-specifications "$(tags security-group "${PREFIX}-sg-node")" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG" \
  --ip-permissions "IpProtocol=-1,UserIdGroupPairs=[{GroupId=$SG}]" >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 22          --cidr "${MY_IP}/32" >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 30000-32767 --cidr "${MY_IP}/32" >/dev/null
log "Security group: $SG (노드끼리 전체 · SSH · NodePort 허용: ${MY_IP}/32)"

# 7) 키 페어 — 없을 때만 만든다 (수업 스크립트와 같음). 개인 키는 이 컴퓨터 ~/.bus-step3/ 에만 (권한 600)
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  rm -f "$KEY_FILE"                      # AWS 에 없는 키의 남은 로컬 파일
  umask 077
  aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type ed25519 \
    --tag-specifications "$(tags key-pair "$KEY_NAME")" --query KeyMaterial --output text > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  log "Key pair: $KEY_NAME → $KEY_FILE"
else
  log "Key pair: $KEY_NAME (이미 있음) → $KEY_FILE"
fi

# 8) 인스턴스 3대 — 사설 IP 고정, 호스트 이름 = 노드 이름
for n in "${NODES[@]}"; do
  USERDATA=$(printf '#cloud-config\nhostname: %s\nfqdn: %s\npreserve_hostname: false\n' "$n" "$n")
  aws ec2 run-instances --image-id "$AMI" --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" --subnet-id "$SUBNET" --security-group-ids "$SG" \
    --private-ip-address "${NODE_IP[$n]}" \
    --metadata-options HttpTokens=required,HttpPutResponseHopLimit=1,HttpEndpoint=enabled \
    --block-device-mappings "DeviceName=${ROOT_DEV},Ebs={VolumeSize=${DISK_GB},VolumeType=gp3,DeleteOnTermination=true}" \
    --user-data "$USERDATA" \
    --tag-specifications "$(tags instance "${PREFIX}-instance-${n}")" "$(tags volume "${PREFIX}-volume-${n}")" \
    --query 'Instances[0].InstanceId' --output text >/dev/null
  log "Instance: $n (${NODE_IP[$n]})"
done

log "실행 대기 중 ..."
mapfile -t IDS < <(for n in "${NODES[@]}"; do instance_id "$n"; done)
aws ec2 wait instance-running --instance-ids "${IDS[@]}"
write_ssh_config
print_table

cat <<EOF
접속 설정: $SSH_CONFIG
  처음 한 번: ~/.ssh/config 맨 위에  Include ~/.bus-step3/ssh_config
  그 뒤:      ssh cp · ssh worker1 · ssh worker2   (부팅 · SSH 준비에 1~2분 걸린다)
쉬는 동안:  bash infra/step3/ec2/stop-cluster.sh   (인스턴스 요금 없음, 디스크 요금만)
EOF
