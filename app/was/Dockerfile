# syntax=docker/dockerfile:1

# 2-2 명령어 동작 확인 — 2-1(1단계 절차 그대로)에 Docker Core 4장 02의 명령을 적용했다.
#   ARG(FROM 앞) · LABEL · ENV(비밀 아닌 기본값) · EXPOSE · HEALTHCHECK
# 2-3 ~ 2-5 에서 계속 고친다. (변경 이력: docs/2-*.md)

# [빌드 인자] 베이스 이미지 태그. FROM 줄에서만 쓰인다 (이름이 베이스 이미지의 ENV PYTHON_VERSION 과 겹치지 않게 _TAG)
ARG PYTHON_TAG=3.14-slim

# 1단계: Python 설치 → 베이스 이미지
FROM python:${PYTHON_TAG}

# 1단계: cd ~/k8s-capstone/app/was
WORKDIR /app

# 1단계: git clone (폴더 전체)  — 2-4에서 고친다
COPY . .

# 1단계: pip install -r requirements.txt
RUN pip install -r requirements.txt

# ---- 여기부터는 파일을 바꾸지 않는 실행 설정 (이미지 설정에 기록, 층 크기 0B) ----

# [메타데이터] OCI 표준 키
LABEL org.opencontainers.image.title="bus-app" \
      org.opencontainers.image.description="버스 도착 정보 APP (FastAPI)" \
      org.opencontainers.image.source="https://github.com/sujeong37/Kubernetes-capstone"

# [설정 기본값] 비밀이 아닌 값만. DB_HOST=db 는 2-6에서 만들 DB 컨테이너 이름
# DB_PASSWORD · TAGO_SERVICE_KEY 는 넣지 않는다 — ENV/ARG 값은 inspect · history 로 누구나 볼 수 있다
ENV DB_HOST=db \
    DB_PORT=3306 \
    DB_NAME=busdb \
    CITY_CODE=25 \
    PYTHONUNBUFFERED=1

# [포트 문서화] APP이 받는 포트. 게시는 실행할 때 -p 로 한다
EXPOSE 8000

# [헬스체크] 10초마다 /api/healthz 요청. 실패(예외)하면 python 이 종료 코드 1로 끝난다
#            slim 이미지에는 curl 이 없어 python 표준 라이브러리로 요청한다
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/healthz', timeout=2)"]

# 1단계: uvicorn app:app --host 127.0.0.1 --port 8000  (주소만 0.0.0.0) — 셸 형식은 2-3에서 고친다
CMD uvicorn app:app --host 0.0.0.0 --port 8000
