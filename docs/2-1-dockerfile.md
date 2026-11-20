# 2-1 Dockerfile 작성 · 이미지 빌드

1단계에서 사람이 직접 하던 설치 · 설정(1-2, 1-3)을 Dockerfile 두 개로 옮긴다.
이 소단계는 **기초 Dockerfile**이다. 빌드 최적화(멀티스테이지, 캐시 마운트, root가 아닌 사용자)는 2-3에서 이 이미지와 비교하며 한다.

| 이미지 | Dockerfile | 빌드 컨텍스트 | 베이스 |
|---|---|---|---|
| APP | `app/was/Dockerfile` | `app/was/` | `python:3.14-slim` |
| Web | `app/web/Dockerfile` | `app/web/` | `nginx:1.30-alpine` |
| DB | 만들지 않음 | — | 공식 이미지 `mysql:8.4` 그대로 사용 (2-2) |

## 1. 1단계 작업 → Dockerfile 명령

| 1단계에서 직접 한 일 | Dockerfile |
|---|---|
| Python 설치 (`apt install python3-venv`) | `FROM python:3.14-slim` |
| 작업 폴더로 이동 (`cd ~/k8s-capstone/app/was`) | `WORKDIR /app` |
| 가상환경 + `pip install -r requirements.txt` | `COPY requirements.txt` + `RUN pip install` |
| 소스 받기 (`git clone`) | `COPY app.py ./` |
| 환경 변수 (`export DB_HOST=...`) | `ENV` (비밀 아닌 값만) / `docker run -e` (비밀) |
| `uvicorn app:app --host 127.0.0.1 --port 8000` | `CMD ["uvicorn", ..., "--host", "0.0.0.0", ...]` |
| Nginx 설치, 설정 복사, `/var/www` 에 화면 복사 | `FROM nginx:1.30-alpine`, `COPY` 2개 |
| Nginx 설정의 `proxy_pass 127.0.0.1:8000` | 템플릿 `proxy_pass http://${APP_ADDR}` + `ENV APP_ADDR=app:8000` |

## 2. APP Dockerfile 명령별 역할

| 명령 | 역할 | 이렇게 한 이유 |
|---|---|---|
| `# syntax=docker/dockerfile:1` | BuildKit Dockerfile 문법 버전 지정 | 수업 예제와 같다. 2-3의 `RUN --mount` 를 쓰려면 필요 |
| `FROM python:3.14-slim` | 베이스 이미지 | 공식 파이썬 이미지 중 작은 slim. 수업(Docker Core 5장 03)과 같은 태그. 사용자 WSL의 Python도 3.14 |
| `WORKDIR /app` | 이후 명령의 작업 디렉터리 (없으면 만든다) | `cd` 대신. 경로를 한 곳에서 정한다 |
| `COPY requirements.txt ./` → `RUN pip install` | 라이브러리 설치 | **소스보다 먼저** 복사한다. 소스(`app.py`)만 바뀌면 이 층은 캐시를 다시 쓴다 (Docker Core 4장 06) |
| `COPY app.py ./` | 소스 복사 | 필요한 파일만 이름으로 복사한다 (`COPY . .` 를 쓰지 않음) |
| `ENV DB_HOST=db ...` | 설정 기본값 | 비밀이 아닌 값만. `db` 는 2-2에서 만들 DB 컨테이너 이름 |
| (ENV 에 없음) `DB_USER` · `DB_PASSWORD` · `TAGO_SERVICE_KEY` | 실행할 때 `-e` 로 주입 | 이미지에 넣으면 `docker image inspect` · `docker history` 로 누구나 볼 수 있다 (평가 감점 대상) |
| `ENV PYTHONUNBUFFERED=1` | 파이썬 출력 버퍼링 끄기 | `docker logs` 에 로그가 바로 보인다 |
| `EXPOSE 8000` | 컨테이너가 받는 포트를 기록 | 문서 역할. 실제로 포트를 여는 것은 `docker run -p` |
| `CMD ["uvicorn", ..., "--host", "0.0.0.0", ...]` | 컨테이너 시작 명령 | **exec 형식**: uvicorn 이 PID 1 이 되어 `docker stop` 의 SIGTERM 을 직접 받고 정상 종료(종료 코드 0). **0.0.0.0**: 1단계의 127.0.0.1 은 컨테이너 자기 자신만 뜻하므로 Web 컨테이너가 접속할 수 없다 |

