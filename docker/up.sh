#!/usr/bin/env bash
# step2: 네트워크 → DB → APP → Web 순서로 컨테이너 3개를 띄운다.
#   bash docker/up.sh                                  → 내 컴퓨터의 bus-app:step2.1 · bus-web:step2.1 (현재 단계)
#   IMAGE_TAG=step2 bash docker/up.sh                  → 이전 단계 이미지 (step2.0 의 web 은 컨테이너 포트 80)
#   IMAGE_PREFIX=<Docker Hub 계정>/ bash docker/up.sh  → 레지스트리의 이미지 (없으면 받아 온다)
#
# 비밀번호는 환경 변수 DB_ROOT_PASSWORD · DB_PASSWORD 로 받는다. 없으면 화면에 보이지 않게 입력받는다.
# 명령줄에 값을 쓰지 않도록 -e 이름 (값 없이) 으로 넘긴다 → 이 셸의 환경 변수 값이 들어간다.
# 공공 API 인증키(TAGO_SERVICE_KEY)가 환경 변수에 있으면 APP에 전달하고, 없으면 가짜 데이터로 동작한다.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${IMAGE_TAG:-step2.1}"
# web 컨테이너가 듣는 포트: step2.0 은 80(root), step2.1 부터 8080(비root)
WEB_PORT="${WEB_PORT:-$([ "$TAG" = step2 ] && echo 80 || echo 8080)}"
PREFIX="${IMAGE_PREFIX:-}"

[ -n "${DB_ROOT_PASSWORD:-}" ] || { read -rsp "DB root 비밀번호: " DB_ROOT_PASSWORD; echo; }
[ -n "${DB_PASSWORD:-}" ]      || { read -rsp "DB 비밀번호(bus): " DB_PASSWORD; echo; }
export MYSQL_ROOT_PASSWORD="$DB_ROOT_PASSWORD" MYSQL_PASSWORD="$DB_PASSWORD" DB_PASSWORD TAGO_SERVICE_KEY="${TAGO_SERVICE_KEY:-}"

wait_healthy() {  # wait_healthy 이름 최대초
  printf "%-4s 준비 대기" "$1"
  for _ in $(seq "$2"); do
    s=$(docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo none)
    [ "$s" = healthy ] && { echo " healthy"; return 0; }
    printf "."; sleep 1
  done
  echo " $s"; echo "준비되지 않았다. docker logs $1 로 확인한다."; return 1
}

# 0) 네트워크와 데이터 볼륨 (이미 있으면 그대로 쓴다)
docker network inspect bus-net >/dev/null 2>&1 || docker network create bus-net >/dev/null
docker volume create bus-db-data >/dev/null

# 1) DB — 데이터는 볼륨에, 첫 시작 때만 app/db/*.sql 실행. 포트는 밖으로 열지 않는다
docker run -d --name db --network bus-net --restart unless-stopped \
  -e MYSQL_ROOT_PASSWORD -e MYSQL_DATABASE=busdb -e MYSQL_USER=bus -e MYSQL_PASSWORD \
  -v bus-db-data:/var/lib/mysql \
  -v "$PWD/app/db:/docker-entrypoint-initdb.d:ro" \
  --health-cmd "mysqladmin ping -h 127.0.0.1 --silent" --health-interval 3s --health-retries 40 \
  mysql:8.4 >/dev/null
wait_healthy db 120

# 2) APP — 공통 설정은 env.docker, 비밀 값은 -e 이름 (이미지에는 없다)
docker run -d --name app --network bus-net --restart unless-stopped \
  --env-file docker/env.docker -e DB_PASSWORD -e TAGO_SERVICE_KEY \
  -p 127.0.0.1:8000:8000 \
  "${PREFIX}bus-app:$TAG" >/dev/null
wait_healthy app 60

# 3) Web — Nginx는 시작할 때 app 이름을 찾으므로 APP 다음에 띄운다. step2.1부터 컨테이너 포트 8080 (비root)
docker run -d --name web --network bus-net --restart unless-stopped \
  -p "127.0.0.1:8080:$WEB_PORT" \
  "${PREFIX}bus-web:$TAG" >/dev/null
wait_healthy web 60

docker ps --filter network=bus-net --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
