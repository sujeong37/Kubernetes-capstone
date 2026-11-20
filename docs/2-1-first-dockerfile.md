# 2-1 첫 Dockerfile

Docker Core 4장 01(첫 Dockerfile) · 03([실습] Gallery: 첫 이미지 빌드)을 우리 앱에 적용한다.

이 소단계는 **1단계(WSL)에서 손으로 한 절차를 그대로 Dockerfile로 옮긴다.** 일부러 고치지 않은 가장 단순한 형태로 시작해 빌드 · 실행하고, 무엇이 되고 무엇이 안 되는지와 측정값(빌드 컨텍스트 크기, 첫 빌드 시간, 이미지 크기, 정지 시간, 실행 사용자)을 기록한다.
2-2 ~ 2-5에서 교재의 섹션을 하나씩 적용해 고치고, 같은 항목을 다시 측정해 이 기록과 비교한다.

| 이미지 | Dockerfile | 태그 |
|---|---|---|
| APP | `app/was/Dockerfile` | `bus-app:2.1` |
| Web | `app/web/Dockerfile` | `bus-web:2.1` |
| DB | 만들지 않는다. 공식 이미지 `mysql:8.4` (2-6) | — |

## 1. 1단계 절차 → Dockerfile (그대로 옮기기)

| 1단계에서 한 일 (1-2, 1-3) | APP Dockerfile v1 |
|---|---|
| Python 설치 | `FROM python:3.14-slim` |
| `cd ~/k8s-capstone/app/was` | `WORKDIR /app` |
| `git clone` (폴더 전체) | `COPY . .` |
| `pip install -r requirements.txt` | `RUN pip install -r requirements.txt` |
| `uvicorn app:app --host 127.0.0.1 --port 8000` | `CMD uvicorn app:app --host 0.0.0.0 --port 8000` (주소만 변경, 아래 4) |

| 1단계에서 한 일 (1-3) | Web Dockerfile v1 |
|---|---|
| `sudo apt install nginx` | `FROM nginx:1.30-alpine` |
| `sudo cp app/web/nginx.conf /etc/nginx/sites-available/bus-app` | `COPY nginx.conf /etc/nginx/conf.d/default.conf` |
| `sudo cp app/web/html/index.html /var/www/bus-app/` | `COPY html/ /var/www/bus-app/` |
| `sudo service nginx reload` | (없음) 베이스 이미지의 실행 명령 `nginx -g "daemon off;"` |

`# syntax=docker/dockerfile:1` 은 빌드 전에 Dockerfile 문법의 최신 1.x 안정 버전을 받아 쓰게 하는 지시문이다(교재 4장 01). 2-5의 `RUN --mount` 도 이 문법이 필요하다.

## 2. 빌드 출력 읽기

```bash
docker build -t bus-app:2.1 app/was        # PATH(app/was) = 빌드 컨텍스트
```

| 출력 | 뜻 |
|---|---|
| `[internal] load build definition from Dockerfile` | Dockerfile 읽기 |
| `resolve image config for docker-image://docker.io/docker/dockerfile:1` | syntax 지시문의 문법 버전 확인 |
| `[internal] load metadata for docker.io/library/python:3.14-slim` | 베이스 이미지 정보를 Docker Hub에 조회 (모든 층이 캐시여도 매번 2~3초) |
| `[internal] load .dockerignore` → `transferring context: 2B` | 제외 목록 — **없음** |
| `[internal] load build context` → `transferring context: 35.8MB` | 빌드 컨텍스트 전송. `.venv`(1단계 가상환경)까지 보낸다 |
| `[1/4]` ~ `[4/4]` | 실행하는 명령 4개 (FROM, WORKDIR, COPY, RUN). CMD는 설정으로 기록되므로 번호가 없다 |
| `JSONArgsRecommended` 경고 | 셸 형식 CMD — 2-3에서 다룬다 |

## 3. 확인한 것 (작업 환경 검증)