`CMD` 를 쓴 이유: 실행 명령을 바꿀 일이 있으면(예: `docker run bus-app:basic python -c ...`) 덮어쓸 수 있게 기본값으로 둔다. 수업의 기준(CMD = 바꿀 수 있는 기본값, ENTRYPOINT = 고정 실행 파일)에 따랐다.

## 3. Web Dockerfile 명령별 역할

| 명령 | 역할 | 이렇게 한 이유 |
|---|---|---|
| `FROM nginx:1.30-alpine` | 베이스 이미지 | Nginx 안정 버전 1.30, Alpine 기반으로 작다 |
| `COPY default.conf.template /etc/nginx/templates/` | 설정 템플릿 | 공식 이미지가 시작할 때 템플릿의 `${APP_ADDR}` 를 환경 변수 값으로 바꿔 `conf.d/default.conf` 를 만든다. `$host` 처럼 환경 변수가 아닌 Nginx 변수는 그대로 둔다 |
| `COPY html/ /usr/share/nginx/html/` | 화면 파일 | 공식 이미지의 기본 문서 경로 |
| `ENV APP_ADDR=app:8000` | APP 주소 기본값 | 2단계는 컨테이너 이름 `app`, 3 · 4단계는 Service 이름으로 바뀐다. **이미지를 다시 만들지 않고** `-e APP_ADDR=...` 로 바꿀 수 있다 |
| `EXPOSE 80` | 받는 포트 기록 | — |
| (CMD 없음) | 베이스 이미지의 실행 명령 사용 | 공식 이미지의 `/docker-entrypoint.sh` 가 템플릿 처리 후 `nginx -g "daemon off;"` 를 실행한다 |

1단계용 `app/web/nginx.conf` 는 그대로 두고(태그 `stage1-local` 의 재현성), 컨테이너용은 `default.conf.template` 으로 분리했다.

## 4. .dockerignore

| 파일 | 제외하는 것 | 이유 |
|---|---|---|
| `app/was/.dockerignore` | `.venv/`, `__pycache__/`, `*.pyc`, `.env*`, `Dockerfile`, `.dockerignore` | 1단계 가상환경은 수십 MB이고 이미지 안에서 다시 설치한다. `.env` 에는 비밀이 들어갈 수 있다 |
| `app/web/.dockerignore` | `nginx.conf`(1단계용), `Dockerfile`, `.dockerignore` | 이미지에서 쓰지 않는 파일 |

빌드 컨텍스트(도커에 보내는 파일 묶음)에서 빠지므로 빌드가 빠르고, 나중에 누군가 `COPY . .` 로 바꿔도 비밀 · 불필요 파일이 이미지에 들어가지 않는다.

## 5. 빌드와 확인

```bash
cd ~/k8s-capstone
docker build -t bus-app:basic app/was
docker build -t bus-web:basic app/web
docker image ls bus-*
docker history bus-app:basic
docker image inspect bus-app:basic --format '{{json .Config.Env}}'
```

| 확인 | 기대 결과 |
|---|---|
| 이미지 목록 | `bus-app:basic`, `bus-web:basic` |
| `docker history` | 층마다 Dockerfile 명령 하나. 가장 큰 층은 `pip install` |
| `inspect` 의 Env | `DB_HOST=db`, `DB_PORT=3306`, `DB_NAME=busdb`, `CITY_CODE=25` — **비밀번호 없음** |
| `docker run --rm bus-app:basic` | `KeyError: 'DB_PASSWORD'` 로 종료 — 비밀번호가 이미지에 없다는 증거 |
| `docker run --rm -e APP_ADDR=127.0.0.1:8000 bus-web:basic nginx -T` | 생성된 설정에 `proxy_pass http://127.0.0.1:8000;` |
| `docker run --rm bus-web:basic nginx -t` | `host not found in upstream "app"` — APP 컨테이너가 없어서. 2-2에서 같은 네트워크에 APP을 먼저 띄운다 |

## 6. 다음 소단계

2-2에서 사용자 정의 네트워크에 DB(`mysql:8.4` + 볼륨) → APP → Web 순서로 컨테이너를 실행하고 `bash tests/scenario.sh http://localhost:8080` 으로 T1~T9를 확인한다.
