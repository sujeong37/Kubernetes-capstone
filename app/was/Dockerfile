# syntax=docker/dockerfile:1

# 2-1 첫 Dockerfile — 1단계(WSL)에서 손으로 한 절차를 그대로 옮긴 가장 단순한 형태.
# 2-2 ~ 2-5 에서 Docker Core 4 · 5장을 하나씩 적용해 고친다. (변경 이력: docs/2-*.md)

# 1단계: Python 설치          → 베이스 이미지
FROM python:3.14-slim

# 1단계: cd ~/k8s-capstone/app/was
WORKDIR /app

# 1단계: git clone (폴더 전체)
COPY . .

# 1단계: pip install -r requirements.txt
RUN pip install -r requirements.txt

# 1단계: uvicorn app:app --host 127.0.0.1 --port 8000
#        컨테이너 밖에서 접속해야 하므로 주소만 0.0.0.0 으로 바꿨다 (이유: docs/2-1-first-dockerfile.md)
CMD uvicorn app:app --host 0.0.0.0 --port 8000
