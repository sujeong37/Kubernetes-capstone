#!/usr/bin/env bash
# step4.5 · 4.9 — (WSL) RDS 와 딸린 것 지우기. EKS 클러스터(VPC)보다 먼저 — 보안 그룹 · 서브넷 그룹이 VPC 안에 있다
#   최종 스냅샷 없이 지운다 (캡스톤 데이터, 필요하면 SNAPSHOT=1 로 bus-eks-db-final 을 남긴다 — 스냅샷도 요금)
#   지우기 전에 앱을 클러스터 안 db 로 되돌리려면: bash infra/step4/eks/apply-eks.sh (OVERLAY 기본 eks)
set -euo pipefail
cd "$(dirname "$0")"; source ../lib.sh; need_aws
DB=bus-eks-db; SG_NAME=bus-eks-rds-sg; SUBNET_GROUP=bus-eks-rds
if aws rds describe-db-instances --db-instance-identifier $DB >/dev/null 2>&1; then
  if [ "${SNAPSHOT:-0}" = 1 ]; then opt=(--final-db-snapshot-identifier $DB-final); else opt=(--skip-final-snapshot); fi
  aws rds delete-db-instance --db-instance-identifier $DB "${opt[@]}" --delete-automated-backups >/dev/null
  say "== DB 인스턴스 삭제 시작 (5~10분)"; aws rds wait db-instance-deleted --db-instance-identifier $DB; say "  삭제됨"
else say "== DB 인스턴스 없음"; fi
aws rds delete-db-subnet-group --db-subnet-group-name $SUBNET_GROUP 2>/dev/null && say "== 서브넷 그룹 삭제" || say "== 서브넷 그룹 없음"
SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values=$SG_NAME --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG" != None ]; then aws ec2 delete-security-group --group-id "$SG" && say "== 보안 그룹 $SG 삭제"; else say "== 보안 그룹 없음"; fi
rm -f ~/.bus-step4/rds
say "== 남은 것: $(aws rds describe-db-instances --query "DBInstances[?DBInstanceIdentifier=='$DB'] | length(@)" --output text)개 인스턴스 · 스냅샷 $(aws rds describe-db-snapshots --db-instance-identifier $DB --query 'length(DBSnapshots)' --output text 2>/dev/null || echo 0)개"
