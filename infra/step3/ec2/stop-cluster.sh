#!/usr/bin/env bash
# ============================================================================
# step3.0 클러스터 정지 — worker 2대 먼저, cp 마지막
#   Control Plane 이 마지막까지 동작해야 worker 가 정상적으로 빠진다 (수업 vagrant halt 와 같은 순서)
#   정지 중: 인스턴스 요금 없음, 디스크(EBS) 요금만
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
check_aws

stop_nodes() {   # stop_nodes <이름...>
  local ids=() n
  for n in "$@"; do
    mapfile -t -O "${#ids[@]}" ids < <(instance_id "$n" pending,running | tr '\t' '\n' | sed '/^$/d')
  done
  if ((${#ids[@]})); then
    aws ec2 stop-instances --instance-ids "${ids[@]}" >/dev/null
    aws ec2 wait instance-stopped --instance-ids "${ids[@]}"
  fi
  log "stopped: $(printf '%s · ' "$@" | sed 's/ · $//')"
}

stop_nodes worker1 worker2
stop_nodes cp
print_table
