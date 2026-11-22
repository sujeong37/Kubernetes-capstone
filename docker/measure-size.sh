#!/usr/bin/env bash
# step2.3: APP 이미지 크기를 단계별로 만들어 비교한다. 한 번에 하나씩만 바꾼다.
#   A  step2.2 그대로                         (python:3.14, 단일 스테이지)
#   B  A 에서 바탕만 python:3.14-slim
#   C  B 에서 바탕만 python:3.14-alpine        (alpine 은 useradd 대신 addgroup · adduser)
#   D  step2.3                                (alpine + 멀티스테이지 + 가상환경에 pip 없음 + 넓힌 .dockerignore)
#
#   bash docker/measure-size.sh
#
# 만든 이미지: bus-app:size-A ~ size-D (끝나면 docker image rm 으로 지워도 된다)
set -euo pipefail
cd "$(dirname "$0")/.."
REF22="${REF22:-2467920}"          # step2.2 커밋
WORK="${TMPDIR:-/tmp}/measure-size"
mkdir -p "$WORK"

# A: step2.2 Dockerfile (git 기록에서 꺼낸다)
git show "$REF22:app/was/Dockerfile" > "$WORK/Dockerfile.A"
# B: 바탕만 slim
sed 's#^FROM python:3.14$#FROM python:3.14-slim#' "$WORK/Dockerfile.A" > "$WORK/Dockerfile.B"
# C: 바탕만 alpine (사용자 만들기 명령만 alpine 방식으로)
sed -e 's#^FROM python:3.14$#FROM python:3.14-alpine#' \
    -e 's#^RUN useradd --uid 10001 --user-group --no-create-home --shell /usr/sbin/nologin app$#RUN addgroup -S -g 10001 app \&\& adduser -S -D -H -u 10001 -G app -s /sbin/nologin app#' \
    "$WORK/Dockerfile.A" > "$WORK/Dockerfile.C"
# D: 지금 Dockerfile
cp app/was/Dockerfile "$WORK/Dockerfile.D"

for v in A B C D; do
  printf "빌드 %s ... " "$v"
  docker build -q -f "$WORK/Dockerfile.$v" -t "bus-app:size-$v" app/was >/dev/null
  echo "완료"
done

echo
echo "| 단계 | 바뀐 것 | 바탕 | DISK USAGE | CONTENT SIZE |"
echo "|---|---|---|---|---|"
row() {  # row 기호 설명 바탕 — docker image ls 의 DISK USAGE · CONTENT SIZE 두 칸을 옮긴다
  local sizes
  sizes=$(docker image ls "bus-app:size-$1" | awk -v n="bus-app:size-$1" '$1==n {print $3 " | " $4}')
  printf "| %s | %s | %s | %s |\n" "$1" "$2" "$3" "$sizes"
}
row A "step2.2 그대로" "python:3.14"
row B "바탕 → slim" "python:3.14-slim"
row C "바탕 → alpine" "python:3.14-alpine"
row D "+ 멀티스테이지 · venv(pip 없음) · .dockerignore" "python:3.14-alpine"
echo
docker image ls 'bus-app:size-*'
