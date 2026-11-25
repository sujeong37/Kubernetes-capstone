#!/usr/bin/env bash
# step4.5 — (WSL) RDS 로 바꾼 뒤 확인. 4.4 와 같은 방법(0.5초마다 ALB 요청 · 실패 수)으로
#   준비: app 이 보는 DB_HOST · 그 이름이 VPC 사설 주소로 풀리는지 · 클러스터 안 db 0개 · 옮긴 즐겨찾기(4.4 별칭)
#   ① app Pod 교체 → 별칭 그대로 · 실패 0
#   ② RDS 재부팅 (aws rds reboot-db-instance) → 4.4 ② db Pod 교체와 비교: 데이터 그대로, 끊긴 시간
#   STEP=1|2 로 하나만
set -euo pipefail
cd "$(dirname "$0")"; source ../lib.sh; need_aws
NS=bus; DB=bus-eks-db
[ "$(kubectl config current-context)" = bus-eks ] || die "context 가 bus-eks 가 아니다"
ADDR=$(cat ~/.bus-step4/alb); BASE="http://$ADDR"; STOP=${STOP_ID:-DJB8005901}   # migrate-rds.sh 가 「4.5 옮기기 전 시각」 별칭으로 등록한 대전역
api() { curl -s -m 5 -X "$1" "$BASE$2" -H 'Content-Type: application/json' ${3:+-d "$3"}; }
alias_now() { api GET /api/favorites | python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: print('(응답 없음)'); sys.exit()
print(next((f.get('alias') for f in d if f.get('nodeId')=='$STOP'),'(없음)'), '· 전체', len(d), '개')"; }
PF=$(mktemp)
pstart() { : >"$PF"; ( while :; do echo "$(date +%T) $(curl -s -o /dev/null -m 2 -w '%{http_code}' "$BASE/api/favorites")" >>"$PF"; sleep 0.5; done ) & PP=$!; }
pstop()  { kill $PP 2>/dev/null; wait $PP 2>/dev/null || true
  local n f; n=$(wc -l <"$PF"); f=$(grep -vc ' 200$' "$PF" || true)
  if [ "$f" -gt 0 ]; then say "  ALB 요청 $n · 실패 $f ($(grep -v ' 200$' "$PF" | head -1 | cut -d' ' -f1) ~ $(grep -v ' 200$' "$PF" | tail -1 | cut -d' ' -f1), 코드 $(grep -v ' 200$' "$PF" | awk '{print $2}' | sort | uniq -c | awk '{printf "%s×%s ",$2,$1}'))"
  else say "  ALB 요청 $n · 실패 0"; fi; }
trap 'kill ${PP:-0} 2>/dev/null || true; rm -f "$PF"' EXIT

say "== 준비 ($(date +%T))"
APP=$(kubectl get pod -n $NS -l app=app -o jsonpath='{.items[0].metadata.name}')
H=$(kubectl exec -n $NS "$APP" -c app -- printenv DB_HOST)
say "  app 의 DB_HOST = $H"
say "  app Pod 안에서 이름 풀기 → $(kubectl exec -n $NS "$APP" -c app -- python -c "import socket;print(socket.gethostbyname('$H'))")"
say "  클러스터 안 db: Deployment $(kubectl get deploy db -n $NS -o jsonpath='{.spec.replicas}')개 · Pod $(kubectl get pod -n $NS -l app=db --no-headers 2>/dev/null | wc -l)개 · PVC $(kubectl get pvc db-data -n $NS -o jsonpath='{.status.phase}') (되돌리기용으로 남김)"
say "  RDS $(aws rds describe-db-instances --db-instance-identifier $DB --query 'DBInstances[0].[DBInstanceStatus,AvailabilityZone,MultiAZ]' --output text | awk '{print $1" · "$2" · Multi-AZ "$3}')"
say "  즐겨찾기 $STOP 별칭 「$(alias_now)」"

if [ -z "${STEP:-}" ] || [ "$STEP" = 1 ]; then
say "== ① app Pod 교체 (rollout restart)"
t=$SECONDS; pstart
kubectl rollout restart deploy/app -n $NS >/dev/null; kubectl rollout status deploy/app -n $NS --timeout=5m >/dev/null; sleep 3; pstop
say "  $((SECONDS-t))초 · 별칭 「$(alias_now)」"
fi

if [ -z "${STEP:-}" ] || [ "$STEP" = 2 ]; then
say "== ② RDS 재부팅 (aws rds reboot-db-instance — 단일 AZ 라 그동안 끊긴다)"
t=$SECONDS; pstart
aws rds reboot-db-instance --db-instance-identifier $DB >/dev/null
sleep 10; aws rds wait db-instance-available --db-instance-identifier $DB
for i in $(seq 1 60); do curl -s -m 2 "$BASE/api/favorites" | grep -q "$STOP" && break; sleep 1; done
sleep 3; pstop
say "  available 까지 $((SECONDS-t))초 · 별칭 「$(alias_now)」"
say "  최근 이벤트: $(aws rds describe-events --source-identifier $DB --source-type db-instance --duration 15 --query 'Events[].Message' --output text | tr '\t' ',' )"
fi
say "== 끝 ($(date +%T))"
