# ① 앱 — 버스 도착 정보

아래 명령은 모두 저장소의 `app/` 폴더에서 실행한다.

```bash
git clone https://github.com/sujeong37/Kubernetes-capstone.git
cd Kubernetes-capstone/app
```

```
브라우저 → [Web: Nginx :80] ─ /       → 화면 파일 (web/html/index.html)
                            └ /api/*  → [WAS: FastAPI :8000] → [DB: MySQL :3306]
                                                             → 공공데이터 TAGO API (키 없으면 가짜 데이터)
```

```
app/
├── web/
│   ├── nginx.conf        # 화면 파일 응답 + /api는 WAS로 전달
│   └── html/index.html   # 폰 모양 화면
├── was/
│   ├── app.py            # API 전부 (등록·조회·수정·삭제 포함)
│   └── requirements.txt
└── db/
    └── init.sql          # 즐겨찾기 테이블
```

## 로컬 실행 (WSL Ubuntu, Docker 없이)

### 1. 프로그램 설치

```bash
sudo apt-get update
sudo apt-get install -y mysql-server nginx python3-venv
```

### 2. DB 준비 (MySQL)

DB 비밀번호는 파일에 적지 않고 터미널 변수로만 정한다.

```bash
read -s -p "DB 비밀번호: " DB_PASSWORD; echo; export DB_PASSWORD

sudo service mysql start
sudo mysql <<SQL
CREATE DATABASE IF NOT EXISTS busdb DEFAULT CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 'bus'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS 'bus'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE ON busdb.* TO 'bus'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON busdb.* TO 'bus'@'127.0.0.1';
SQL
sudo mysql busdb < db/init.sql
```

앱 계정(bus)에는 데이터 읽기·쓰기 권한만 준다(테이블 생성·삭제 불가).

### 3. Web 준비 (Nginx)

```bash
sudo mkdir -p /var/www/bus-app
sudo cp web/html/index.html /var/www/bus-app/
sudo cp web/nginx.conf /etc/nginx/sites-available/bus-app
sudo ln -sf /etc/nginx/sites-available/bus-app /etc/nginx/sites-enabled/bus-app
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo service nginx start      # 이미 켜져 있으면: sudo service nginx reload
```

### 4. APP 실행 (새 터미널)

```bash
cd was
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

read -s -p "DB 비밀번호: " DB_PASSWORD; echo; export DB_PASSWORD   # 2번에서 정한 값
# 실제 데이터를 쓰려면 (안 하면 가짜 데이터): 공공데이터포털 인증키(디코딩 키)
# read -s -p "TAGO 인증키: " TAGO_SERVICE_KEY; echo; export TAGO_SERVICE_KEY

uvicorn app:app --host 127.0.0.1 --port 8000
```

DB_PASSWORD가 없으면 APP은 시작하지 않는다(`KeyError: 'DB_PASSWORD'`).

### 5. 확인

- 브라우저: http://localhost/
- `curl localhost/api/healthz` → `{"status":"ok","mode":"fake"}` (키를 넣었으면 `"real"`)
- API 문서 (WAS 직접): http://localhost:8000/docs

## 환경변수 (WAS)

| 이름 | 기본값 | 설명 | 나중에 Kubernetes에서 |
|---|---|---|---|
| TAGO_SERVICE_KEY | (없음) | 비워 두면 가짜 데이터 | Secret |
| CITY_CODE | 25 | 대전 | ConfigMap |
| DB_HOST | 127.0.0.1 | DB 주소 | ConfigMap |
| DB_PORT | 3306 | DB 포트 | ConfigMap |
| DB_NAME | busdb | DB 이름 | ConfigMap |
| DB_USER | bus | DB 계정 | Secret |
| DB_PASSWORD | 없음 (필수) | DB 비밀번호 | Secret |

인증키와 비밀번호는 코드와 GitHub에 넣지 않는다. 부하 테스트는 반드시 가짜 데이터 모드로 한다.

## 테스트 시나리오 (모든 단계에서 같은 시나리오로 확인)

`{주소}`: 로컬 `localhost` → 컨테이너 `localhost:8080` → kubeadm `{노드 공인 IP}:{NodePort}` → EKS `{ALB 주소}`

| # | 확인 항목 | 명령 | 기대 결과 |
|---|---|---|---|
| T1 | 상태 확인 | `curl {주소}/api/healthz` | `{"status":"ok", ...}` |
| T2 | 화면 | 브라우저로 `http://{주소}/` | 폰 모양 화면 |
| T3 | 정류장 검색 | `curl "{주소}/api/stops?name=북대전"` | 북대전농협 포함 |
| T4 | 도착 정보 | `curl {주소}/api/arrivals/DJB8001793` | 버스 목록 (남은 시간 오름차순) |
| T5 | 등록 (같은 정류장 다시 등록하면 409) | `curl -X POST {주소}/api/favorites -H 'Content-Type: application/json' -d '{"nodeId":"DJB8001793","nodeName":"북대전농협"}'` | 201, alias=북대전농협 |
| T6 | 조회 | `curl {주소}/api/favorites` | 등록한 정류장 1건 |
| T7 | 수정 | `curl -X PUT {주소}/api/favorites/DJB8001793 -H 'Content-Type: application/json' -d '{"alias":"집 앞"}'` | alias=집 앞 |
| T8 | 데이터 유지 | WAS(·DB) 재시작 후 `curl {주소}/api/favorites` | alias=집 앞 그대로 |
| T9 | 삭제 | `curl -X DELETE {주소}/api/favorites/DJB8001793` | 204, 목록 비어 있음 |
