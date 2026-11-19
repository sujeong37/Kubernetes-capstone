-- 즐겨찾기 정류장 테이블 (MySQL 8.4)
CREATE TABLE IF NOT EXISTS favorites (
    node_id    VARCHAR(40)  NOT NULL PRIMARY KEY,                -- 정류장 ID (예: DJB8001793)
    node_name  VARCHAR(100) NOT NULL,                            -- 정류장 이름 (예: 북대전농협)
    alias      VARCHAR(100) NOT NULL,                            -- 사용자가 붙인 별명 (수정 가능)
    created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) DEFAULT CHARSET = utf8mb4;
