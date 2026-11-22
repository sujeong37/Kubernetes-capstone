# syntax=docker/dockerfile:1

# ============================================================================
# step2.0 기본 형태 — APP (FastAPI)
# 일부러 가장 단순하게 썼다. 다음 단계에서 하나씩 고치고 전후를 숫자로 비교한다.
#   - root로 실행된다 (USER 없음)                                → step2.1
#   - 소스 전체를 먼저 복사하고 부품을 설치한다 (캐시 안 됨)       → step2.2
#   - 바탕 이미지가 공식 기본판(Debian 전체, 컴파일러 등 포함)     → step2.3
# ============================================================================

# 바탕 이미지: Python 공식 기본판
FROM python:3.14

# 이후 명령의 기준 폴더 (없으면 만든다)
WORKDIR /app

# 소스 폴더 전체를 복사한다 (.dockerignore 에 적은 것은 빠진다)
COPY . /app/

# 부품(라이브러리) 설치
RUN pip install -r requirements.txt

# 기본 환경 변수 — 로그를 버퍼 없이 바로 출력
# DB 주소 등 실행 설정은 docker/env.docker, 비밀번호 · 인증키는 실행할 때 -e 로 넣는다 (이미지에 넣지 않는다)
ENV PYTHONUNBUFFERED=1

# 쓰는 포트를 적어 둔다 (문서 역할. 실제로 여는 것은 docker run -p)
EXPOSE 8000

# Docker가 10초마다 /api/healthz 를 불러 건강한지 판단한다 → docker ps 에 (healthy)
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/healthz', timeout=2)"

# 컨테이너가 켜질 때 실행할 명령. 0.0.0.0: 컨테이너 밖(같은 네트워크의 web)에서 오는 요청을 받는다
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
