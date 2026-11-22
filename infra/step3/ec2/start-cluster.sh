#!/usr/bin/env bash
# ============================================================================
# step3.0 클러스터 기동 — cp 먼저, worker 2대 나중
#   사설 IP 는 그대로, 공인 IP 는 새로 받는다 → ssh_config 를 다시 쓴다
#   내 공인 IP 가 바뀌었으면(장소 이동 등) 보안 그룹의 SSH · NodePort 허용도 바꾼다
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
check_aws

start_nodes() {
  local ids=() n
  for n in "$@"; do
    mapfile -t -O "${#ids[@]}" ids < <(instance_id "$n" stopped,stopping | tr '\t' '\n' | sed '/^$/d')
  done
  if ((${#ids[@]})); then
    aws ec2 wait instance-stopped --instance-ids "${ids[@]}"   # 정지 중이면 끝날 때까지
    aws ec2 start-instances --instance-ids "${ids[@]}" >/dev/null
    aws ec2 wait instance-running --instance-ids "${ids[@]}"
  fi
  log "running: $(printf '%s · ' "$@" | sed 's/ · $//')"
}

start_nodes cp
start_nodes worker1 worker2

SG=$(sg_id); [[ -n $SG ]] || die "보안 그룹을 찾지 못했습니다"
MY_IP="${MY_IP:-$(my_ip)}"
update_my_ip_rules "$SG" "$MY_IP"
log "SSH · NodePort 허용: ${MY_IP}/32"

write_ssh_config
print_table
log "접속: ssh cp (SSH 준비에 1분쯤 걸릴 수 있다)"
