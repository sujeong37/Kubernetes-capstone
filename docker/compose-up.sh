#!/usr/bin/env bash
# step2.4: 비밀번호를 화면에 보이지 않게 입력받아 docker compose 로 db · app · web 를 띄운다.
#   bash docker/compose-up.sh                     → 내 컴퓨터 이미지 (기본 태그 step2.3)
#   IMAGE_PREFIX=sujeong79/ bash docker/compose-up.sh → Docker Hub 이미지
set -euo pipefail
cd "$(dirname "$0")/.."
[ -n "${DB_ROOT_PASSWORD:-}" ] || { read -rsp "DB root 비밀번호: " DB_ROOT_PASSWORD; echo; }
[ -n "${DB_PASSWORD:-}" ]      || { read -rsp "DB 비밀번호(bus): " DB_PASSWORD; echo; }
export DB_ROOT_PASSWORD DB_PASSWORD TAGO_SERVICE_KEY="${TAGO_SERVICE_KEY:-}"
docker volume create bus-db-data >/dev/null      # 없으면 만든다 (compose.yaml 에서 external)
docker compose up -d --wait                      # --wait: 모든 서비스가 healthy 가 될 때까지 기다린다
docker compose ps
