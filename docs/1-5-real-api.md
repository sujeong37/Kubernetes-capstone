# 1-5 실제 공공 API 연동 확인

1-3 · 1-4는 인증키 없이 **가짜 데이터 모드**로 실행했다. 이 소단계는 공공데이터포털 인증키를 넣어 **실제 버스 정보**로 같은 앱과 같은 시나리오가 동작하는지 확인한다.
이후 단계(2~4)는 기본적으로 가짜 데이터 모드로 검증하고(호출 한도 · 외부 상황과 무관하게 같은 결과), 실제 데이터는 이 소단계의 방법으로 필요할 때 확인한다.

## 1. 사용하는 API

| 기능 | API (공공데이터포털, 국토교통부 TAGO) | 앱의 요청 | 쓰는 응답 필드 → 앱의 필드 |
|---|---|---|---|
| 정류장 검색 | 버스정류소정보 `BusSttnInfoInqireService/getSttnNoList` | `GET /api/stops?name=` | `nodeid` → `nodeId`, `nodenm` → `nodeName` |
| 도착 정보 | 버스도착정보 `ArvlInfoInqireService/getSttnAcctoArvlPrearngeInfoList` | `GET /api/arrivals/{nodeId}` | `routeno` → `route`, `arrtime`(초) → `arrSec`, `arrprevstationcnt` → `leftStops` |

- 공통 요청값: `serviceKey`(인증키), `cityCode=25`(대전), `_type=json`, `numOfRows=50`
- 인증키는 **일반 인증키(Decoding)** 를 쓴다. 앱이 주소에 넣을 때 인코딩한다(Encoding 키를 넣으면 두 번 인코딩되어 인증 오류).
- 호출 한도: 개발 계정 하루 10,000회. 화면을 열어 두면 15초마다 도착 정보를 다시 부르므로 확인이 끝나면 닫는다.

## 2. 인증키 관리

| 원칙 | 방법 |
|---|---|
| 코드 · 저장소 · 문서 · 이미지에 남기지 않는다 | `read -s -p "TAGO 인증키: " TAGO_SERVICE_KEY; echo; export TAGO_SERVICE_KEY` 로 터미널 변수로만 입력 |
| 화면 · 기록에 남기지 않는다 | `read -s` 는 입력이 보이지 않고 명령 기록에도 남지 않는다. `curl` 은 `--data-urlencode "serviceKey=$TAGO_SERVICE_KEY"` 로 변수를 넘겨 키가 화면에 찍히지 않는다 |
| 로그에 남기지 않는다 | 호출 실패 시 APP 로그에 **원인만** 남기고, 인증키가 들어 있는 URL은 남기지 않는다 |
| 이후 단계 | 2단계 `docker run -e TAGO_SERVICE_KEY`, 3 · 4단계 Kubernetes Secret |

## 3. 이 소단계에서 바꾼 것

| 파일 | 변경 | 이유 |
|---|---|---|
| `app/was/app.py` `call_tago()` | 호출 실패 원인을 APP 로그(stderr)에 한 줄 남긴다. 인증키 오류처럼 JSON 대신 XML로 오는 응답에서 `returnAuthMsg` 등을 꺼낸다 | 기존에는 사용자에게 502만 보이고 원인을 알 수 없었다. 키 미등록 · 호출 한도 초과 · 네트워크 오류를 로그로 구분한다 |
| `app/was/app.py` `fetch()` | 응답이 5초 안에 안 오거나 연결이 끊기면 **한 번만** 다시 시도한다 (최대 10초). 401 같은 거절 응답은 다시 시도하지 않는다 | 실제 연동에서 첫 요청이 `TimeoutError` 로 두 번 실패하고 세 번째에 성공했다(아래 6. 겪은 문제). 사용자가 다시 누르지 않아도 되게 한다 |
| `tests/scenario.sh` | 검색어 · 정류장을 `SEARCH` · `STOP_ID` · `STOP_NAME` 환경 변수로 바꿀 수 있다 (기본값은 그대로) | 실제 데이터에서 다른 정류장으로 확인할 수 있게. 기본 실행은 이전과 완전히 같다 |

로그 예 (인증키가 등록되지 않았을 때):

```
TAGO 호출 실패 (getSttnNoList): ValueError: SERVICE_KEY_IS_NOT_REGISTERED_ERROR
```

## 4. 확인 방법

```bash
# 터미널 1 — 인증키를 넣고 APP 재시작
cd ~/k8s-capstone/app/was && source .venv/bin/activate
read -s -p "TAGO 인증키: " TAGO_SERVICE_KEY; echo; export TAGO_SERVICE_KEY
uvicorn app:app --host 127.0.0.1 --port 8000

# 터미널 2
curl -s localhost/api/healthz                                  # {"status":"ok","mode":"real"}
curl -s "localhost/api/stops?name=%EB%B6%81%EB%8C%80%EC%A0%84"  # 실제 정류장 목록
bash tests/scenario.sh http://localhost                        # 같은 시나리오 T1~T9
```

