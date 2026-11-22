#!/usr/bin/env bash
# step2: 이미지 2개(APP · Web)를 만든다. DB는 공식 이미지 mysql:8.4 를 그대로 쓴다.
#   bash docker/build.sh                 → bus-app:step2.3, bus-web:step2.3 (현재 단계)
#   IMAGE_TAG=다른태그 bash docker/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${IMAGE_TAG:-step2.3}"

docker build -t "bus-app:$TAG" app/was
docker build -t "bus-web:$TAG" app/web
docker image ls --filter "reference=bus-*:$TAG"
