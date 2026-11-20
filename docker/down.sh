#!/usr/bin/env bash
# 2단계: 컨테이너만 지운다. 네트워크(bus-net)와 데이터 볼륨(bus-db-data)은 남긴다.
# 데이터까지 모두 지우려면:  docker volume rm bus-db-data && docker network rm bus-net
docker rm -f web app db >/dev/null 2>&1 || true
echo "컨테이너 삭제: web app db (볼륨 bus-db-data 는 유지)"
