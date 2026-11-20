# syntax=docker/dockerfile:1

# 2-2 명령어 동작 확인 — 2-1(1단계 절차 그대로)에 Docker Core 4장 02의 명령을 적용했다.
#   ARG(FROM 앞) · LABEL · EXPOSE · HEALTHCHECK
# 2-3 ~ 2-5 에서 계속 고친다. (변경 이력: docs/2-*.md)

# [빌드 인자] 베이스 이미지 태그 (베이스 이미지의 ENV NGINX_VERSION 과 겹치지 않게 _TAG)
ARG NGINX_TAG=1.30-alpine

# 1단계: sudo apt install nginx → 베이스 이미지
FROM nginx:${NGINX_TAG}

# 1단계: sudo cp app/web/nginx.conf /etc/nginx/sites-available/bus-app (+ 기본 사이트 끄기)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 1단계: sudo cp app/web/html/index.html /var/www/bus-app/
COPY html/ /var/www/bus-app/

# ---- 실행 설정 ----

LABEL org.opencontainers.image.title="bus-web" \
      org.opencontainers.image.description="버스 도착 정보 Web (Nginx: 화면 + /api 프록시)" \
      org.opencontainers.image.source="https://github.com/sujeong37/Kubernetes-capstone"

# [포트 문서화] 베이스 이미지에도 EXPOSE 80 이 있지만, 이 이미지가 받는 포트를 직접 적어 둔다
EXPOSE 80

# [헬스체크] Nginx 자신이 화면(/)에 응답하는지 확인한다. /api 는 APP 상태라 여기서 검사하지 않는다
#            Alpine 의 busybox wget: 응답 코드가 오류면 종료 코드 1
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1/"]

# 실행 명령은 베이스 이미지의 것을 그대로 쓴다 (ENTRYPOINT /docker-entrypoint.sh, CMD nginx -g "daemon off;")
