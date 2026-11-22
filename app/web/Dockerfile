# syntax=docker/dockerfile:1

# ============================================================================
# step2.2 빌드 속도 개선 — Web (Nginx: 화면 + /api 를 APP으로 넘김)
# step2.1에서 명령 순서만 바꿨다: 바뀌지 않는 설정은 위로, 자주 바뀌는 화면 파일은 맨 아래로.
#   (Web은 설치 단계가 없어 시간 차이는 작다. APP과 같은 원칙으로 맞춰 둔다)
#   - 바탕 이미지가 Debian 기본판 → step2.3
# ============================================================================

# 바탕 이미지: Nginx 비root판 (UID 101, 포트 8080)
FROM nginxinc/nginx-unprivileged:1.30

# [step2.2] 바뀌지 않는 설정 · 포트 · 건강 검사는 위로
ENV APP_ADDR=app:8000
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fs http://127.0.0.1:8080/ > /dev/null || exit 1

# 설정 템플릿 (가끔 바뀜). 시작할 때 ${APP_ADDR} 를 채워 conf.d/default.conf 를 만든다
COPY default.conf.template /etc/nginx/templates/default.conf.template

# [step2.2] 화면 파일은 가장 자주 바뀌므로 맨 아래
COPY html/ /usr/share/nginx/html/

# 실행 사용자 (숫자)
USER 101

# 실행 명령은 바탕 이미지의 것 (/docker-entrypoint.sh → nginx -g "daemon off;")
