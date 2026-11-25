#!/usr/bin/env bash
# step4.5 — (WSL) Amazon RDS for MySQL 8.4 를 EKS 와 같은 VPC 의 사설 서브넷에 만든다. 여러 번 실행해도 같다 (있으면 건너뜀)
#   만드는 것: 보안 그룹 bus-eks-rds-sg (3306 ← EKS 클러스터 보안 그룹만) · DB 서브넷 그룹 bus-eks-rds (사설 2a · 2b)
#              · DB 인스턴스 bus-eks-db (db.t4g.micro · gp3 20GiB · 암호화 · 공개 접근 없음 · 단일 AZ · 자동 백업 1일)
#   admin 비밀번호는 무작위로 만들어 ~/.bus-step4/bus.env(600) 에 RDS_ADMIN_PASSWORD 로만 보관 — 화면 · 명령줄 · Git 에 없다
#   끝나면 주소를 ~/.bus-step4/rds 에 저장 → migrate-rds.sh → OVERLAY=eks-rds apply-eks.sh
set -euo pipefail
cd "$(dirname "$0")"; source ../lib.sh; need_aws
CLUSTER=bus-eks; DB=bus-eks-db; SG_NAME=bus-eks-rds-sg; SUBNET_GROUP=bus-eks-rds
ENV_FILE=~/.bus-step4/bus.env
t0=$SECONDS

