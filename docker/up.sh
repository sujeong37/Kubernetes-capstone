#!/usr/bin/env bash
# 2단계: DB → APP → Web 컨테이너를 순서대로 실행한다 (2-2 Runbook 4~6단계의 명령을 모은 것).
#
# 사용법:  bash docker/up.sh            (이미지 태그 basic)
#          TAG=opt bash docker/up.sh    (다른 태그의 이미지로 실행)
#
# 비밀번호는 환경 변수 DB_ROOT_PASSWORD · DB_PASSWORD 로 받는다. 없으면 화면에 보이지 않게 입력받는다.
# 공공 API 인증키(TAGO_SERVICE_KEY)가 환경 변수에 있으면 APP에 전달하고, 없으면 가짜 데이터로 동작한다.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${TAG:-basic}"

[ -n "${DB_ROOT_PASSWORD:-}" ] || { read -rsp "DB root 비밀번호: " DB_ROOT_PASSWORD; echo; }
[ -n "${DB_PASSWORD:-}" ]      || { read -rsp "DB 비밀번호(bus): " DB_PASSWORD; echo; }

# 네트워크와 볼륨은 한 번만 만든다 (이미 있으면 그대로 쓴다)
docker network inspect bus-net >/dev/null 2>&1 || docker network create bus-net >/dev/null
docker volume create bus-db-data >/dev/null

# 1) DB — 데이터는 볼륨에, 첫 시작 때만 app/db/*.sql 실행. 포트는 밖으로 열지 않는다
docker run -d --name db --network bus-net --restart unless-stopped \
  -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASSWORD" \
  -e MYSQL_DATABASE=busdb -e MYSQL_USER=bus -e MYSQL_PASSWORD="$DB_PASSWORD" \
  -v bus-db-data:/var/lib/mysql \
  -v "$PWD/app/db:/docker-entrypoint-initdb.d:ro" \
  --health-cmd "mysqladmin ping -h 127.0.0.1 --silent" --health-interval 5s --health-retries 30 \
  mysql:8.4 >/dev/null

printf "DB 준비 대기"
for _ in $(seq 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' db)" = healthy ] && break
  printf "."; sleep 2
done
status=$(docker inspect -f '{{.State.Health.Status}}' db)
echo " $status"
[ "$status" = healthy ] || { echo "DB가 준비되지 않았다. docker logs db 로 확인한다."; exit 1; }

# 2) APP — 비밀 값은 실행할 때 환경 변수로 넣는다 (이미지에는 없다)
docker run -d --name app --network bus-net --restart unless-stopped \
  -e DB_USER=bus -e DB_PASSWORD="$DB_PASSWORD" -e TAGO_SERVICE_KEY="${TAGO_SERVICE_KEY:-}" \
  "bus-app:$TAG" >/dev/null

# 3) Web — 바깥(브라우저)에 여는 것은 Web 하나, 호스트 8080 → 컨테이너 80
docker run -d --name web --network bus-net --restart unless-stopped -p 8080:80 \
  "bus-web:$TAG" >/dev/null

docker ps --filter network=bus-net --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
