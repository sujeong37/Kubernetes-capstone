#!/usr/bin/env bash
# step2.4: Compose 로 띄운 상태에서 시나리오 T1~T9. T7 뒤에 compose down → up 으로 모두 다시 띄우고 T8(데이터 유지) 확인.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -n "${DB_ROOT_PASSWORD:-}" ] || { read -rsp "DB root 비밀번호: " DB_ROOT_PASSWORD; echo; }
[ -n "${DB_PASSWORD:-}" ]      || { read -rsp "DB 비밀번호(bus): " DB_PASSWORD; echo; }
export DB_ROOT_PASSWORD DB_PASSWORD
RESTART_CMD="docker compose down && docker compose up -d --wait" bash tests/scenario.sh http://localhost:8080
