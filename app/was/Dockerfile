# syntax=docker/dockerfile:1

# ============================================================================
# step2.3 이미지 크기 개선 — APP (FastAPI)
# step2.2(빌드 속도)에서 "무엇을 바탕으로, 무엇만 담나"를 바꿨다. 명령 순서 · 캐시 · 실행 사용자 원칙은 그대로.
#   - 바탕 이미지 python:3.14 (Debian 전체, 컴파일러 등 포함 1.7GB)  → python:3.14-alpine (step2.3 완료)
#   - 설치 도구 · 내려받기 흔적이 실행 이미지에 남음                   → 멀티스테이지 (step2.3 완료)
#   - .dockerignore 최소 (Dockerfile · __pycache__ 등이 이미지에 들어감) → 넓힘 (step2.3 완료)
# ============================================================================

# 두 스테이지가 같은 바탕을 쓰도록 한 곳에서 정한다
ARG PYTHON_IMAGE=python:3.14-alpine

# ---------- 1) build 스테이지: 부품 설치만 하는 곳 (최종 이미지에 들어가지 않는다) ----------
FROM ${PYTHON_IMAGE} AS build
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
# 부품을 가상환경 /opt/venv 한 폴더에 모아 설치한다 → 다음 스테이지로 이 폴더만 통째로 옮긴다
#   --without-pip: 가상환경 안에 pip(약 13MB)를 넣지 않는다. 설치는 바탕 이미지의 pip 가 --python 으로 대신 한다
RUN python -m venv --without-pip /opt/venv
COPY requirements.txt /tmp/requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    pip --python /opt/venv/bin/python install -r /tmp/requirements.txt

# ---------- 2) runtime 스테이지: 실행에 필요한 것만 ----------
FROM ${PYTHON_IMAGE} AS runtime
ENV PYTHONUNBUFFERED=1 \
    PATH=/opt/venv/bin:$PATH
WORKDIR /app

# 실행 사용자 (alpine은 useradd 대신 busybox의 addgroup · adduser)
#   -S: 시스템 계정, -D: 비밀번호 없음, -H: 홈 폴더 만들지 않음
RUN addgroup -S -g 10001 app \
 && adduser -S -D -H -u 10001 -G app -s /sbin/nologin app

# build 스테이지에서 설치해 둔 부품 폴더만 가져온다 (pip 캐시 · 설치 중 임시 파일은 따라오지 않는다)
COPY --from=build /opt/venv /opt/venv

EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/healthz', timeout=2)"

# 자주 바뀌는 소스는 맨 아래 (.dockerignore 로 문서 · Dockerfile · 캐시 파일은 빠진다)
COPY . /app/

USER 10001
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
