# syntax=docker/dockerfile:1

# ============================================================================
# step2.0 기본 형태 — Web (Nginx: 화면 + /api 를 APP으로 넘김)
# 일부러 가장 단순하게 썼다. 다음 단계에서 하나씩 고치고 전후를 숫자로 비교한다.
#   - root로 실행된다 (Nginx 마스터 프로세스), 포트 80                → step2.1
#   - 바탕 이미지가 공식 기본판(Debian)                             → step2.3
# ============================================================================

# 바탕 이미지: Nginx 공식 기본판
FROM nginx:1.30

# 설정 템플릿. 공식 이미지가 시작할 때 ${APP_ADDR} 를 환경 변수 값으로 바꿔 conf.d/default.conf 를 만든다
COPY default.conf.template /etc/nginx/templates/default.conf.template

# 화면 파일
COPY html/ /usr/share/nginx/html/

# /api 요청을 넘길 APP 주소 (같은 네트워크의 컨테이너 이름:포트). 실행할 때 -e 로 바꿀 수 있다
ENV APP_ADDR=app:8000

# 쓰는 포트
EXPOSE 80

# Docker가 10초마다 첫 화면을 요청해 건강한지 판단한다
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fs http://127.0.0.1/ > /dev/null || exit 1

# 실행 명령은 바탕 이미지의 것을 그대로 쓴다 (/docker-entrypoint.sh → nginx -g "daemon off;")
