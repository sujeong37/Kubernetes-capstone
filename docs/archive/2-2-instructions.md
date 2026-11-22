# 2-2 명령어 동작 확인

Docker Core 4장 02(명령어 체계)와 그 실습 lab01(명령어 동작 확인) · lab02(EXPOSE와 HEALTHCHECK)를 우리 앱에 적용한다.
먼저 명령의 동작을 우리 이미지(`bus-app:2.1`)로 확인하고, 그 결과에 따라 APP · Web Dockerfile에 ARG · LABEL · ENV · EXPOSE · HEALTHCHECK를 넣어 `2.2`를 만든다.

## 1. 명령의 분류 — 층을 만드는 명령과 설정만 기록하는 명령

| 효과 | 명령 | `docker history` 크기 | 우리 Dockerfile |
|---|---|---|---|
| 파일시스템 변경 → 층 생성 | COPY, ADD, RUN | 0B 아님 | `COPY . .`, `RUN pip install` |
| 실행 조건 → 이미지 설정 | ENV, WORKDIR, USER, EXPOSE, HEALTHCHECK, STOPSIGNAL, CMD, ENTRYPOINT | 0B | 2-2에서 ENV · EXPOSE · HEALTHCHECK 추가 |
| 메타데이터 | LABEL | 0B | 2-2에서 추가 |
| 빌드 인자 | ARG | 0B | 2-2에서 FROM 앞에 추가 |

## 2. 명령 동작 확인 (bus-app:2.1 위에서 실험, 표준 입력 Dockerfile)

| 실험 | 결과 | 우리 Dockerfile에 반영 |
|---|---|---|
| `ARG BUILD_NOTE` + `ENV APP_MODE` 를 RUN에서 사용 | 빌드 중에는 둘 다 쓰인다. 컨테이너 `env` 에는 `APP_MODE` 만 남고, `-e APP_MODE=production` 으로 바뀐다. `docker history` 의 ARG 행 · `RUN \|1 BUILD_NOTE=...` 행에 ARG 값이 남는다 | 실행 설정은 ENV, 빌드에만 쓰는 값은 ARG |
| `--build-arg DB_PASSWORD=fake-pass-1234` + `ENV DB_PASSWORD=${DB_PASSWORD}` | 빌드는 성공하지만 경고 2개 `SecretsUsedInArgOrEnv` (ARG · ENV). `history --no-trunc` 에 원문, `inspect .Config.Env` 에 원문 | **DB_PASSWORD · TAGO_SERVICE_KEY 는 ARG · ENV에 넣지 않는다.** 실행할 때 `-e`(2-6), Kubernetes Secret(3 · 4단계) |
| 같은 tar 파일을 `COPY` · `ADD` | COPY는 `html.tar` 그대로, ADD는 풀어서 `html/index.html` | 로컬 파일은 COPY만 쓴다 (ADD 없음) |
| `ARG PYTHON_TAG` 를 FROM 앞에 | FROM 줄에서만 쓰인다 | 베이스 이미지 태그를 한 곳에서 바꿀 수 있게 (2-5 베이스 비교에서 사용). 이름을 `PYTHON_VERSION` 이 아니라 `_TAG` 로 한 것은 베이스 이미지에 같은 이름의 ENV가 있어서 |

## 3. 2.2 Dockerfile — 추가한 명령

| 명령 | APP | Web | 이유 |
|---|---|---|---|
| `ARG ..._TAG` (FROM 앞) | `PYTHON_TAG=3.14-slim` | `NGINX_TAG=1.30-alpine` | 베이스 태그를 빌드 인자로 |
| `LABEL` | `org.opencontainers.image.title/description/source` | 같음 | 이미지만 보고 무엇인지 · 소스가 어디인지 알 수 있게 (OCI 표준 키) |
| `ENV` | `DB_HOST=db DB_PORT=3306 DB_NAME=busdb CITY_CODE=25 PYTHONUNBUFFERED=1` | — | 비밀이 아닌 기본값. 실행할 때 `-e` 로 바꿀 수 있다 |
| `EXPOSE` | `8000` | `80` | 실행할 사람에게 게시할 포트를 알린다 (게시는 `-p`) |
| `HEALTHCHECK` | 10초마다 `python -c urllib ... /api/healthz` | 10초마다 `wget -q -O /dev/null http://127.0.0.1/` | 프로세스는 살아 있어도 응답하지 않는 상태를 구분한다. slim에는 curl이 없어 python, Alpine은 busybox wget |

배치: 파일을 바꾸는 명령(WORKDIR · COPY · RUN) 뒤에 실행 설정(LABEL · ENV · EXPOSE · HEALTHCHECK) → CMD (교재 5장 01 "명령의 배치 순서").

## 4. 확인한 것 (작업 환경 검증)

| 확인 | 결과 |
|---|---|
| 2.2 빌드 | 끝에 설정만 추가했는데 `[3/4] COPY . .` · `[4/4] RUN pip install` 이 **다시 실행** — `.dockerignore` 가 없어 수정한 Dockerfile 자체가 `COPY . .` 로 복사되므로 체크섬이 바뀌었다 (2-4에서 해결) |
| `docker history bus-app:2.2` | HEALTHCHECK · EXPOSE · ENV · LABEL · CMD 모두 0B. 크기는 2.1과 같다 |
| `inspect` | Labels 3개, Env에 DB_HOST 등 (비밀 없음), ExposedPorts `8000/tcp`, Healthcheck(나노초 단위) |
| 게시 없이 실행 | PORTS `8000/tcp`, `docker port` 출력 없음 |
| `-p 127.0.0.1:8000:8000` | `127.0.0.1:8000->8000/tcp`, 호스트 curl 성공, 다른 주소(eth0)로는 실패 |
| `-P` | `0.0.0.0:32768->8000/tcp` (임의 포트), eth0 주소로도 접속됨 → 같은 네트워크의 다른 장비에서도 접속 가능. 그래서 쓰지 않는다 |
| APP 헬스체크 | `health: starting` → 약 8초 후 `healthy`, `State.Health.Log` ExitCode 0 |
| uvicorn 정지(SIGSTOP) | 약 35초 뒤 `unhealthy` (FailingStreak 3), STATUS는 `Up`, `RestartCount 0`, `--filter health=unhealthy` 로 조회됨. SIGCONT 후 다시 `healthy` |
| Web 헬스체크 | `healthy` — 하지만 `/api` 는 여전히 502. 헬스체크는 지정한 것(/)만 검사한다 |
| Web index.html 삭제 | `/` 403 → `unhealthy`, 컨테이너는 running |
| APP `docker stop` | 여전히 약 10초 (2-3에서 고칠 문제) |

## 5. 남은 문제 (2-1에서 이어짐)

| 문제 | 상태 | 고치는 소단계 |
|---|---|---|
| 이미지에 포트 · 상태 확인 정보 없음 | **해결** (EXPOSE, HEALTHCHECK) | 2-2 |
| 설정 기본값이 이미지에 없음 | **해결** (ENV) — 설정 계약 정리는 2-3 | 2-2, 2-3 |
| `docker stop` 10초 · 137 | 남음 | 2-3 |
| Web `/api` 502 | 남음 (헬스체크는 healthy) | 2-3, 2-6 |
| Dockerfile만 고쳐도 pip install 다시 실행 | **새로 발견** | 2-4 |
| 빌드 컨텍스트 · 이미지에 `.venv` | 남음 | 2-4 |
| 이미지 크기, root 실행 | 남음 | 2-5 |