| 확인 | 결과 |
|---|---|
| 빌드 컨텍스트 (첫 빌드) | 약 36MB (`.venv` 39MB 포함). 다시 빌드할 때는 바뀐 것만 보내 약 157kB |
| `docker history bus-app:2.1` | `COPY . .` 층 40.1MB, `RUN pip install` 층 46.7MB, `CMD ["/bin/sh" "-c" "uvicorn ..."]` 0B |
| 이미지 안 `/app` | `.venv`, `__pycache__`, `Dockerfile` 까지 들어 있다 (실행에 필요 없음) |
| `docker run --rm bus-app:2.1` | `KeyError: 'DB_PASSWORD'` 로 종료 — 비밀번호를 이미지에 넣지 않았고, 없으면 시작하지 않는다 |
| `-e DB_PASSWORD=unused -p 127.0.0.1:8000:8000` | `/api/healthz` `{"status":"ok","mode":"fake"}`, 정류장 검색 정상 (이 소단계는 DB 없이 가짜 데이터 기능만 확인) |
| `docker top` | PID 1이 `/bin/sh -c uvicorn ...`, uvicorn은 그 자식 |
| `docker stop` | **약 10초**, 종료 코드 **137** (SIGKILL) |
| 실행 사용자 | `root` |
| Web `/` | 200 (화면) |
| Web `/api/healthz` | **502** — 로그 `connect() failed (111: Connection refused) ... upstream: "http://127.0.0.1:8000/..."` |
| Web `docker stop` | 약 0.2초, 종료 코드 0 |
| `docker build app/was` (`-t` 없음) | `<untagged>` 이미지 생성 (`docker image ls --filter dangling=true`) |
| `COPY ../web/nginx.conf .` | `"/web/nginx.conf": not found`, `Dockerfile:3` 과 `>>>` 로 실패 위치 표시, 이미지 생성 안 됨 |

작업 환경은 Docker Hub에 접속할 수 없어 같은 이름의 대체 베이스 이미지로 검증했다. 크기 · 시간의 실제 값은 Runbook 수행 결과로 기록한다.

## 4. 127.0.0.1 → 0.0.0.0 만 바꾼 이유

1단계 그대로 `--host 127.0.0.1` 로 실행하면(`docker run ... bus-app:2.1 uvicorn app:app --host 127.0.0.1 --port 8000`) 컨테이너 안에서는 응답하지만 호스트의 `curl` 은 `Connection reset by peer` 로 실패한다.
컨테이너는 자기만의 네트워크(네임스페이스)를 가지므로 컨테이너의 127.0.0.1은 **컨테이너 자기 자신**이다. `-p` 로 들어온 요청은 컨테이너의 네트워크 인터페이스(eth0)로 오기 때문에 127.0.0.1에만 열린 프로그램에는 닿지 않는다.
그래서 모든 인터페이스에서 받도록 `0.0.0.0` 으로 바꿨다. 이것이 1단계 절차에서 바꾼 유일한 값이다.

호스트에 게시할 때는 `-p 127.0.0.1:8000:8000` 처럼 호스트 쪽을 루프백으로 지정해 같은 네트워크의 다른 장비에서 접속하지 못하게 한다(교재 4장 03과 같다).

## 5. 남은 문제 (2-2 ~ 2-5에서 고칠 것)

| 문제 | 근거 (측정) | 고치는 소단계 |
|---|---|---|
| 이미지에 포트 · 상태 확인 정보가 없다 | `docker image inspect` 에 ExposedPorts 없음, `docker ps` 에 health 없음 | 2-2 EXPOSE · HEALTHCHECK |
| 설정 기본값(DB_HOST 등)이 이미지에 없다 | 실행할 때마다 모든 값을 `-e` 로 넣어야 한다 | 2-2 ENV, 2-3 설정 계약 |
| `docker stop` 이 10초 걸리고 강제 종료(137) | 셸 형식 CMD → PID 1이 `/bin/sh` | 2-3 CMD와 ENTRYPOINT |
| Web의 `/api` 가 502 | `nginx.conf` 의 `127.0.0.1:8000` 은 Web 컨테이너 자신 | 2-3 엔트리포인트 스크립트 · 템플릿(설정을 환경 변수로), 2-6 네트워크 |
| 빌드 컨텍스트 36MB, 이미지에 `.venv` · `Dockerfile` | `COPY . .`, `.dockerignore` 없음 | 2-4 .dockerignore |
| 소스(app.py)만 고쳐도 pip install 다시 실행 | `COPY . .` 뒤에 `RUN pip install` | 2-4 명령 순서 |
| 이미지 크기, root 실행 | `docker image ls`, `whoami` → root | 2-5 멀티스테이지 · 비root |

## 6. 다음 소단계

2-2에서 교재 4장 02(명령어 체계)를 적용한다: ENV와 ARG(비밀 값이 남는 위치), WORKDIR, LABEL, EXPOSE와 포트 게시(`-p`, `-P`), HEALTHCHECK.
