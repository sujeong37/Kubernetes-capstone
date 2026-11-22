# syntax=docker/dockerfile:1

# ============================================================================
# step2.1 root가 아닌 사용자로 실행 — Web (Nginx: 화면 + /api 를 APP으로 넘김)
# step2.0(기본 형태)에서 "누구로 실행하나"만 바꿨다.
#   - root(Nginx 마스터 프로세스) · 포트 80 → UID 101 · 포트 8080        (step2.1 완료)
#   - 바탕 이미지가 Debian 기본판                                   → step2.3
# ============================================================================

# [step2.1] 바탕 이미지: Nginx 공식 이미지의 비root판 (같은 Nginx 1.30, nginxinc 제공)
#   공식 nginx 이미지는 마스터 프로세스가 root로 떠서 80번을 열고 작업 프로세스만 낮은 권한으로 돈다.
#   비root판은 처음부터 UID 101(nginx)로 실행되도록 미리 바꿔 둔 이미지다:
#     pid 파일 · 임시 폴더를 /tmp 로, 설정 폴더(conf.d)를 101이 쓸 수 있게, USER 101, 포트 8080
FROM nginxinc/nginx-unprivileged:1.30

# 설정 템플릿. 시작할 때 ${APP_ADDR} 를 환경 변수 값으로 바꿔 conf.d/default.conf 를 만든다 (listen 8080)
COPY default.conf.template /etc/nginx/templates/default.conf.template

# 화면 파일 (root 소유 그대로 → nginx 사용자는 읽기만)
COPY html/ /usr/share/nginx/html/

# /api 요청을 넘길 APP 주소 (같은 네트워크의 컨테이너 이름:포트)
ENV APP_ADDR=app:8000

# [step2.1] 1024 아래 포트(80)는 root만 열 수 있다 → 8080
EXPOSE 8080

# Docker가 10초마다 첫 화면을 요청해 건강한지 판단한다
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fs http://127.0.0.1:8080/ > /dev/null || exit 1

# [step2.1] 바탕 이미지에 USER 101 이 이미 있지만, 이 이미지가 누구로 도는지 숫자로 직접 적어 둔다
USER 101

# 실행 명령은 바탕 이미지의 것을 그대로 쓴다 (/docker-entrypoint.sh → nginx -g "daemon off;")
