#!/usr/bin/env bash
# 테스트 시나리오 T1~T9 — 1~4단계에서 같은 시나리오로 확인한다.
#
# 사용법:  bash tests/scenario.sh [주소]
#   1단계 WSL         : bash tests/scenario.sh http://localhost
#   2단계 Docker      : bash tests/scenario.sh http://localhost:8080
#   3단계 kubeadm     : bash tests/scenario.sh http://<노드 공인 IP>:<NodePort>
#   4단계 EKS         : bash tests/scenario.sh http://<ALB 주소>
#
# T7까지 실행한 뒤 멈춘다. 그동안 APP과 DB를 재시작(3·4단계는 Pod 삭제)하고 Enter를 누르면
# T8(데이터 유지)과 T9(삭제)를 확인한다. 멈추지 않으려면 WAIT=0 을 앞에 붙인다.
# RESTART_CMD='명령' 을 주면 멈추는 대신 그 명령으로 재시작한다 (예: 2단계 docker/test.sh).
#
# 실제 공공 API(인증키)로 확인할 때 정류장을 바꾸려면 (기본값은 가짜 데이터와 같은 정류장):
#   SEARCH=검색어 STOP_ID=정류장ID STOP_NAME=정류장이름 bash tests/scenario.sh http://localhost

BASE="${1:-http://localhost}"
SEARCH="${SEARCH:-북대전}"
STOP="${STOP_ID:-DJB8001793}"
NAME="${STOP_NAME:-북대전농협}"
ALIAS="집 앞"
PASS=0; FAIL=0

check() {  # check 번호 설명 조건(0=통과) 실제값
  if [ "$3" -eq 0 ]; then echo "  [PASS] $1 $2"; PASS=$((PASS+1))
  else echo "  [FAIL] $1 $2"; echo "         실제: $(tr '\n' ' ' <<<"$4" | cut -c1-100)"; FAIL=$((FAIL+1)); fi
}
req() {  # req 메서드 경로 [본문] → 응답 본문, 마지막 줄에 상태 코드
  curl -s -m 10 -X "$1" "$BASE$2" -H 'Content-Type: application/json' ${3:+-d "$3"} -w '\n%{http_code}'
}
code() { tail -n1 <<<"$1"; }
enc() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
body() { sed '$d' <<<"$1"; }

echo "테스트 대상: $BASE   ($(date '+%Y-%m-%d %H:%M:%S'))"
req DELETE "/api/favorites/$STOP" >/dev/null   # 이전 실행 흔적 정리 (없어도 됨)

r=$(req GET /api/healthz)
check T1 "상태 확인        GET /api/healthz → 200, status ok" $([ "$(code "$r")" = 200 ] && grep -q '"status":"ok"' <<<"$(body "$r")"; echo $?) "$(code "$r") $(body "$r")"

r=$(req GET /)
check T2 "화면             GET / → 200, 버스 도착 정보" $([ "$(code "$r")" = 200 ] && grep -q '버스 도착 정보' <<<"$(body "$r")"; echo $?) "$(code "$r")"

r=$(req GET "/api/stops?name=$(enc "$SEARCH")")
check T3 "정류장 검색      GET /api/stops?name=$SEARCH → $NAME 포함" $([ "$(code "$r")" = 200 ] && grep -q "$NAME" <<<"$(body "$r")"; echo $?) "$(code "$r") $(body "$r")"

r=$(req GET "/api/arrivals/$STOP")
check T4 "도착 정보        GET /api/arrivals/$STOP → 버스 목록" $([ "$(code "$r")" = 200 ] && grep -q '"route"' <<<"$(body "$r")"; echo $?) "$(code "$r") $(body "$r")"

r=$(req POST /api/favorites "{\"nodeId\":\"$STOP\",\"nodeName\":\"$NAME\"}")
check T5 "등록             POST /api/favorites → 201" $([ "$(code "$r")" = 201 ]; echo $?) "$(code "$r") $(body "$r")"

r=$(req GET /api/favorites)
check T6 "조회             GET /api/favorites → 등록한 정류장" $([ "$(code "$r")" = 200 ] && grep -q "\"$STOP\"" <<<"$(body "$r")"; echo $?) "$(code "$r") $(body "$r")"

r=$(req PUT "/api/favorites/$STOP" "{\"alias\":\"$ALIAS\"}")
check T7 "수정             PUT /api/favorites/$STOP → alias=$ALIAS" $([ "$(code "$r")" = 200 ] && grep -q "$ALIAS" <<<"$(body "$r")"; echo $?) "$(code "$r") $(body "$r")"

if [ -n "${RESTART_CMD:-}" ]; then
  echo
  echo "  ▶ 재시작: $RESTART_CMD"
  bash -c "$RESTART_CMD" || { echo "  재시작 실패"; exit 1; }
elif [ "${WAIT:-1}" != 0 ]; then
  echo
  echo "  ▶ 지금 APP과 DB를 재시작(3·4단계는 Pod 삭제)한 뒤, 다시 실행되면 Enter를 누른다."
  read -r _
fi

r=$(req GET /api/favorites)
check T8 "데이터 유지      재시작 후 GET /api/favorites → alias=$ALIAS" $([ "$(code "$r")" = 200 ] && grep -q "$ALIAS" <<<"$(body "$r")"; echo $?) "$(code "$r") $(body "$r")"

r=$(req DELETE "/api/favorites/$STOP")
r2=$(req GET /api/favorites)
check T9 "삭제             DELETE → 204, 목록에서 사라짐" $([ "$(code "$r")" = 204 ] && ! grep -q "\"$STOP\"" <<<"$(body "$r2")"; echo $?) "$(code "$r") $(body "$r2")"

echo
echo "결과: 통과 $PASS / 9, 실패 $FAIL"
[ "$FAIL" -eq 0 ]
