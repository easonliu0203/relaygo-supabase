-- 為 promo_code_usage 表新增 service_type 欄位
-- 用於記錄推廣碼使用時的服務類型快照，便於對帳與歷史還原

ALTER TABLE promo_code_usage ADD COLUMN IF NOT EXISTS service_type VARCHAR(30);
COMMENT ON COLUMN promo_code_usage.service_type IS '服務類型快照 (charter / instant_ride / airport_transfer)';
