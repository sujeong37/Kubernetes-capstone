#!/usr/bin/env bash
# step4.0.2 — 같은 태그로 「내용이 다른」 이미지를 올리면 ECR 이 거절하는지 (IMMUTABLE 확인)
#   bus-web:<태그> 에 라벨 하나만 더한 이미지를 만들어 같은 태그로 push → 거절 기대
#   시험용 로컬 이미지는 지우고, ECR 의 원래 이미지(digest)가 그대로인지 확인한다
set -euo pipefail
cd "$(dirname "$0")/../../.."
source infra/step4/lib.sh; need_aws
M="****${ACCOUNT: -4}"; hide() { sed -u "s/$ACCOUNT/$M/g"; }
TAG=$(cat infra/step4/ecr/.last-tag 2>/dev/null) || die "push-images.sh 먼저"
ref="$REGISTRY/bus-web:$TAG"
before=$(aws ecr describe-images --repository-name bus-web --image-ids imageTag="$TAG" --query 'imageDetails[0].imageDigest' --output text)
say "== 전: bus-web:$TAG = ${before:0:19}…"
printf 'FROM %s\nLABEL immutable-test="%s"\n' "$ref" "$(date +%s)" | docker build -q -t "$ref" - >/dev/null
say "== 같은 태그, 다른 내용(라벨 추가)으로 push"
if docker push "$ref" 2>&1 | tail -3 | hide; then :; fi
after=$(aws ecr describe-images --repository-name bus-web --image-ids imageTag="$TAG" --query 'imageDetails[0].imageDigest' --output text)
say "== 후: bus-web:$TAG = ${after:0:19}…"
[ "$before" = "$after" ] && say "== 결과: 거절됨 — 태그가 가리키는 이미지는 그대로" || say "== 결과: 바뀌었다 (IMMUTABLE 이 아니다)"
docker rmi -f "$ref" >/dev/null; docker pull -q "$ref" | hide >/dev/null
say "== 로컬 시험 이미지 지우고 ECR 원본을 다시 받음"
