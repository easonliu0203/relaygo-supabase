-- ============================================
-- 為 bookings 表新增多維度欄位
-- ============================================
-- 創建日期: 2026-01-27
-- 用途: 支援多維度分潤配置系統
-- 新增欄位: country, service_type
-- ============================================

-- 1. 新增欄位到 bookings 表
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS country VARCHAR(2) DEFAULT 'TW',
ADD COLUMN IF NOT EXISTS service_type VARCHAR(50) DEFAULT 'charter';

-- 2. 新增註釋
COMMENT ON COLUMN bookings.country IS '國家代碼 (ISO 3166-1 alpha-2): TW, JP, KR, etc.';
COMMENT ON COLUMN bookings.service_type IS '服務類型: charter (包車旅遊), instant_ride (即時派車 A→B 點)';

-- 3. 新增索引以優化查詢
CREATE INDEX IF NOT EXISTS idx_bookings_country ON bookings(country);
CREATE INDEX IF NOT EXISTS idx_bookings_service_type ON bookings(service_type);
CREATE INDEX IF NOT EXISTS idx_bookings_country_service ON bookings(country, service_type);

-- 4. 新增檢查約束
ALTER TABLE bookings
ADD CONSTRAINT check_country_code 
CHECK (country ~ '^[A-Z]{2}$');

ALTER TABLE bookings
ADD CONSTRAINT check_service_type 
CHECK (service_type IN ('charter', 'instant_ride'));

-- 5. 更新現有訂單的預設值（確保資料一致性）
UPDATE bookings
SET 
  country = COALESCE(country, 'TW'),
  service_type = COALESCE(service_type, 'charter')
WHERE country IS NULL OR service_type IS NULL;

-- 6. 驗證資料
DO $$
DECLARE
  v_total_bookings INTEGER;
  v_bookings_with_country INTEGER;
  v_bookings_with_service_type INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_total_bookings FROM bookings;
  SELECT COUNT(*) INTO v_bookings_with_country FROM bookings WHERE country IS NOT NULL;
  SELECT COUNT(*) INTO v_bookings_with_service_type FROM bookings WHERE service_type IS NOT NULL;
  
  RAISE NOTICE '=== Bookings 表欄位新增完成 ===';
  RAISE NOTICE '總訂單數: %', v_total_bookings;
  RAISE NOTICE '有 country 的訂單: %', v_bookings_with_country;
  RAISE NOTICE '有 service_type 的訂單: %', v_bookings_with_service_type;
  
  IF v_total_bookings = v_bookings_with_country AND v_total_bookings = v_bookings_with_service_type THEN
    RAISE NOTICE '✅ 所有訂單都已正確填入預設值';
  ELSE
    RAISE WARNING '⚠️ 部分訂單缺少必要欄位';
  END IF;
END $$;

