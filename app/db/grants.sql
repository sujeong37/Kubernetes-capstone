-- 2단계(컨테이너)부터 사용: MySQL 공식 이미지가 데이터가 빈 상태로 처음 시작할 때 실행한다 (/docker-entrypoint-initdb.d).
-- 이미지는 MYSQL_USER(bus)에게 busdb 전체 권한(ALL: 표 생성 · 삭제 포함)을 준다.
-- 1단계(1-3)와 같은 최소 권한(데이터 읽기 · 쓰기 · 수정 · 삭제)으로 줄인다.
REVOKE ALL PRIVILEGES ON busdb.* FROM 'bus'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON busdb.* TO 'bus'@'%';
