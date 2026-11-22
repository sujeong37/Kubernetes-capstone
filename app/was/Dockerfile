# syntax=docker/dockerfile:1

# ============================================================================
# step2.2 빌드 속도 개선 — APP (FastAPI)
# step2.1(root가 아닌 사용자)에서 "명령 순서"와 "부품 내려받기 캐시"만 바꿨다. 바탕 이미지는 그대로.
#   - 소스 전체를 먼저 복사해서 코드 한 줄만 고쳐도 부품을 처음부터 다시 설치  → 순서 변경 (step2.2 완료)
#   - 부품 목록이 바뀌면 모든 부품을 인터넷에서 다시 내려받음              → 캐시 마운트 (step2.2 완료)
#   - 바탕 이미지가 공식 기본판(Debian 전체, 컴파일러 등 포함)                → step2.3
# 원칙: 잘 안 바뀌는 것은 위로, 자주 바뀌는 것(소스)은 맨 아래로.
#   Docker는 위에서부터 한 줄씩 "지난번과 같은가"를 보고, 처음 달라진 줄부터 아래를 전부 다시 만든다.
# ============================================================================

# 바탕 이미지: Python 공식 기본판 (step2.3에서 바꾼다)
FROM python:3.14

# [step2.2] 바뀌지 않는 설정은 위로 — 소스를 고쳐도 다시 만들지 않는다
#   PYTHONUNBUFFERED: 로그를 버퍼 없이 바로 출력
#   PIP_DISABLE_PIP_VERSION_CHECK: 빌드할 때 pip 새 버전 확인(인터넷 요청)을 하지 않는다
ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app

# [step2.2] 실행 사용자 만들기도 위로 (step2.1에서는 pip install 뒤였다)
RUN useradd --uid 10001 --user-group --no-create-home --shell /usr/sbin/nologin app

# [step2.2] 부품 목록만 먼저 복사 → 이 파일이 그대로면 아래 pip install 은 CACHED (몇 초 → 0초)
COPY requirements.txt /app/

# [step2.2] 캐시 마운트: pip가 내려받은 파일을 빌드 사이에 Docker 쪽에 보관해 둔다
#   부품 목록이 바뀌어 이 줄을 다시 실행해도, 이미 받은 부품은 인터넷에서 다시 받지 않는다
#   보관 장소는 이미지 밖이라 이미지에는 들어가지 않는다
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# 문서 역할 · 건강 검사도 소스와 상관없으므로 위로
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/healthz', timeout=2)"

# [step2.2] 자주 바뀌는 소스는 맨 아래 — 코드를 고치면 여기부터만 다시 만든다
COPY . /app/

# 이후 실행은 UID 10001 (숫자: Kubernetes runAsNonRoot 판단용)
USER 10001
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
