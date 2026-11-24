#!/usr/bin/env bash
# step4.0.2 — 이미지 2개를 linux/amd64 로 빌드해 ECR 에 올린다 (WSL)
#   태그 = 소스(app/was · app/web)를 마지막으로 바꾼 커밋 7자리 → 같은 소스 = 같은 태그
#     (문서만 바뀐 커밋에서는 태그가 그대로라 다시 올리지 않는다. 이미 ECR 에 있으면 건너뜀)
#   빌드 재료에 커밋하지 않은 변경이 있으면 멈춘다 (태그가 내용을 대표하지 못하므로)
#   화면 · 로그에는 계정 ID 를 뒤 4자리만
set -euo pipefail
cd "$(dirname "$0")/../../.."
source infra/step4/lib.sh; need_aws
M="****${ACCOUNT: -4}"; hide() { sed -u "s/$ACCOUNT/$M/g"; }

[ -z "$(git status --porcelain -- app/was app/web)" ] || die "app/was · app/web 에 커밋하지 않은 변경이 있다 (git status)"
TAG=$(git log -1 --format=%h --abbrev=7 -- app/was app/web)
say "== 태그 $TAG ($(git log -1 --format=%s -- app/was app/web | cut -c1-60))"

say "== ECR 로그인 ($REGISTRY_MASKED)"
aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY" 2>&1 | grep -v -i warning | hide

start=$SECONDS
for pair in "bus-app:app/was" "bus-web:app/web"; do
  name=${pair%%:*}; dir=${pair#*:}; ref="$REGISTRY/$name:$TAG"
  if aws ecr describe-images --repository-name "$name" --image-ids imageTag="$TAG" >/dev/null 2>&1; then
    say "  있음 $name:$TAG — 건너뜀 (IMMUTABLE: 같은 태그는 다시 올릴 수 없다)"; continue
  fi
  say "== 빌드 $name ($dir, linux/amd64)"
  s=$SECONDS
  docker buildx build --platform linux/amd64 --load -t "$ref" "$dir" 2>&1 | tail -3 | hide
  say "== push $name:$TAG (빌드 $((SECONDS-s))초)"
  docker push "$ref" 2>&1 | grep -E 'digest|Pushed|exists' | tail -4 | hide
done
say "== 전체 $((SECONDS-start))초"

say "== 올라간 이미지"
printf '  %-8s %-8s %-12s %-6s %-8s %s\n' NAME TAG PLATFORM USER 'SIZE(MB)' DIGEST
for name in bus-app bus-web; do
  ref="$REGISTRY/$name:$TAG"
  plat=$(docker image inspect -f '{{.Os}}/{{.Architecture}}' "$ref" 2>/dev/null || echo "?")
  user=$(docker image inspect -f '{{.Config.User}}' "$ref" 2>/dev/null || echo "?")
  read -r size dig < <(aws ecr describe-images --repository-name "$name" --image-ids imageTag="$TAG" \
     --query 'imageDetails[0].[imageSizeInBytes,imageDigest]' --output text)
  printf '  %-8s %-8s %-12s %-6s %-8s %s\n' "$name" "$TAG" "$plat" "${user:-root}" "$((size/1024/1024))" "${dig:0:19}…"
done

say "== 스캔 (push 때 자동, 끝날 때까지 기다림)"
for name in bus-app bus-web; do
  aws ecr wait image-scan-complete --repository-name "$name" --image-id imageTag="$TAG" 2>/dev/null || true
  aws ecr describe-image-scan-findings --repository-name "$name" --image-id imageTag="$TAG" \
    --query 'imageScanStatus.status' --output text | sed "s/^/  $name $TAG 스캔 /"
  aws ecr describe-image-scan-findings --repository-name "$name" --image-id imageTag="$TAG" \
    --query 'imageScanFindings.findingSeverityCounts' --output json | tr -d '\n ' | sed "s/^/    심각도별 건수 /"; echo
done
echo "$TAG" > infra/step4/ecr/.last-tag
say "== 다음 단계에서 쓸 태그: $TAG (infra/step4/ecr/.last-tag)"
