# syntax=docker/dockerfile:1

# [베이스 이미지] 파이썬 3.14 실행 환경 (Debian slim: 필요한 최소 패키지만 포함)
FROM python:3.14-slim

# [작업 디렉터리] 이후 명령은 /app 에서 실행된다
WORKDIR /app

# [의존성 설치] 라이브러리 목록이 바뀔 때만 다시 실행된다
COPY requirements.txt ./
RUN pip install -r requirements.txt

# [소스 복사] 소스가 바뀌면 이 단계부터 다시 실행된다
COPY app.py ./

# [설정 기본값] 비밀이 아닌 값만 넣는다. DB 주소는 같은 네트워크의 DB 컨테이너 이름(db)
ENV DB_HOST=db \
    DB_PORT=3306 \
    DB_NAME=busdb \
    CITY_CODE=25 \
    PYTHONUNBUFFERED=1
# DB_USER · DB_PASSWORD · TAGO_SERVICE_KEY 는 이미지에 넣지 않는다. 실행할 때 주입한다

# [포트 문서화] 컨테이너 안에서 APP이 받는 포트
EXPOSE 8000

# [실행 명령] exec 형식: uvicorn 이 PID 1 이 되어 docker stop 의 SIGTERM 을 직접 받는다
#             0.0.0.0: 컨테이너 밖(같은 네트워크의 Web 컨테이너)에서 오는 요청을 받는다
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
