#!/usr/bin/env bash
# step2: 띄워 둔 컨테이너로 테스트 시나리오 T1~T9 를 자동으로 확인한다.
# T7 다음에 컨테이너 3개를 모두 지우고 다시 띄운 뒤(down.sh → up.sh) T8(데이터 유지)을 확인한다.
#   bash docker/test.sh                                 → 내 컴퓨터의 이미지
#   IMAGE_PREFIX=<Docker Hub 계정>/ bash docker/test.sh  → 레지스트리의 이미지로 다시 띄움
set -euo pipefail
cd "$(dirname "$0")/.."
[ -n "${DB_ROOT_PASSWORD:-}" ] || { read -rsp "DB root 비밀번호: " DB_ROOT_PASSWORD; echo; }
[ -n "${DB_PASSWORD:-}" ]      || { read -rsp "DB 비밀번호(bus): " DB_PASSWORD; echo; }
export DB_ROOT_PASSWORD DB_PASSWORD
RESTART_CMD="bash docker/down.sh && bash docker/up.sh" bash tests/scenario.sh http://localhost:8080