| 확인 | 기대 결과 |
|---|---|
| 공공 API 원본 응답 (curl 직접 호출) | `resultCode` `00`, `nodeid` · `nodenm` 목록 |
| `healthz` | `"mode":"real"` |
| 정류장 검색 · 도착 정보 | 실제 정류장 · 실제 노선 번호와 남은 시간 |
| 실제 서비스와 비교 | 같은 정류장을 지도 앱(카카오맵 등)에서 조회하면 노선 · 남은 시간이 비슷하다 |
| 시나리오 | 통과 9 / 9 (T3 · T4가 실제 데이터) |
| 잘못된 인증키 | 화면 "검색에 실패했습니다", API 502, APP 로그에 원인 |

- 심야(버스 운행 종료 후)에는 도착 정보가 빈 목록이라 T4가 실패할 수 있다. 버스 운행 시간에 확인한다.
- 기본 정류장(DJB8001793 북대전농협)이 실제 검색 결과에 없으면, 실제 검색 결과의 정류장으로 `SEARCH=... STOP_ID=... STOP_NAME=... bash tests/scenario.sh http://localhost` 를 실행한다.

## 5. 검증 (제작 중)

작업 환경에서는 공공 API에 접속할 수 없어, API 명세의 응답 형식을 그대로 흉내 낸 가짜 서버로 앱의 실제 데이터 모드 코드를 확인했다.

| 경우 | 결과 |
|---|---|
| 정상 (여러 건) | 필드 변환 · 남은 시간순 정렬, 시나리오 9 / 9 |
| 결과 1건 (`item` 이 목록이 아닌 객체) | 목록으로 처리 |
| 결과 없음 (`items` 가 `""`) | 빈 목록 `[]`, 화면 "도착 예정인 버스가 없습니다" |
| 인증키 미등록 (XML 응답) | 502, 로그 `SERVICE_KEY_IS_NOT_REGISTERED_ERROR` |
| 호출 한도 초과 (`resultCode` 22) | 502, 로그 `LIMITED NUMBER OF SERVICE REQUESTS EXCEEDS ERROR.` |
| HTTP 401 | 502, 로그 `HTTP Error 401: Unauthorized` |
| 인증키에 `+ / =` 포함 | 인코딩되어 정상 전달 |
| 첫 응답만 6초 지연 | 재시도로 성공 (약 5초 후 200), 로그 `TAGO 응답 지연 ... 한 번 더 시도` |
| 계속 6초 지연 | 두 번 시도 후 502 (약 10초), 로그 `TimeoutError` |
| HTTP 401 | 재시도 없이 바로 502 |
| 로그에 인증키 | 남지 않음 (0건) |

실제 API와의 연동 결과는 Runbook 수행 기록(스크린샷)으로 남긴다.

## 6. 겪은 문제

| 문제 | 원인 | 해결 |
|---|---|---|
| `git pull` 에서 `Could not resolve host: github.com` | WSL의 DNS가 Windows 중계 주소(`nameserver 10.255.255.254`)를 쓰는데 중계가 응답하지 않았다. `ping 8.8.8.8` 은 성공 → 인터넷은 되고 주소 변환(DNS)만 실패 | `/etc/resolv.conf` 를 지우고 `nameserver 8.8.8.8`, `1.1.1.1` 로 직접 지정. 계속 유지하려면 `/etc/wsl.conf` 에 `[network] generateResolvConf = false` |
| 정류장 검색이 두 번 502, 세 번째에 200 (아무것도 안 바꿈) | APP 로그 `TAGO 호출 실패 (getSttnNoList): TimeoutError: The read operation timed out` — 공공 API 응답이 5초를 넘었다 | 이번에 추가한 실패 원인 로그로 원인을 바로 확인했다. `fetch()` 에 1회 재시도 추가 |
| 실제 검색 결과에 기본 정류장(북대전농협 DJB8001793)이 없음 | 가짜 데이터의 정류장이 실제 데이터와 다름. 실제 "북대전" 검색 결과: 북대전IC네거리(DJB8001320, DJB8001321), KT북대전지사(DJB8001795), 북대전세무서/보훈요양원(DJB8002739, DJB8002740) | 시나리오를 `SEARCH` · `STOP_ID` · `STOP_NAME` 으로 실제 정류장 지정 |
| 같은 이름의 정류장이 두 개 (북대전IC네거리 등) | 길 건너편(방향별) 정류장은 이름이 같고 ID가 다르다 | 화면에서 구분이 안 됨 → 정류소 번호 표시 개선 후보 |
