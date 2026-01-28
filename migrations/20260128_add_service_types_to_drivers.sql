-- 新增 service_types 欄位到 drivers 表
-- 日期：2026-01-28
-- 目的：支援司機服務類型選擇功能（包車旅遊 / 即時派單）

-- ============================================
-- 第一部分: 新增 service_types 欄位
-- ============================================

-- 新增 service_types 欄位，預設為兩種都可接
-- 格式: JSONB 陣列，例如 ["charter", "instant_ride"]
ALTER TABLE drivers
ADD COLUMN IF NOT EXISTS service_types JSONB DEFAULT '["charter", "instant_ride"]'::jsonb;

-- ============================================
-- 第二部分: 更新現有資料
-- ============================================

-- 確保所有現有司機都有預設值（向後兼容）
UPDATE drivers
SET service_types = '["charter", "instant_ride"]'::jsonb
WHERE service_types IS NULL;

-- ============================================
-- 第三部分: 新增欄位註釋
-- ============================================

COMMENT ON COLUMN drivers.service_types IS '司機可接受的服務類型: ["charter"] 包車旅遊, ["instant_ride"] 即時派車, 或兩者都可。必須至少選擇一種。';

-- ============================================
-- 完成
-- ============================================

DO $$
BEGIN
  RAISE NOTICE '✅ drivers 表已新增 service_types 欄位';
  RAISE NOTICE '   - charter: 包車旅遊';
  RAISE NOTICE '   - instant_ride: 即時派單 A→B 點';
  RAISE NOTICE '   - 預設值: 兩種都可接';
END $$;

