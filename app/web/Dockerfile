# syntax=docker/dockerfile:1

# ============================================================================
# step2.3 이미지 크기 개선 — Web (Nginx: 화면 + /api 를 APP으로 넘김)
# step2.2에서 바탕 이미지만 바꿨다: Debian 기반 → Alpine 기반 최소판(alpine-slim). 비root · 8080은 그대로.
#   alpine-slim 에는 curl 이 없다 → 건강 검사는 busybox wget 으로
# ============================================================================

FROM nginxinc/nginx-unprivileged:1.30-alpine-slim

ENV APP_ADDR=app:8000
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1

# 설정 템플릿 → 시작할 때 ${APP_ADDR} 를 채워 conf.d/default.conf 를 만든다 (alpine-slim 에도 envsubst 가 있다)
COPY default.conf.template /etc/nginx/templates/default.conf.template

# 화면 파일 (맨 아래)
COPY html/ /usr/share/nginx/html/

USER 101