say "== 1. EKS 의 VPC · 사설 서브넷 · 클러스터 보안 그룹"
VPC=$(aws eks describe-cluster --name $CLUSTER --query cluster.resourcesVpcConfig.vpcId --output text)
CLUSTER_SG=$(aws eks describe-cluster --name $CLUSTER --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)
# eksctl 이 사설 서브넷에 붙인 태그 (내부 로드밸런서용) 로 찾는다
mapfile -t SUBNETS < <(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC" Name=tag:kubernetes.io/role/internal-elb,Values=1 \
  --query 'Subnets[].[SubnetId,AvailabilityZone,CidrBlock]' --output text | sort -k2)
[ "${#SUBNETS[@]}" -ge 2 ] || die "사설 서브넷 2개를 못 찾음 (VPC $VPC)"
say "  VPC $VPC · 클러스터 보안 그룹 $CLUSTER_SG (Auto Mode 노드 = Pod 가 나가는 보안 그룹)"
for s in "${SUBNETS[@]}"; do say "  사설 서브넷 $s"; done

say "== 2. 보안 그룹 $SG_NAME — 3306 은 EKS 노드(클러스터 보안 그룹)에서만"
SG=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" Name=group-name,Values=$SG_NAME --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG" = None ]; then
  SG=$(aws ec2 create-security-group --group-name $SG_NAME --vpc-id "$VPC" --description "bus RDS: 3306 from EKS nodes only" \
       --tag-specifications "ResourceType=security-group,Tags=[{$PROJECT_TAG},{Key=Name,Value=$SG_NAME}]" --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id "$SG" \
    --ip-permissions "IpProtocol=tcp,FromPort=3306,ToPort=3306,UserIdGroupPairs=[{GroupId=$CLUSTER_SG,Description=EKS-nodes}]" >/dev/null
  say "  만듦 $SG"
else say "  있음 $SG"; fi
say "  들어오는 규칙: $(aws ec2 describe-security-groups --group-ids "$SG" --query 'SecurityGroups[0].IpPermissions[].[IpProtocol,FromPort,UserIdGroupPairs[].GroupId,IpRanges[].CidrIp]' --output text | tr '\n\t' '  ')"

say "== 3. DB 서브넷 그룹 $SUBNET_GROUP (RDS 는 영역 2개 이상을 요구)"
if aws rds describe-db-subnet-groups --db-subnet-group-name $SUBNET_GROUP >/dev/null 2>&1; then say "  있음"
else
  aws rds create-db-subnet-group --db-subnet-group-name $SUBNET_GROUP --db-subnet-group-description "bus EKS private subnets" \
    --subnet-ids $(printf '%s\n' "${SUBNETS[@]}" | awk '{print $1}') --tags "$PROJECT_TAG" >/dev/null
  say "  만듦"
fi

say "== 4. DB 인스턴스 $DB"
if aws rds describe-db-instances --db-instance-identifier $DB >/dev/null 2>&1; then
  say "  있음 — 상태 $(aws rds describe-db-instances --db-instance-identifier $DB --query 'DBInstances[0].DBInstanceStatus' --output text)"
else
  mkdir -p -m 700 ~/.bus-step4; touch "$ENV_FILE"; chmod 600 "$ENV_FILE"
  grep -q '^RDS_ADMIN_PASSWORD=' "$ENV_FILE" || echo "RDS_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)" >> "$ENV_FILE"
  VER=$(aws rds describe-db-engine-versions --engine mysql --engine-version 8.4 --default-only --query 'DBEngineVersions[0].EngineVersion' --output text 2>/dev/null || true)
  [[ "$VER" == 8.4.* ]] || VER=$(aws rds describe-db-engine-versions --engine mysql --query "DBEngineVersions[?starts_with(EngineVersion,'8.4.')].EngineVersion" --output text | tr '\t' '\n' | sort -V | tail -1)
  [[ "$VER" == 8.4.* ]] || die "MySQL 8.4 버전을 못 찾음"
  # 비밀번호를 명령줄 인자로 주지 않는다 (ps 에 보인다) → 600 임시 파일로 넘기고 바로 지운다
  IN=$(mktemp); trap 'rm -f "$IN"' EXIT
  python3 - "$IN" "$ENV_FILE" <<'PY'
import json,sys
pw=[l.split('=',1)[1].strip() for l in open(sys.argv[2]) if l.startswith('RDS_ADMIN_PASSWORD=')][0]
json.dump({"MasterUserPassword": pw}, open(sys.argv[1],'w'))
PY
  aws rds create-db-instance --db-instance-identifier $DB --engine mysql --engine-version "$VER" \
    --db-instance-class db.t4g.micro --allocated-storage 20 --storage-type gp3 --storage-encrypted \
    --master-username admin --cli-input-json "file://$IN" --db-name busdb \
    --db-subnet-group-name $SUBNET_GROUP --vpc-security-group-ids "$SG" --no-publicly-accessible --no-multi-az \
    --backup-retention-period 1 --copy-tags-to-snapshot --tags "$PROJECT_TAG" >/dev/null
  rm -f "$IN"
  say "  만들기 시작 — MySQL $VER (보통 5~10분)"
fi
aws rds wait db-instance-available --db-instance-identifier $DB
read -r HOST VER CLASS STYPE SIZE ENC PUB MAZ AZ < <(aws rds describe-db-instances --db-instance-identifier $DB \
  --query 'DBInstances[0].[Endpoint.Address,EngineVersion,DBInstanceClass,StorageType,AllocatedStorage,StorageEncrypted,PubliclyAccessible,MultiAZ,AvailabilityZone]' --output text)
echo "$HOST" > ~/.bus-step4/rds
say "  available · $((SECONDS-t0))초"
say "  주소 $HOST (~/.bus-step4/rds 에 저장)"
say "  MySQL $VER · $CLASS · $STYPE ${SIZE}GiB · 암호화 $ENC · 공개 접근 $PUB · Multi-AZ $MAZ · $AZ"
say "  admin 비밀번호: ~/.bus-step4/bus.env 의 RDS_ADMIN_PASSWORD ($(awk -F= '/^RDS_ADMIN_PASSWORD=/{print length($2)}' "$ENV_FILE")자) — 값은 출력하지 않는다"

say "== 5. 밖(내 WSL)에서 3306 — 막혀야 정상"
IP=$(getent hosts "$HOST" | awk '{print $1}')
say "  $HOST → ${IP:-?} (VPC 사설 주소)"
if timeout 5 bash -c "</dev/tcp/$HOST/3306" 2>/dev/null; then say "  연결됨 (예상과 다름 — 보안 그룹 확인)"; else say "  연결 안 됨 (사설 주소 · 공개 접근 없음 · 보안 그룹)"; fi
say "== 다음: bash infra/step4/rds/migrate-rds.sh"
