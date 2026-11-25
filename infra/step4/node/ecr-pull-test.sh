#!/usr/bin/env bash
# step4.0.3 — (cp 창) worker 마다 ECR 이미지로 시험 Pod 를 띄워 pull 되는지 + Pod 가 노드 역할에 닿지 못하는지
#   계정 ID 는 cp 의 IMDS(인스턴스 신원 문서)에서 읽고 화면에는 뒤 4자리만 → Git 에 계정 ID 를 넣지 않는다
set -euo pipefail
cd "$(dirname "$0")/../../.."   # 저장소 맨 위 (infra/step4/node → ../../..)
T=$(curl -s -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token)
ACC=$(curl -s -H "X-aws-ec2-metadata-token: $T" http://169.254.169.254/latest/dynamic/instance-identity/document | python3 -c 'import json,sys;print(json.load(sys.stdin)["accountId"])')
M="****${ACC: -4}"; hide() { sed -u "s/$ACC/$M/g"; }
exec > >(hide) 2>&1   # 오류 메시지까지 모든 출력에서 계정 ID 를 가린다
# 태그는 overlay(ec2-ecr)에 적힌 값을 쓴다 — cp 의 저장소는 얕은 clone 이라 git 기록으로는 못 구할 수 있다
TAG=$(awk '/newTag:/{print $2; exit}' k8s/overlays/ec2-ecr/kustomization.yaml)
[ -n "$TAG" ] || { echo "ERROR: k8s/overlays/ec2-ecr 에서 태그를 못 읽음 (git pull 했는지)"; exit 1; }
IMG="$ACC.dkr.ecr.ap-northeast-2.amazonaws.com/bus-web:$TAG"
echo "== 이미지 $M.dkr.ecr.ap-northeast-2.amazonaws.com/bus-web:$TAG"
for n in ${NODES:-worker1 worker2 cp}; do
  p=ecr-test-$n
  kubectl delete pod $p --ignore-not-found --wait >/dev/null
  kubectl run $p --image="$IMG" --image-pull-policy=Always --restart=Never \
    --overrides="{\"spec\":{\"nodeName\":\"$n\",\"tolerations\":[{\"operator\":\"Exists\"}]}}" \
    --command -- sleep 600 >/dev/null
  kubectl wait --for=condition=Ready pod/$p --timeout=40s >/dev/null 2>&1 && st=Running || st=$(kubectl get pod $p -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}')
  # 이유가 담긴 이벤트만 고른다: 성공이면 'Successfully pulled …', 실패면 'Failed to pull image …' 의 끝부분(원인)
  ev=$(kubectl get events --field-selector involvedObject.name=$p -o jsonpath='{range .items[*]}{.message}{"\n"}{end}')
  if [ "$st" = Running ]; then msg=$(grep -m1 'Successfully pulled' <<<"$ev" | sed 's/.*\(Successfully pulled\)/\1/; s/ image "[^"]*"//' | cut -c1-110)
  else msg=$(grep 'Failed to pull image' <<<"$ev" | tail -1 | sed 's/.*: //' | cut -c1-110); msg="원인: ${msg:-이벤트 없음}"; fi
  printf '  %-8s %-17s %s\n' $n "$st" "$msg"
done
echo "== 앱 Pod 는 노드 역할에 닿는가 (worker1 의 시험 Pod 안에서 IMDS)"
[ "$(kubectl get pod ecr-test-worker1 -o jsonpath='{.status.phase}')" = Running ] || { echo "  (worker1 시험 Pod 가 Running 이 아니라 건너뜀 — 설치 전에는 정상)"; NOEXEC=1; }
[ -n "${NOEXEC:-}" ] || kubectl exec ecr-test-worker1 -- sh -c 'wget -q -T 3 -O- http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>&1 || echo "v1 거절/응답 없음"' | sed 's/^/  v1: /' | hide
for n in ${NODES:-worker1 worker2 cp}; do kubectl delete pod ecr-test-$n --ignore-not-found --wait=false >/dev/null; done
echo "== 시험 Pod 지움"
