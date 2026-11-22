#!/usr/bin/env bash
# step2: 컨테이너 3개만 지운다. 네트워크(bus-net)와 데이터 볼륨(bus-db-data)은 남긴다 (다시 띄우면 즐겨찾기가 그대로).
# 데이터까지 모두 지우려면:  docker volume rm bus-db-data && docker network rm bus-net
docker rm -f web app db >/dev/null 2>&1 || true
echo "컨테이너 삭제: web app db (네트워크 bus-net · 볼륨 bus-db-data 는 유지)"
