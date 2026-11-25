#!/usr/bin/env bash
# step4.0.3 — (cp 창) overlay ec2-ecr 적용: ACCOUNT_ID 자리를 IMDS 의 계정 ID 로 바꿔 apply (화면에는 가림)
#   --diff 만 주면 바뀔 줄만 보여 주고 적용하지 않는다
set -euo pipefail
cd "$(dirname "$0")/../.."
T=$(curl -s -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token)
ACC=$(curl -s -H "X-aws-ec2-metadata-token: $T" http://169.254.169.254/latest/dynamic/instance-identity/document | python3 -c 'import json,sys;print(json.load(sys.stdin)["accountId"])')
M="****${ACC: -4}"; hide() { sed -u "s/$ACC/$M/g"; }
exec > >(hide) 2>&1   # 오류 메시지까지 모든 출력에서 계정 ID 를 가린다
render() { kubectl kustomize k8s/overlays/ec2-ecr | sed "s/ACCOUNT_ID/$ACC/g"; }
if [ "${1:-}" = "--diff" ]; then render | kubectl diff -f - | grep -E '^[-+] ' | hide; exit 0; fi
render | kubectl apply -f - | grep -v unchanged | hide
kubectl rollout status deploy/app -n bus && kubectl rollout status deploy/web -n bus
kubectl get pods -n bus -l 'app in (app,web)' -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,IMAGE:.spec.containers[0].image,IMAGEID:.status.containerStatuses[0].imageID' | hide
