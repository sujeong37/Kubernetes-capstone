#!/usr/bin/env bash
# step3.13 — 3단계 최종 점검 (cp 에서 실행: bash k8s/step3/check.sh)
#   평가 기준 ③ 항목을 클러스터에서 직접 확인해 PASS / FAIL 로 보여 준다. 아무것도 바꾸지 않는다 (읽기만)
set -u
cd "$(dirname "$0")"
NS=bus; pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  [PASS] %-34s %s\n' "$1" "$2"; }
ng()  { fail=$((fail+1)); printf '  [FAIL] %-34s %s\n' "$1" "$2"; }
chk() { if [ "$2" = "$3" ]; then ok "$1" "$2"; else ng "$1" "$2 (기대: $3)"; fi; }
jp()  { kubectl get "$@" 2>/dev/null; }

echo "== 3단계 최종 점검 $(date '+%F %T')"

echo "-- 클러스터"
ready=$(jp nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep -c True)
chk "노드 Ready" "$ready/3" "3/3"

echo "-- 워크로드 (APP 여러 Pod · Probe · 롤링)"
for d in app web db; do
  r=$(jp deploy/$d -n $NS -o jsonpath='{.status.readyReplicas}/{.spec.replicas}')
  want=$(jp deploy/$d -n $NS -o jsonpath='{.spec.replicas}/{.spec.replicas}')
  chk "Deployment $d 준비" "${r:-0/?}" "$want"
done
nodes=$(jp pods -n $NS -l app=app -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | tr '\n' ' ')
[ "$(echo $nodes | wc -w)" -ge 2 ] && ok "app 분산 배치" "$nodes" || ng "app 분산 배치" "$nodes"
probes=$(jp deploy/app -n $NS -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path} {.spec.template.spec.containers[0].livenessProbe.httpGet.path}')
chk "app readiness · liveness" "$probes" "/api/healthz /api/healthz"
strat=$(jp deploy/app -n $NS -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}/{.spec.strategy.rollingUpdate.maxSurge}')
chk "롤링 maxUnavailable/maxSurge" "$strat" "0/1"
rev=$(kubectl rollout history deploy/app -n $NS 2>/dev/null | grep -cE '^[0-9]+ ')
[ "$rev" -ge 2 ] && ok "rollout history (롤백 가능)" "revision ${rev}개" || ng "rollout history" "$rev"

echo "-- 노출 (클러스터 밖 → web, DB 는 안에서만)"
chk "web Service" "$(jp svc/web -n $NS -o jsonpath='{.spec.type}:{.spec.ports[0].nodePort}')" "NodePort:30080"
chk "app Service" "$(jp svc/app -n $NS -o jsonpath='{.spec.type}')" "ClusterIP"
chk "db Service" "$(jp svc/db -n $NS -o jsonpath='{.spec.type}')" "ClusterIP"
chk "Gateway bus Programmed" "$(jp gateway/bus -n $NS -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')" "True"

echo "-- 데이터 · 설정 · 비밀"
chk "PVC db-data" "$(jp pvc/db-data -n $NS -o jsonpath='{.status.phase}')" "Bound"
chk "db 볼륨 = PVC" "$(jp deploy/db -n $NS -o jsonpath='{.spec.template.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}')" "db-data"
chk "ConfigMap bus-app-config" "$(jp cm/bus-app-config -n $NS -o jsonpath='{.data.DB_HOST}')" "db"
chk "Secret bus-db (클러스터에만)" "$(jp secret/bus-db -n $NS -o jsonpath='{.type}')" "Opaque"
chk "Git 의 Secret 수" "$(kubectl kustomize . | grep -c '^kind: Secret')" "0"

echo "-- 운영 · 보안 (선택 과제)"
for p in app web; do chk "PDB $p 여유" "$(jp pdb/$p -n $NS -o jsonpath='{.status.disruptionsAllowed}')" "1"; done
chk "NetworkPolicy 수" "$(jp networkpolicy -n $NS -o name | wc -l)" "4"
chk "app SA · 토큰 자동 마운트" "$(jp deploy/app -n $NS -o jsonpath='{.spec.template.spec.serviceAccountName}/{.spec.template.spec.automountServiceAccountToken}')" "app/false"
chk "metrics-server" "$(jp deploy/metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}')" "1"
kubectl diff -k . >/dev/null 2>&1; d=$?
chk "Git = 클러스터 (diff -k 종료 코드)" "$d" "0"

echo "-- 재시작 수 (참고)"
kubectl get pods -n $NS -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,RESTARTS:.status.containerStatuses[0].restartCount' --no-headers | sed 's/^/  /'

echo "== 결과: PASS $pass · FAIL $fail"
[ "$fail" -eq 0 ]
