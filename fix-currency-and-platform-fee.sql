-- 修復貨幣代碼和平台抽成比例
-- 日期：2025-11-09
-- 問題：
--   1. 價格配置中的貨幣代碼為 'USD'，應該是 'TWD'
--   2. 平台抽成比例為 30%，應該是 25%

-- ============================================
-- 第一部分: 檢查現有配置
-- ============================================

DO $$
DECLARE
    current_config JSONB;
    current_currency TEXT;
BEGIN
    -- 檢查現有價格配置
    SELECT value INTO current_config
    FROM system_settings
    WHERE key = 'pricing_config';
    
    IF current_config IS NOT NULL THEN
        current_currency := current_config->>'currency';
        
        RAISE NOTICE '========================================';
        RAISE NOTICE '📊 現有價格配置';
        RAISE NOTICE '========================================';
        RAISE NOTICE '貨幣代碼: %', current_currency;
        RAISE NOTICE '完整配置: %', current_config;
        RAISE NOTICE '========================================';
    ELSE
        RAISE NOTICE '⚠️  沒有找到價格配置';
    END IF;
END $$;

-- ============================================
-- 第二部分: 更新貨幣代碼為 TWD
-- ============================================

UPDATE system_settings
SET 
    value = jsonb_set(
        value,
        '{currency}',
        '"TWD"'::jsonb
    ),
    updated_at = NOW()
WHERE key = 'pricing_config';

-- 驗證更新
DO $$
DECLARE
    updated_currency TEXT;
BEGIN
    SELECT value->>'currency' INTO updated_currency
    FROM system_settings
    WHERE key = 'pricing_config';
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ 貨幣代碼已更新';
    RAISE NOTICE '========================================';
    RAISE NOTICE '新貨幣代碼: %', updated_currency;
    RAISE NOTICE '========================================';
END $$;

-- ============================================
-- 第三部分: 檢查平台抽成觸發器
-- ============================================

DO $$
DECLARE
    trigger_exists BOOLEAN;
    function_body TEXT;
BEGIN
    -- 檢查觸發器是否存在
    SELECT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'trigger_calculate_booking_financials'
    ) INTO trigger_exists;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 平台抽成觸發器檢查';
    RAISE NOTICE '========================================';
    
    IF trigger_exists THEN
        RAISE NOTICE '✅ 觸發器存在: trigger_calculate_booking_financials';
        
        -- 獲取函數定義
        SELECT pg_get_functiondef(oid) INTO function_body
        FROM pg_proc
        WHERE proname = 'calculate_booking_financials';
        
        RAISE NOTICE '函數定義:';
        RAISE NOTICE '%', function_body;
    ELSE
        RAISE NOTICE '⚠️  觸發器不存在';
    END IF;
    
    RAISE NOTICE '========================================';
END $$;

-- ============================================
-- 第四部分: 重新創建平台抽成計算函數（25%）
-- ============================================

-- 刪除舊的觸發器（如果存在）
DROP TRIGGER IF EXISTS trigger_calculate_booking_financials ON bookings;

-- 刪除舊的函數（如果存在）
DROP FUNCTION IF EXISTS calculate_booking_financials();

-- 創建新的函數（平台抽成 25%）
CREATE OR REPLACE FUNCTION calculate_booking_financials()
RETURNS TRIGGER AS $$
BEGIN
  -- 計算平台抽成（25%）
  NEW.platform_fee := COALESCE(NEW.total_amount, 0) * 0.25;
  
  -- 計算司機收入（75%）
  NEW.driver_earning := COALESCE(NEW.total_amount, 0) * 0.75;
  
  -- 如果狀態變為 completed，設定 completed_at
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    NEW.completed_at := NOW();
  END IF;
  
  -- 如果有 actual_end_time 但沒有 completed_at，同步
  IF NEW.actual_end_time IS NOT NULL AND NEW.completed_at IS NULL THEN
    NEW.completed_at := NEW.actual_end_time;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 創建觸發器
