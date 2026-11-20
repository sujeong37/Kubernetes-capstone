# syntax=docker/dockerfile:1

# [베이스 이미지] Nginx 1.30 안정 버전 (Alpine: 작은 리눅스)
FROM nginx:1.30-alpine

# [설정 템플릿] 시작할 때 환경 변수로 APP 주소를 채워 conf.d/default.conf 를 만든다 (기본 사이트 설정을 대체)
COPY default.conf.template /etc/nginx/templates/default.conf.template

# [화면 파일] Nginx 가 직접 응답하는 정적 파일
COPY html/ /usr/share/nginx/html/

# [설정 기본값] /api/ 요청을 넘길 APP 주소 (같은 네트워크의 APP 컨테이너 이름:포트)
ENV APP_ADDR=app:8000

# [포트 문서화] 컨테이너 안에서 Nginx 가 받는 포트
EXPOSE 80

# 실행 명령은 베이스 이미지의 것을 그대로 쓴다 (ENTRYPOINT /docker-entrypoint.sh, CMD nginx -g "daemon off;")
