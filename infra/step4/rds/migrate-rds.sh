#!/usr/bin/env bash
# step4.5 — (WSL) RDS 준비와 데이터 옮기기. 클러스터 안에 잠깐 mysql 클라이언트 Pod 를 띄워 VPC 안에서 RDS 에 붙는다
#   1. 접속 확인 (admin) — 버전 · TLS 강제 여부 · 접속한 곳
#   2. 표 만들기(app/db/init.sql 그대로) + 앱 계정 bus (SELECT · INSERT · UPDATE · DELETE 만, 비밀번호는 Secret bus-db 와 같은 값)
#   3. 데이터 옮기기: 클러스터 안 MySQL(EBS)의 favorites → RDS (mysqldump --replace, 여러 번 해도 같다)
#   4. bus 계정으로 확인 — 읽기는 되고 CREATE TABLE 은 ERROR 1142 (2단계 grants.sql 과 같은 최소 권한)
#   비밀번호는 Secret 으로만 Pod 에 넣는다 (화면 · 명령줄 인자에 없음). 끝나면 Pod · 임시 Secret 을 지운다
set -euo pipefail
cd "$(dirname "$0")"; source ../lib.sh; need_aws
ROOT=$(cd ../../.. && pwd); NS=bus; ENV_FILE=~/.bus-step4/bus.env
[ "$(kubectl config current-context)" = bus-eks ] || die "context 가 bus-eks 가 아니다"
HOST=$(cat ~/.bus-step4/rds 2>/dev/null) || die "~/.bus-step4/rds 가 없다 → create-rds.sh 먼저"
set -a; . "$ENV_FILE"; set +a
[ -n "${RDS_ADMIN_PASSWORD:-}" ] && [ -n "${DB_PASSWORD:-}" ] || die "$ENV_FILE 에 RDS_ADMIN_PASSWORD · DB_PASSWORD 가 없다"

cleanup() { kubectl delete pod rds-client -n $NS --ignore-not-found --wait=false >/dev/null 2>&1 || true
            kubectl delete secret bus-rds-admin -n $NS --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT

say "== 0. 클라이언트 Pod (mysql:8.4 · 비root · 비밀번호는 Secret 에서)"
kubectl create secret generic bus-rds-admin -n $NS --from-file=password=<(printf %s "$RDS_ADMIN_PASSWORD") \
  --dry-run=client -o yaml | kubectl apply --server-side -f - >/dev/null
kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: {name: rds-client, namespace: $NS, labels: {app: rds-client}}
spec:
  automountServiceAccountToken: false
  restartPolicy: Never
  securityContext: {runAsNonRoot: true, runAsUser: 999, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: mysql
    image: mysql:8.4
    command: ["sleep", "1800"]
    env:
    - {name: RDS_HOST, value: "$HOST"}
    - {name: ADMIN_PW, valueFrom: {secretKeyRef: {name: bus-rds-admin, key: password}}}
    - {name: BUS_PW, valueFrom: {secretKeyRef: {name: bus-db, key: password}}}
    securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
    resources: {requests: {cpu: 50m, memory: 128Mi}, limits: {memory: 256Mi}}
EOF
kubectl wait --for=condition=Ready pod/rds-client -n $NS --timeout=5m >/dev/null
say "  Ready · 노드 $(kubectl get pod rds-client -n $NS -o jsonpath='{.spec.nodeName} · Pod IP {.status.podIP}')"
admin() { kubectl exec -i -n $NS rds-client -- sh -c 'MYSQL_PWD="$ADMIN_PW" mysql -h "$RDS_HOST" -uadmin --table busdb'; }
bus()   { kubectl exec -i -n $NS rds-client -- sh -c 'MYSQL_PWD="$BUS_PW" mysql -h "$RDS_HOST" -ubus --table busdb'; }

say "== 1. 접속 확인 (admin) → $HOST"
admin <<'SQL' | sed 's/^/  /'
SELECT VERSION() AS version, @@require_secure_transport AS require_tls, CURRENT_USER() AS me, USER() AS from_where;
SQL

say "== 2. 표 · 앱 계정 bus"
{ cat "$ROOT/app/db/init.sql"
  echo "CREATE USER IF NOT EXISTS 'bus'@'%' IDENTIFIED BY '$DB_PASSWORD';"
  echo "ALTER USER 'bus'@'%' IDENTIFIED BY '$DB_PASSWORD';"
  echo "GRANT SELECT, INSERT, UPDATE, DELETE ON busdb.* TO 'bus'@'%';"
  echo "SHOW TABLES; SHOW GRANTS FOR 'bus'@'%';"; } | admin | sed 's/^/  /'

say "== 3. 데이터 옮기기 (클러스터 안 MySQL → RDS)"
if [ "$(kubectl get deploy db -n $NS -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = 1 ]; then
  # 옮겨졌는지 알아볼 표시: ALB(→ 지금의 클러스터 db)로 대전역을 등록하고 별칭에 시각을 적는다
  #   (시나리오 T9 는 KT북대전지사를 지우므로 겹치지 않는 정류장을 쓴다)
  BASE="http://$(cat ~/.bus-step4/alb)"; MARK="4.5 옮기기 전 $(date +%H:%M:%S)"
  curl -s -m 5 -X POST "$BASE/api/favorites" -H 'Content-Type: application/json' -d '{"nodeId":"DJB8005901","nodeName":"대전역"}' >/dev/null || true
  curl -s -m 5 -X PUT "$BASE/api/favorites/DJB8005901" -H 'Content-Type: application/json' -d "{\"alias\":\"$MARK\"}" >/dev/null
  say "  표시: ALB 로 DJB8005901 대전역 · 별칭 「$MARK」 (클러스터 db 에 저장)"
  src() { kubectl exec -i -n $NS deploy/db -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" '"$1"; }
  say "  클러스터 db: $(src 'mysql -uroot -N busdb -e "SELECT COUNT(*) FROM favorites"')행"
  src 'mysqldump -uroot --no-create-info --replace --skip-add-locks --skip-triggers --set-gtid-purged=OFF busdb favorites' 2>/dev/null | admin
  say "  RDS 로 옮긴 뒤:"
  echo "SELECT node_id, node_name, alias, updated_at FROM favorites ORDER BY created_at;" | admin | sed 's/^/  /'
else
  say "  클러스터 db 가 꺼져 있다 (이미 RDS 로 전환됨) → 건너뜀. RDS 지금 내용:"
  echo "SELECT node_id, node_name, alias, updated_at FROM favorites ORDER BY created_at;" | admin | sed 's/^/  /'
fi

say "== 4. bus 계정 (앱이 쓰는 계정 · Secret bus-db 의 비밀번호)"
echo "SELECT CURRENT_USER() AS me, COUNT(*) AS favorites FROM favorites;" | bus | sed 's/^/  /'
echo "CREATE TABLE hack (x INT);" | bus 2>&1 | grep -E '^ERROR' | sed 's/^/  CREATE TABLE → /' || true
say "== 다음: OVERLAY=eks-rds bash infra/step4/eks/apply-eks.sh --compare  →  OVERLAY=eks-rds bash infra/step4/eks/apply-eks.sh"
