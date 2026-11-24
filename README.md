# Kubernetes Capstone — 버스 도착 정보

버스 도착 정보 앱 하나를 **로컬(WSL) → Docker → EC2 kubeadm 클러스터 → Amazon EKS** 순서로 옮기는 개인 캡스톤 프로젝트.

```
브라우저 → [Web: Nginx] ─ /       → 화면 (index.html)
                        └ /api/*  → [APP: Python FastAPI] → [DB: MySQL 8.4]
                                                         → 공공데이터 TAGO API (키 없으면 가짜 데이터)
```

## 단계

| 단계 | 실행 기반 | 폴더 | 태그 |
|---|---|---|---|
| ① 워크로드 테스트 환경 | WSL 2 Ubuntu (직접 설치) | [`app/`](app/) | `stage1-local` |
| ② 이미지 빌드 · 컨테이너 테스트 | WSL 2 Ubuntu + Docker Engine | `app/was/Dockerfile`, `app/web/Dockerfile`, `docker/` (step2.0 기본 형태 → 2.1 비root → 2.2 빌드 속도 → 2.3 크기 → 2.4 Compose, [`docs/2.*`](docs/)) | `stage2-docker` |
| ③ Kubernetes 전환 | AWS EC2 3대 + kubeadm | `k8s/step3` (Kustomize base, `kubectl apply -k`), `k8s/overlays/`, `helm/bus` (비교용), 점검 `k8s/step3/check.sh`, [정리](docs/3.13-stage3-summary.md) | `stage3-k8s` |
| ④ EKS 전환 | Amazon ECR + EKS Auto Mode | `eks/` | `stage4-eks` |

## 앱 기능

| 기능 | API |
|---|---|
| 상태 확인 | `GET /api/healthz` |
| 정류장 검색 | `GET /api/stops?name=` |
| 도착 정보 | `GET /api/arrivals/{nodeId}` |
| 즐겨찾기 등록 · 조회 · 수정 · 삭제 | `POST · GET /api/favorites`, `PUT · DELETE /api/favorites/{nodeId}` |

실행 방법과 테스트 시나리오(T1~T9)는 [`app/README.md`](app/README.md).

## 비밀 값

DB 비밀번호와 공공데이터 인증키는 저장소에 넣지 않는다. 실행할 때 환경 변수(→ 이후 Kubernetes Secret)로만 주입한다.
