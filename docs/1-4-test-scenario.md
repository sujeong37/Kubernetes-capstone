# 1-4 테스트 시나리오

평가 기준 ①은 "기능 확인 항목(등록 · 조회 · 수정 등)과 기대 결과를 정했다. **이후 모든 단계에서 같은 시나리오로 확인한다**"를 요구한다.
그래서 시나리오를 문서뿐 아니라 **실행 스크립트(`tests/scenario.sh`)**로 만들었다. 단계가 바뀌어도 주소만 바꿔 같은 스크립트를 실행하면, 같은 항목을 같은 기준으로 판정한다.

## 1. 시나리오

| # | 확인 항목 | 요청 | 기대 결과 | 확인하는 것 |
|---|---|---|---|---|
| T1 | 상태 확인 | `GET /api/healthz` | 200, `"status":"ok"` | APP이 살아 있고 Web → APP 연결이 된다 |
| T2 | 화면 | `GET /` | 200, 본문에 "버스 도착 정보" | Web이 화면 파일을 응답한다 |
| T3 | 정류장 검색 | `GET /api/stops?name=북대전` | 200, "북대전농협" 포함 | APP의 조회 기능 (외부 데이터 또는 가짜 데이터) |
| T4 | 도착 정보 | `GET /api/arrivals/DJB8001793` | 200, 버스 목록(`"route"`) | APP의 조회 기능 |
| T5 | **등록** | `POST /api/favorites` | 201 | DB INSERT |
| T6 | **조회** | `GET /api/favorites` | 200, 등록한 정류장 포함 | DB SELECT |
| T7 | **수정** | `PUT /api/favorites/DJB8001793` `{"alias":"집 앞"}` | 200, alias=집 앞 | DB UPDATE |
| T8 | **데이터 유지** | APP · DB 재시작 후 `GET /api/favorites` | alias=집 앞 그대로 | 재시작해도 DB에 남는다 |
| T9 | 삭제 | `DELETE /api/favorites/DJB8001793` | 204, 목록에서 사라짐 | DB DELETE, 다음 실행을 위한 정리 |

- T5 → T6 → T7 → T8은 평가 기준의 "등록 · 조회 · 수정으로 데이터 유지 여부 확인"에 그대로 대응한다.
- T8은 단계마다 "재시작"의 뜻이 바뀐다. 이 차이가 각 단계에서 보여 줄 핵심이다.

| 단계 | T8에서 하는 일 | 확인되는 것 |
|---|---|---|
| 1 WSL | APP `Ctrl+C` 후 재실행, `sudo service mysql restart` | 프로세스가 바뀌어도 데이터는 MySQL 파일에 남는다 |
| 2 Docker | APP · DB 컨테이너 삭제 후 다시 실행 | 컨테이너가 바뀌어도 볼륨의 데이터가 남는다 |
| 3 kubeadm | APP · DB Pod 삭제 → Deployment가 새 Pod 생성 | Pod가 교체돼도 PV의 데이터가 남는다 |
| 4 EKS | 같음 | EBS 볼륨의 데이터가 남는다 |

## 2. 실행 방법

```bash
cd ~/k8s-capstone
bash tests/scenario.sh http://localhost          # 1단계
```

- T1~T7을 실행한 뒤 멈춘다. 그동안 APP과 DB를 재시작하고 `Enter`를 누르면 T8 · T9를 실행한다.
- 멈추지 않고 한 번에 실행: `WAIT=0 bash tests/scenario.sh http://localhost`
- 시작할 때 이전 실행에서 남은 즐겨찾기(DJB8001793)를 지우므로 몇 번이든 다시 실행할 수 있다.
- 모두 통과하면 종료 코드 0, 하나라도 실패하면 1 → 나중에 자동화(CI)에도 그대로 쓸 수 있다.

```
테스트 대상: http://localhost   (2026-11-20 00:37:49)
  [PASS] T1 상태 확인        GET /api/healthz → 200, status ok
  [PASS] T2 화면             GET / → 200, 버스 도착 정보
  [PASS] T3 정류장 검색      GET /api/stops?name=북대전 → 북대전농협 포함
  [PASS] T4 도착 정보        GET /api/arrivals/DJB8001793 → 버스 목록
  [PASS] T5 등록             POST /api/favorites → 201
  [PASS] T6 조회             GET /api/favorites → 등록한 정류장
  [PASS] T7 수정             PUT /api/favorites/DJB8001793 → alias=집 앞

  ▶ 지금 APP과 DB를 재시작(3·4단계는 Pod 삭제)한 뒤, 다시 실행되면 Enter를 누른다.
  [PASS] T8 데이터 유지      재시작 후 GET /api/favorites → alias=집 앞
  [PASS] T9 삭제             DELETE → 204, 목록에서 사라짐

결과: 통과 9 / 9, 실패 0
```

실패하면 실제 응답이 함께 나온다. 예: APP이 꺼져 있으면

```
  [FAIL] T1 상태 확인        GET /api/healthz → 200, status ok
         실제: 502 <html> <head><title>502 Bad Gateway</title> ...
  [PASS] T2 화면             GET / → 200, 버스 도착 정보
```

→ Web(T2)은 통과하고 API(T1, T3~)는 502로 실패해, 어느 계층이 문제인지 바로 보인다.

## 3. 설계 이유

| 결정 | 이유 |
|---|---|
| 스크립트로 만들기 | 사람이 명령을 하나씩 치면 단계마다 확인 방법이 조금씩 달라진다. 같은 스크립트를 실행하면 "같은 시나리오"가 보장된다 |
| 주소만 인자로 받기 | 단계가 바뀌어도 바뀌는 것은 접속 주소뿐이다(1-1 분석: 입구는 Web 하나) |
| 모든 요청을 Web(입구)으로 보내기 | APP에 직접 보내지 않고 사용자와 같은 경로로 확인한다. Web → APP → DB 전체가 연결돼야 통과한다 |
| 화면(T2)과 API(T1)를 따로 확인 | 실패했을 때 Web 문제인지 APP 문제인지 구분된다 |
| T8 앞에서 멈추기 | 재시작은 단계마다 방법이 달라서 스크립트가 대신하지 않는다. 사람이 재시작하는 동안 기다린다 |
| 시작 시 정리, 끝에서 삭제(T9) | 몇 번을 실행해도 같은 결과가 나온다(멱등). 이전 실행의 데이터 때문에 T5가 409로 실패하지 않는다 |
| curl · bash만 사용 | WSL, EC2 노드 등 어디서나 추가 설치 없이 실행된다 |
