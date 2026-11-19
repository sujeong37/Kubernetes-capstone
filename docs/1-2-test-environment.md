# 1-2 테스트 환경 구성 (WSL 2 Ubuntu)

1-1에서 정리한 실행 조건(Nginx · Python 3.9 이상 + 라이브러리 3개 · MySQL)을 **Docker 없이** WSL 2 Ubuntu에 직접 설치한다.
이 문서만 보고 같은 환경을 다시 만들 수 있게 설치 명령과 확인 방법을 남긴다. 실행(DB 초기화 · APP 기동 · Web 연결)은 1-3에서 한다.

## 1. 환경

| 항목 | 값 | 확인 명령 |
|---|---|---|
| 호스트 | Windows + WSL 2 | `wsl -l -v` (PowerShell) |
| OS | Ubuntu 24.04 LTS (22.04도 가능) | `cat /etc/os-release` |
| Web | Nginx 1.24 (Ubuntu 기본 저장소) | `nginx -v` |
| DB | MySQL 8.0 (Ubuntu 기본 저장소) | `mysql --version` |
| APP 런타임 | Python 3.12 (Ubuntu 24.04 기본) + venv | `python3 --version` |
| APP 라이브러리 | fastapi 0.115.6, uvicorn 0.32.1, PyMySQL 1.1.1 (+ cryptography 46.0.3 — 1-4에서 추가) | `pip list` |

## 2. 설치

```bash
# 2-1. 패키지 목록 갱신 후 설치
sudo apt-get update
sudo apt-get install -y nginx mysql-server python3-venv

# 2-2. 서비스 시작 (WSL은 재부팅 때마다 다시 시작해야 할 수 있다)
sudo service mysql start
sudo service nginx start

# 2-3. APP 라이브러리를 프로젝트 전용 가상환경(venv)에 설치
cd ~/k8s-capstone/app/was
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
deactivate
```

## 3. 확인

```bash
nginx -v                              # nginx version: nginx/1.24.x
mysql --version                       # mysql  Ver 8.0.xx
python3 --version                     # Python 3.12.x
sudo service nginx status             # * nginx is running
sudo service mysql status             # ... Server version ... / Uptime
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/    # 200 (Nginx 기본 페이지)
sudo mysql -e "SELECT VERSION();"     # 8.0.xx
~/k8s-capstone/app/was/.venv/bin/pip list | grep -Ei "fastapi|uvicorn|pymysql"
```

| 확인 항목 | 기대 결과 |
|---|---|
| Nginx 설치 · 실행 | 버전 출력, `nginx is running`, `localhost` 응답 200 |
| MySQL 설치 · 실행 | 버전 출력, `SELECT VERSION()` 결과 |
| Python · venv | 3.9 이상, `.venv` 안에 라이브러리 3개 |

## 4. 선택 이유

| 선택 | 이유 | 다른 방법과 비교 |
|---|---|---|
| WSL 2 Ubuntu에 **직접 설치** | 평가 기준 ①이 "WSL 2 Ubuntu에서 소스를 빌드하고 실행"을 요구한다. 직접 설치해 보면 2단계에서 Docker가 무엇을 대신해 주는지 비교할 수 있다 | Docker로 바로 시작하면 ①과 ②의 차이를 보여 줄 수 없다 |
| Ubuntu 기본 저장소의 **MySQL 8.0** | `apt` 한 줄로 설치되고 별도 저장소 등록이 필요 없다. 앱이 쓰는 SQL(테이블 1개, INSERT · SELECT · UPDATE · DELETE)은 8.0과 8.4에서 같다 | 2단계부터는 공식 이미지 `mysql:8.4`를 쓴다. 버전을 이미지 태그로 고정하는 것이 Docker의 장점 중 하나 |
| Python **venv** (가상환경) | 시스템 파이썬을 건드리지 않고 프로젝트 폴더 안(`.venv`)에만 라이브러리를 설치한다. Ubuntu 24.04는 시스템 전체에 `pip install`을 막는다(PEP 668) | 컨테이너에서는 이미지가 곧 격리된 환경이라 venv가 필요 없어진다 |
| 라이브러리 **버전 고정** (`==`) | 언제 설치해도 같은 버전이 깔려 1~4단계 결과가 같다 | 버전을 안 적으면 설치 시점마다 다른 버전이 깔릴 수 있다 |

## 5. 이 단계에서 겪는 불편 (2단계와 비교할 기준)

- 프로그램 3개를 각각 설치하고, 서비스를 하나씩 시작해야 한다.
- 설치된 버전이 Ubuntu 버전에 따라 달라진다 (22.04 → Python 3.10, 24.04 → 3.12).
- 같은 포트(80, 3306)를 이미 쓰는 프로그램이 있으면 충돌한다.
- 다른 컴퓨터에 옮기려면 이 문서를 처음부터 다시 따라 해야 한다.

2단계(Docker)에서는 이 과정이 Dockerfile과 `docker run` 몇 줄로 바뀐다.
