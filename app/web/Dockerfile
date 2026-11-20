# syntax=docker/dockerfile:1

# 2-1 첫 Dockerfile — 1단계(WSL)에서 손으로 한 절차를 그대로 옮긴 가장 단순한 형태.
# 2-2 ~ 2-5 에서 Docker Core 4 · 5장을 하나씩 적용해 고친다. (변경 이력: docs/2-*.md)

# 1단계: sudo apt install nginx  → 베이스 이미지
FROM nginx:1.30-alpine

# 1단계: sudo cp app/web/nginx.conf /etc/nginx/sites-available/bus-app (+ 기본 사이트 끄기)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 1단계: sudo cp app/web/html/index.html /var/www/bus-app/
COPY html/ /var/www/bus-app/

# 실행 명령은 베이스 이미지의 것(nginx -g "daemon off;")을 그대로 쓴다
