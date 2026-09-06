-- ============================================================
-- 新增 zone 欄位到 airport_transfer_pricing
-- zone：記錄此定價區包含的行政區名稱（顯示用）
-- ============================================================

ALTER TABLE airport_transfer_pricing
  ADD COLUMN IF NOT EXISTS zone TEXT;

COMMENT ON COLUMN airport_transfer_pricing.zone IS '此定價區包含的行政區名稱，以「、」分隔（顯示用）';

-- ============================================================
-- 更新新北三個子區的 zone 值
-- ============================================================

UPDATE airport_transfer_pricing
SET zone = '三重、新莊、八里、三峽、鶯歌、樹林、五股、蘆洲、中和、永和、板橋、泰山、土城'
WHERE country = 'TW' AND region = '新北A';

UPDATE airport_transfer_pricing
SET zone = '汐止、深坑'
WHERE country = 'TW' AND region = '新北B';

UPDATE airport_transfer_pricing
SET zone = '瑞芳、三芝、萬里'
WHERE country = 'TW' AND region = '新北C';

-- ============================================================
-- 驗證
-- ============================================================
SELECT region, vehicle_type, tpe_price, zone
FROM airport_transfer_pricing
WHERE country = 'TW' AND region IN ('新北A', '新北B', '新北C')
ORDER BY region, vehicle_type;
