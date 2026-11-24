#!/usr/bin/env bash
# step4.0.1 — ECR 리포지토리 bus-app · bus-web 만들기 (이미 있으면 설정만 맞춘다, 여러 번 실행해도 같다)
#   IMMUTABLE         : 같은 태그로 다시 push 하면 거절 → 「EC2 에서 검증한 태그 = EKS 에 올리는 이미지」 를 ECR 이 강제
#   scanOnPush        : push 할 때마다 OS 패키지 취약점(CVE) 기본 스캔
#   AES256            : 저장 암호화 (기본값이지만 드러낸다)
#   수명 주기 규칙      : 태그 없는 이미지 1일 후 삭제 · 나머지는 최근 10개만 → 저장 요금을 작게
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
need_aws
say "== ECR 리포지토리 (계정 $(mask "$ACCOUNT"), $REGION)"

POLICY='{"rules":[
 {"rulePriority":1,"description":"untagged 1 day","selection":{"tagStatus":"untagged","countType":"sinceImagePushed","countUnit":"days","countNumber":1},"action":{"type":"expire"}},
 {"rulePriority":2,"description":"keep last 10","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":10},"action":{"type":"expire"}}]}'

start=$SECONDS
for r in "${REPOS[@]}"; do
  if aws ecr describe-repositories --repository-names "$r" >/dev/null 2>&1; then
    aws ecr put-image-tag-mutability --repository-name "$r" --image-tag-mutability IMMUTABLE >/dev/null
    aws ecr put-image-scanning-configuration --repository-name "$r" --image-scanning-configuration scanOnPush=true >/dev/null
    say "  있음  $r (설정만 맞춤)"
  else
    aws ecr create-repository --repository-name "$r" \
      --image-tag-mutability IMMUTABLE \
      --image-scanning-configuration scanOnPush=true \
      --encryption-configuration encryptionType=AES256 \
      --tags "$PROJECT_TAG" >/dev/null
    say "  만듦  $r"
  fi
  aws ecr put-lifecycle-policy --repository-name "$r" --lifecycle-policy-text "$POLICY" >/dev/null
done
say "== $((SECONDS-start))초"

say "== 확인"
printf '  %-8s %-10s %-6s %-7s %-6s %s\n' NAME TAG SCAN ENCRYPT RULES URI
for r in "${REPOS[@]}"; do
  read -r mut scan enc < <(aws ecr describe-repositories --repository-names "$r" \
    --query 'repositories[0].[imageTagMutability,imageScanningConfiguration.scanOnPush,encryptionConfiguration.encryptionType]' --output text)
  rules=$(aws ecr get-lifecycle-policy --repository-name "$r" --query lifecyclePolicyText --output text | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["rules"]))')
  printf '  %-8s %-10s %-6s %-7s %-6s %s\n' "$r" "$mut" "$scan" "$enc" "$rules" "$REGISTRY_MASKED/$r"
done
