#!/usr/bin/env bash
# step4.1 — 노드가 「저절로」 생기는지: 노드 0대에서 Pod 2개(요청 cpu 250m)를 올리면 Auto Mode 가 노드를 만든다
set -euo pipefail
C=bus-eks
k() { kubectl --context $C "$@"; }
echo "== 전: 노드 $(k get nodes --no-headers 2>/dev/null | wc -l)대"
start=$SECONDS
# 요청(requests)을 처음부터 넣어 한 번에 만든다 — create 후 set resources 를 하면 ReplicaSet 이 두 번 생긴다(4.1 첫 실행)
k create deployment node-test --image=registry.k8s.io/pause:3.10 --replicas=2 --dry-run=client -o yaml \
 | k set resources --local -f - --requests=cpu=250m,memory=64Mi -o yaml | k apply -f - >/dev/null
k rollout status deployment node-test --timeout=5m
echo "== Pod 2개 Running 까지 $((SECONDS-start))초"
k get pods -l app=node-test -o wide | sed 's/^/  /'
k get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type,karpenter.sh/capacity-type | sed 's/^/  /'
k get events --field-selector involvedObject.kind=Pod --sort-by=.lastTimestamp | grep -E 'node-test' | tail -6 | sed 's/^/  /'
k delete deployment node-test >/dev/null
echo "== 시험 Deployment 삭제 — 빈 노드는 Auto Mode 가 몇 분 뒤 스스로 정리한다 (status.sh 로 확인)"
