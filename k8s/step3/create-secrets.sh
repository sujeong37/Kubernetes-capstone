#!/usr/bin/env bash
# step3.4 — Secret 을 파일 없이 만든다 (cp 노드에서 실행). Git · Notion 에 비밀값을 남기지 않는다.
#   bus-db   : root-password · username(bus) · password  ← 처음이면 무작위로 만들어 ~/.bus-step3/bus.env(600) 에 보관
#   bus-tago : service-key  ← TAGO Decoding 키를 화면에 보이지 않게 입력 (비우면 가짜 데이터)
#   --server-side : 보통 apply 가 남기는 last-applied 주석에 비밀값이 한 번 더 저장되는 것을 막는다
set -euo pipefail
ENV_FILE="$HOME/.bus-step3/bus.env"
mkdir -p -m 700 "$(dirname "$ENV_FILE")"
if [ ! -f "$ENV_FILE" ]; then
  umask 077
  {
    echo "DB_ROOT_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)"
    echo "DB_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)"
  } > "$ENV_FILE"
  echo "비밀번호 2개를 새로 만들었다: $ENV_FILE"
fi
if ! grep -q '^TAGO_SERVICE_KEY=' "$ENV_FILE"; then
  read -rsp "TAGO Decoding 키 (없으면 Enter): " TAGO; echo
  echo "TAGO_SERVICE_KEY=$TAGO" >> "$ENV_FILE"; unset TAGO
fi
chmod 600 "$ENV_FILE"
set -a; . "$ENV_FILE"; set +a

kubectl create secret generic bus-db -n bus \
  --from-literal=root-password="$DB_ROOT_PASSWORD" \
  --from-literal=username=bus \
  --from-literal=password="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply --server-side -f -
kubectl create secret generic bus-tago -n bus \
  --from-literal=service-key="$TAGO_SERVICE_KEY" \
  --dry-run=client -o yaml | kubectl apply --server-side -f -

# 값은 출력하지 않는다 — 키 이름과 길이만
awk -F= '{print "  " $1 " (" length($2) "자)"}' "$ENV_FILE"
