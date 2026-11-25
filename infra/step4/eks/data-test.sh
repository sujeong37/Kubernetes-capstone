#!/usr/bin/env bash
# step4.4 — (WSL) 데이터 유지: 즐겨찾기 하나를 ALB 로 등록한 뒤 ① app Pod 교체 ② db Pod 교체 ③ db 가 있던 노드 교체
#   단계마다 같은 행이 남는지, EBS 볼륨 ID · 영역이 같은지, 그동안 ALB 요청이 몇 번 실패했는지 본다
#   STEP=1|2|3 으로 하나만. 3번(노드 교체)은 3~5분
set -euo pipefail
cd "$(dirname "$0")"; source ../lib.sh; need_aws
NS=bus
[ "$(kubectl config current-context)" = bus-eks ] || die "context 가 bus-eks 가 아니다"
ADDR=$(cat ~/.bus-step4/alb 2>/dev/null || kubectl get gateway bus -n $NS -o jsonpath='{.status.addresses[0].value}')
BASE="http://$ADDR"; STOP=${STOP_ID:-DJB8001795}; NAME=${STOP_NAME:-KT북대전지사}
api() { curl -s -m 5 -X "$1" "$BASE$2" -H 'Content-Type: application/json' ${3:+-d "$3"}; }
alias_now() { api GET /api/favorites | python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: print('(응답 없음)'); sys.exit()
items=d if isinstance(d,list) else d.get('favorites',d.get('items',[]))
print(next((f.get('alias') or '(별칭 없음)' for f in items if f.get('nodeId')=='$STOP'),'(없음)'))"; }
dbinfo() {  # db Pod · 노드 · 영역 · EBS 볼륨
  local p n z v
  p=$(kubectl get pod -n $NS -l app=db -o jsonpath='{.items[0].metadata.name}')
  n=$(kubectl get pod -n $NS "$p" -o jsonpath='{.spec.nodeName}')
  z=$(kubectl get node "$n" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
  v=$(kubectl get pv "$(kubectl get pvc db-data -n $NS -o jsonpath='{.spec.volumeName}')" -o jsonpath='{.spec.csi.volumeHandle}')
  echo "db Pod $p · 노드 $n · $z · EBS $v"
}
PF=$(mktemp)
pstart() { : >"$PF"; ( while :; do echo "$(date +%T) $(curl -s -o /dev/null -m 2 -w '%{http_code}' "$BASE/api/favorites")" >>"$PF"; sleep 0.5; done ) & PP=$!; }
pstop()  { kill $PP 2>/dev/null; wait $PP 2>/dev/null || true
  local n f; n=$(wc -l <"$PF"); f=$(grep -vc ' 200$' "$PF" || true)
  if [ "$f" -gt 0 ]; then say "  ALB 요청 $n · 실패 $f ($(grep -v ' 200$' "$PF" | head -1 | cut -d' ' -f1) ~ $(grep -v ' 200$' "$PF" | tail -1 | cut -d' ' -f1), 코드 $(grep -v ' 200$' "$PF" | awk '{print $2}' | sort | uniq -c | awk '{printf "%s×%s ",$2,$1}'))"
  else say "  ALB 요청 $n · 실패 0"; fi; }
trap 'kill ${PP:-0} 2>/dev/null || true; rm -f "$PF"' EXIT

say "== 준비 ($(date +%T)) · $BASE"
MARK="4.4 시험 $(date +%H:%M:%S)"
api DELETE "/api/favorites/$STOP" >/dev/null || true
api POST /api/favorites "{\"nodeId\":\"$STOP\",\"nodeName\":\"$NAME\"}" >/dev/null
api PUT "/api/favorites/$STOP" "{\"alias\":\"$MARK\"}" >/dev/null
say "  등록: $STOP $NAME · 별칭 「$(alias_now)」"
say "  $(dbinfo)"
BEFORE_VOL=$(dbinfo | awk '{print $NF}'); BEFORE_ZONE=$(dbinfo | awk '{print $(NF-3)}')

if [ "${STEP:-1}" = 1 ] || [ -z "${STEP:-}" ]; then
say "== ① app Pod 교체 (kubectl rollout restart — 새 Pod 2개로 하나씩)"
old=$(kubectl get pod -n $NS -l app=app -o jsonpath='{.items[*].metadata.name}'); t=$SECONDS; pstart
kubectl rollout restart deploy/app -n $NS >/dev/null; kubectl rollout status deploy/app -n $NS --timeout=5m >/dev/null; sleep 3; pstop
say "  전: $old"; say "  후: $(kubectl get pod -n $NS -l app=app --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}') · $((SECONDS-t))초"
say "  별칭 「$(alias_now)」"
fi

if [ "${STEP:-2}" = 2 ] || [ -z "${STEP:-}" ]; then
say "== ② db Pod 교체 (kubectl delete pod — DB 는 1개 · Recreate 라 잠깐 끊긴다)"
old=$(kubectl get pod -n $NS -l app=db -o jsonpath='{.items[0].metadata.name}'); t=$SECONDS; pstart
kubectl delete pod -n $NS "$old" >/dev/null
kubectl wait --for=condition=Ready pod -n $NS -l app=db --timeout=5m >/dev/null 2>&1 || true
kubectl rollout status deploy/db -n $NS --timeout=5m >/dev/null; sleep 5; pstop
say "  전: $old → 후: $(dbinfo) · $((SECONDS-t))초"
say "  별칭 「$(alias_now)」"
fi

if [ "${STEP:-3}" = 3 ] || [ -z "${STEP:-}" ]; then
node=$(kubectl get pod -n $NS -l app=db -o jsonpath='{.items[0].spec.nodeName}')
nc=$(kubectl get nodeclaim -o jsonpath="{range .items[?(@.status.nodeName=='$node')]}{.metadata.name}{end}")
[ -n "$nc" ] || die "db 노드 $node 의 NodeClaim 을 못 찾음 (kubectl get nodeclaim)"
say "== ③ 노드 교체 — db 가 있는 노드 $node (NodeClaim $nc) 삭제 → Auto Mode 가 비우고(drain) 새 노드"
say "  그 노드의 Pod: $(kubectl get pod -n $NS --field-selector spec.nodeName=$node -o jsonpath='{.items[*].metadata.name}')"
t=$SECONDS; pstart
kubectl delete nodeclaim "$nc" --wait=false >/dev/null
for i in $(seq 1 120); do
  p=$(kubectl get pod -n $NS -l app=db -o jsonpath='{.items[0].spec.nodeName} {.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)
  [ "${p%% *}" != "$node" ] && [ "${p##* }" = true ] && break; sleep 5
done
kubectl rollout status deploy/db -n $NS --timeout=2m >/dev/null; sleep 5; pstop
say "  $((SECONDS-t))초 · 후: $(dbinfo)"
say "  옛 노드 $node: $(kubectl get node "$node" --no-headers 2>/dev/null | awk '{print $2}' || true)$(kubectl get node "$node" >/dev/null 2>&1 || echo 사라짐)"
say "  별칭 「$(alias_now)」"
AFTER_VOL=$(dbinfo | awk '{print $NF}'); AFTER_ZONE=$(dbinfo | awk '{print $(NF-3)}')
say "  EBS 볼륨 $( [ "$AFTER_VOL" = "$BEFORE_VOL" ] && echo 같음 || echo 다름) · 영역 $BEFORE_ZONE → $AFTER_ZONE"
fi
say "== 끝: 처음 등록한 별칭 「$MARK」 → 지금 「$(alias_now)」"
