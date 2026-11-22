#!/usr/bin/env bash
# step2.2: APP 이미지 빌드 시간을 4가지 경우로 잰다.
#   (a) 처음 빌드     — 빌드 캐시를 모두 지운 뒤
#   (b) 바뀐 것 없음  — 바로 다시 빌드
#   (c) 소스 한 줄    — app.py 끝에 주석 한 줄을 붙였다가 되돌린다
#   (d) 부품 목록     — requirements.txt 끝에 주석 한 줄을 붙였다가 되돌린다 (부품은 그대로, 파일만 달라짐)
#
#   bash docker/measure-build.sh                              → 지금 Dockerfile (step2.2)
#   bash docker/measure-build.sh <Dockerfile 경로> <이름>      → 다른 Dockerfile (예: step2.1 비교)
#
# 주의: (a) 때문에 빌드 캐시(docker builder prune)를 지운다. 이미지 · 컨테이너 · 볼륨은 그대로다.
set -euo pipefail
cd "$(dirname "$0")/.."
DF="${1:-app/was/Dockerfile}"
NAME="${2:-step2.2}"
TAG="measure-$NAME"
LOGDIR="${TMPDIR:-/tmp}/measure-build-$NAME"
mkdir -p "$LOGDIR"

# 소스를 잠깐 고치므로, 끝나거나 중간에 멈춰도 원래대로 되돌린다
cp app/was/app.py "$LOGDIR/app.py.orig"
cp app/was/requirements.txt "$LOGDIR/requirements.txt.orig"
restore() {
  cp "$LOGDIR/app.py.orig" app/was/app.py
  cp "$LOGDIR/requirements.txt.orig" app/was/requirements.txt
}
trap restore EXIT

one() {  # one 기호 설명
  local log="$LOGDIR/$1.log" s e
  s=$(date +%s.%N)
  docker build --progress=plain -f "$DF" -t "bus-app:$TAG" app/was >"$log" 2>&1
  e=$(date +%s.%N)
  local steps cached dl
  steps=$( (grep -oE '^#[0-9]+ \[([a-z0-9-]+ )?[0-9]+/[0-9]+\]' "$log" || true) | sort -u | wc -l)
  cached=$(grep -cE '^#[0-9]+ CACHED' "$log" || true)
  dl=$(grep -cE 'Downloading .*\.(whl|tar\.gz)' "$log" || true)
  awk -v a="$1" -v b="$2" -v s="$s" -v e="$e" -v c="$cached" -v t="$steps" -v d="$dl" \
    'BEGIN { printf "| %s | %s | %.1f초 | %s / %s | %s |\n", a, b, e - s, c, t, d }'
}

echo "Dockerfile: $DF"
echo
echo "| 경우 | 내용 | 걸린 시간 | CACHED / 단계 | 내려받은 부품 |"
echo "|---|---|---|---|---|"
docker builder prune -af >/dev/null
one "(a)" "처음 빌드 (캐시 없음)"
one "(b)" "바뀐 것 없음"
echo "# measure $(date +%s)" >> app/was/app.py
one "(c)" "소스 한 줄 변경"
restore
echo "# measure $(date +%s)" >> app/was/requirements.txt
one "(d)" "부품 목록 파일 변경"
restore
echo
docker image ls "bus-app:$TAG"
echo "빌드 기록: $LOGDIR/(a)~(d).log"
