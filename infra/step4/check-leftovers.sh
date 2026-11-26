#!/usr/bin/env bash
# step4.9 — (WSL) 서울 리전에 요금이 나올 수 있는 자원이 남았는지 한 번에 본다 (지우지 않는다, 읽기만)
#   모두 0 이면 끝. 기본 VPC(계정에 처음부터 있는 것)는 요금이 없어 세지 않는다
set -euo pipefail
cd "$(dirname "$0")"; source ./lib.sh; need_aws
n() { local c; c=$(eval "$2" 2>/dev/null | grep -cv '^\s*$' || true); printf '  %-34s %s\n' "$1" "$c"; [ "$c" = 0 ] || { eval "$2" 2>/dev/null | sed 's/^/      /'; LEFT=$((LEFT+c)); }; }
LEFT=0
say "== 남은 자원 ($REGION · 계정 $(mask "$ACCOUNT") · $(date '+%F %T'))"
n "EC2 인스턴스 (종료 안 된 것)"   "aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==\`Name\`]|[0].Value]' --output text"
n "EBS 볼륨"                       "aws ec2 describe-volumes --query 'Volumes[].[VolumeId,Size,State]' --output text"
n "EBS 스냅샷 (내 것)"             "aws ec2 describe-snapshots --owner-ids self --query 'Snapshots[].[SnapshotId,VolumeSize]' --output text"
n "로드 밸런서 (ALB · NLB)"        "aws elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,Type]' --output text"
n "로드 밸런서 (Classic)"          "aws elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text"
n "NAT 게이트웨이"                 "aws ec2 describe-nat-gateways --filter Name=state,Values=pending,available,deleting --query 'NatGateways[].[NatGatewayId,State]' --output text"
n "탄력적 IP"                      "aws ec2 describe-addresses --query 'Addresses[].[PublicIp,AllocationId]' --output text"
n "VPC (기본 VPC 제외)"            "aws ec2 describe-vpcs --filters Name=is-default,Values=false --query 'Vpcs[].[VpcId,CidrBlock,Tags[?Key==\`Name\`]|[0].Value]' --output text"
n "EKS 클러스터"                   "aws eks list-clusters --query 'clusters[]' --output text | tr '\t' '\n'"
n "RDS 인스턴스"                   "aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus]' --output text"
n "RDS 스냅샷 (수동)"              "aws rds describe-db-snapshots --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' --output text | tr '\t' '\n'"
n "ECR 리포지토리"                 "aws ecr describe-repositories --query 'repositories[].repositoryName' --output text | tr '\t' '\n'"
n "CloudFormation 스택"            "aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED ROLLBACK_COMPLETE CREATE_IN_PROGRESS DELETE_IN_PROGRESS --query 'StackSummaries[].[StackName,StackStatus]' --output text"
n "CloudWatch 로그 그룹 (eks · rds)" "aws logs describe-log-groups --query 'logGroups[?starts_with(logGroupName,\`/aws/eks\`) || starts_with(logGroupName,\`/aws/rds\`)].logGroupName' --output text | tr '\t' '\n'"
n "Secrets Manager 비밀"           "aws secretsmanager list-secrets --query 'SecretList[].Name' --output text | tr '\t' '\n'"
say "== (요금 없음 · 정리용) IAM 역할: $(aws iam list-roles --query "Roles[?starts_with(RoleName,'bus-') || starts_with(RoleName,'eksctl-bus-eks')].RoleName" --output text | tr '\t' ' ')"
if [ "$LEFT" = 0 ]; then say "== 남은 과금 자원 0"; else say "== 남은 것 $LEFT 개 — 위 목록 확인"; fi
