"""APP(WAS): 버스 도착 정보 API (FastAPI)

GET    /api/healthz            상태 확인
GET    /api/stops?name=북대전   정류장 검색  (TAGO 버스정류소정보)
GET    /api/arrivals/{nodeId}  도착 정보    (TAGO 버스도착정보)
GET    /api/favorites          즐겨찾기 조회
POST   /api/favorites          즐겨찾기 등록 {"nodeId": "...", "nodeName": "..."}
PUT    /api/favorites/{nodeId} 즐겨찾기 별명 수정 {"alias": "..."}
DELETE /api/favorites/{nodeId} 즐겨찾기 삭제

환경변수
  DB_PASSWORD                   DB 비밀번호 (필수, 기본값 없음)
  DB_HOST / DB_PORT / DB_NAME   DB 주소 (기본 127.0.0.1 / 3306 / busdb)
  DB_USER                       DB 계정 (기본 bus)
  TAGO_SERVICE_KEY              공공데이터포털 인증키. 비워 두면 가짜 데이터로 동작
  CITY_CODE                     도시 코드 (기본 25 = 대전)
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import pymysql
from fastapi import FastAPI, HTTPException, Query
from pymysql.constants import CLIENT
from pydantic import BaseModel, Field

DB = dict(
    host=os.getenv("DB_HOST", "127.0.0.1"),
    port=int(os.getenv("DB_PORT", "3306")),
    database=os.getenv("DB_NAME", "busdb"),
    user=os.getenv("DB_USER", "bus"),
    password=os.environ["DB_PASSWORD"],          # 없으면 시작하지 않는다 (비밀번호를 코드에 두지 않기 위해)
)
SERVICE_KEY = os.getenv("TAGO_SERVICE_KEY", "")
CITY_CODE = os.getenv("CITY_CODE", "25")
TAGO = "https://apis.data.go.kr/1613000"

app = FastAPI(title="bus-was")


# ---------- 공공데이터 API ----------
def fetch(url: str, name: str) -> str:
    """공공 API 응답 본문. 응답이 늦거나 연결이 끊기면 한 번만 다시 시도한다 (최대 5초 x 2)."""
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(url, timeout=5) as res:
                return res.read().decode("utf-8")
        except urllib.error.HTTPError:            # 401 등 서버가 거절한 응답은 다시 시도해도 같다
            raise
        except (TimeoutError, urllib.error.URLError) as e:
            if attempt == 2:
                raise
            print(f"TAGO 응답 지연 ({name}) — 한 번 더 시도: {type(e).__name__}: {e}", file=sys.stderr, flush=True)


def call_tago(path: str, **params) -> list[dict]:
    """TAGO API 공통 호출. 결과(item) 목록을 돌려준다."""
    params.update(serviceKey=SERVICE_KEY, cityCode=CITY_CODE, _type="json", numOfRows=50)
    try:
        raw = fetch(f"{TAGO}/{path}?{urllib.parse.urlencode(params)}", path.split('/')[-1])
        try:
            data = json.loads(raw)["response"]
        except ValueError:                        # 인증키 오류 등은 _type=json 이어도 XML로 온다
            msgs = [re.search(rf"<{t}>([^<]+)<", raw) for t in ("returnAuthMsg", "resultMsg", "errMsg")]
            raise ValueError(next((m.group(1) for m in msgs if m), "JSON이 아닌 응답"))
        if data["header"]["resultCode"] != "00":   # 호출 한도 초과 등
            raise ValueError(data["header"]["resultMsg"])
    except Exception as e:
        # 원인은 APP 로그에만 남긴다. 인증키가 들어 있는 주소(URL)는 남기지 않는다
        print(f"TAGO 호출 실패 ({path.split('/')[-1]}): {type(e).__name__}: {e}", file=sys.stderr, flush=True)
        raise HTTPException(502, "공공 API 호출에 실패했습니다.")
    items = data["body"].get("items") or {}      # 결과가 없으면 "" 로 온다
    item = items.get("item", [])
    return item if isinstance(item, list) else [item]   # 결과가 1개면 리스트가 아니라 객체로 온다


# ---------- 가짜 데이터 (인증키가 없을 때) ----------
FAKE_STOPS = [
    {"nodeId": "DJB8001793", "nodeName": "북대전농협"},
    {"nodeId": "DJB8002011", "nodeName": "성북3통"},
    {"nodeId": "DJB8005901", "nodeName": "대전역"},
]


def fake_arrivals(node_id: str) -> list[dict]:
    """시간에 따라 버스가 다가오는 것처럼 보이는 가짜 도착 정보 (APP이 여러 개여도 같은 값)"""
    now, seed = int(time.time()), sum(map(ord, node_id))
    buses = []
    for i, route in enumerate(["5", "102", "311", "705"]):
        cycle = 300 + i * 120                      # 노선마다 배차 간격이 다름
        sec = cycle - (now + seed + i * 97) % cycle
        buses.append({"route": route, "arrSec": sec, "leftStops": max(1, sec // 90)})
    return buses


# ---------- 조회 API ----------
@app.get("/api/healthz")
def healthz():
    return {"status": "ok", "mode": "real" if SERVICE_KEY else "fake"}


@app.get("/api/stops")
def search_stops(name: str = Query(min_length=1, max_length=30)):
    if not SERVICE_KEY:
        return [s for s in FAKE_STOPS if name in s["nodeName"]]
    items = call_tago("BusSttnInfoInqireService/getSttnNoList", nodeNm=name)
    return [{"nodeId": i["nodeid"], "nodeName": i["nodenm"]} for i in items]


@app.get("/api/arrivals/{node_id}")
def arrivals(node_id: str):
    if not SERVICE_KEY:
        buses = fake_arrivals(node_id)
    else:
        items = call_tago("ArvlInfoInqireService/getSttnAcctoArvlPrearngeInfoList", nodeId=node_id)
        buses = [{"route": str(i["routeno"]), "arrSec": int(i["arrtime"]),
                  "leftStops": int(i["arrprevstationcnt"])} for i in items]
    return sorted(buses, key=lambda b: b["arrSec"])


# ---------- 즐겨찾기 (DB: 등록 · 조회 · 수정 · 삭제) ----------
def db():
    # FOUND_ROWS: UPDATE가 "바뀐 행"이 아니라 "찾은 행" 수를 돌려주게 함 (같은 별명으로 수정해도 1)
    return pymysql.connect(**DB, charset="utf8mb4", autocommit=True, connect_timeout=3,
                           client_flag=CLIENT.FOUND_ROWS)


class Favorite(BaseModel):
    nodeId: str = Field(min_length=1, max_length=40)
    nodeName: str = Field(min_length=1, max_length=100)


class Alias(BaseModel):
    alias: str = Field(min_length=1, max_length=100)


@app.get("/api/favorites")
def list_favorites():
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT node_id, node_name, alias FROM favorites ORDER BY created_at")
        return [{"nodeId": r[0], "nodeName": r[1], "alias": r[2]} for r in cur.fetchall()]


@app.post("/api/favorites", status_code=201)
def add_favorite(fav: Favorite):
    with db() as conn, conn.cursor() as cur:
        if cur.execute("INSERT IGNORE INTO favorites (node_id, node_name, alias) VALUES (%s, %s, %s)",
                       (fav.nodeId, fav.nodeName, fav.nodeName)) == 0:
            raise HTTPException(409, "이미 등록된 정류장입니다.")
    return {"nodeId": fav.nodeId, "nodeName": fav.nodeName, "alias": fav.nodeName}


@app.put("/api/favorites/{node_id}")
def rename_favorite(node_id: str, body: Alias):
    with db() as conn, conn.cursor() as cur:
        if cur.execute("UPDATE favorites SET alias = %s WHERE node_id = %s", (body.alias, node_id)) == 0:
            raise HTTPException(404, "즐겨찾기에 없는 정류장입니다.")
    return {"nodeId": node_id, "alias": body.alias}


@app.delete("/api/favorites/{node_id}", status_code=204)
def delete_favorite(node_id: str):
    with db() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM favorites WHERE node_id = %s", (node_id,))