CREATE TRIGGER trigger_calculate_booking_financials
BEFORE INSERT OR UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION calculate_booking_financials();

-- 驗證觸發器創建
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ 平台抽成計算函數已更新';
    RAISE NOTICE '========================================';
    RAISE NOTICE '平台抽成比例: 25%%';
    RAISE NOTICE '司機收入比例: 75%%';
    RAISE NOTICE '觸發器: trigger_calculate_booking_financials';
    RAISE NOTICE '========================================';
END $$;

-- ============================================
-- 第五部分: 更新現有訂單的平台抽成（如果需要）
-- ============================================

-- 檢查是否有訂單需要更新
DO $$
DECLARE
    orders_to_update INTEGER;
BEGIN
    SELECT COUNT(*) INTO orders_to_update
    FROM bookings
    WHERE total_amount IS NOT NULL
      AND (
        platform_fee IS NULL 
        OR platform_fee != total_amount * 0.25
        OR driver_earning IS NULL
        OR driver_earning != total_amount * 0.75
      );
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 現有訂單檢查';
    RAISE NOTICE '========================================';
    RAISE NOTICE '需要更新的訂單數量: %', orders_to_update;
    RAISE NOTICE '========================================';
    
    IF orders_to_update > 0 THEN
        RAISE NOTICE '⚠️  將更新現有訂單的平台抽成和司機收入';
    ELSE
        RAISE NOTICE '✅ 所有訂單的平台抽成和司機收入都是正確的';
    END IF;
END $$;

-- 更新現有訂單（只更新不正確的訂單）
UPDATE bookings
SET 
    platform_fee = total_amount * 0.25,
    driver_earning = total_amount * 0.75,
    updated_at = NOW()
WHERE total_amount IS NOT NULL
  AND (
    platform_fee IS NULL 
    OR platform_fee != total_amount * 0.25
    OR driver_earning IS NULL
    OR driver_earning != total_amount * 0.75
  );

-- 驗證更新結果
DO $$
DECLARE
    total_orders INTEGER;
    correct_orders INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_orders
    FROM bookings
    WHERE total_amount IS NOT NULL;
    
    SELECT COUNT(*) INTO correct_orders
    FROM bookings
    WHERE total_amount IS NOT NULL
      AND platform_fee = total_amount * 0.25
      AND driver_earning = total_amount * 0.75;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ 訂單更新完成';
    RAISE NOTICE '========================================';
    RAISE NOTICE '總訂單數: %', total_orders;
    RAISE NOTICE '正確的訂單數: %', correct_orders;
    RAISE NOTICE '========================================';
    
    IF total_orders = correct_orders THEN
        RAISE NOTICE '✅ 所有訂單的平台抽成和司機收入都已正確更新';
    ELSE
        RAISE WARNING '⚠️  仍有 % 個訂單的平台抽成或司機收入不正確', total_orders - correct_orders;
    END IF;
END $$;

-- ============================================
-- 第六部分: 顯示更新後的配置
-- ============================================

SELECT 
    key,
    value->>'currency' AS currency,
    value->'depositRate' AS deposit_rate,
    updated_at
FROM system_settings
WHERE key = 'pricing_config';

-- 顯示訂單統計
SELECT 
    COUNT(*) AS total_orders,
    COUNT(CASE WHEN platform_fee IS NOT NULL THEN 1 END) AS orders_with_platform_fee,
    COUNT(CASE WHEN driver_earning IS NOT NULL THEN 1 END) AS orders_with_driver_earning,
    ROUND(AVG(platform_fee / NULLIF(total_amount, 0))::numeric, 4) AS avg_platform_fee_rate,
    ROUND(AVG(driver_earning / NULLIF(total_amount, 0))::numeric, 4) AS avg_driver_earning_rate
FROM bookings
WHERE total_amount IS NOT NULL;

