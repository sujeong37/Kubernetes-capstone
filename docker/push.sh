#!/usr/bin/env bash
# step2: 이미지 2개를 linux/amd64 로 만들어 레지스트리에 올린다.
#   bash docker/push.sh <Docker Hub 계정>          예) bash docker/push.sh myid
#   bash docker/push.sh localhost:5001              연습용 내 컴퓨터 레지스트리
# 태그 2개: step2.1 (이 단계 최신, IMAGE_TAG 로 바꿈) + step2.1-<커밋 7자리> (어느 코드로 만들었는지 고정). latest 는 쓰지 않는다.
# EKS 노드는 x86_64(amd64)이므로 --platform linux/amd64 로 만든다.
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -eq 1 ] && [ -n "$1" ] || {
  echo "사용법: bash docker/push.sh <레지스트리/계정>   예) bash docker/push.sh sujeong79"
  echo "계정 자리가 비어 있다. \$DOCKERHUB_USER 를 썼다면 이 터미널에서 export DOCKERHUB_USER=아이디 를 먼저 한다."
  exit 1
}
case "$1" in /*|*/) echo "레지스트리/계정은 / 로 시작하거나 끝나지 않는다: '$1'"; exit 1;; esac
REG="$1"
TAG="${IMAGE_TAG:-step2.1}"
SHA=$(git rev-parse --short HEAD)

for pair in "bus-app:app/was" "bus-web:app/web"; do
  name="${pair%%:*}"; dir="${pair#*:}"
  docker buildx build --platform linux/amd64 \
    -t "$REG/$name:$TAG" -t "$REG/$name:$TAG-$SHA" --push "$dir"
done

echo
echo "== 올라간 이미지와 플랫폼"
for name in bus-app bus-web; do
  docker buildx imagetools inspect "$REG/$name:$TAG-$SHA" --format '{{range .Manifest.Manifests}}{{.Platform.OS}}/{{.Platform.Architecture}} {{end}}' \
    | sed "s#^#$REG/$name:$TAG-$SHA   #"
done
