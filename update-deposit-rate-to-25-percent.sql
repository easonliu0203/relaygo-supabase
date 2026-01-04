-- 更新訂金比例為 25%
-- 日期：2025-11-09
-- 問題：Supabase system_settings 表中的 depositRate 仍然是 0.3 (30%)，應該改為 0.25 (25%)

-- ============================================
-- 第一部分: 檢查現有訂金比例
-- ============================================

DO $$
DECLARE
    current_config JSONB;
    current_deposit_rate NUMERIC;
BEGIN
    -- 檢查現有價格配置
    SELECT value INTO current_config
    FROM system_settings
    WHERE key = 'pricing_config';
    
    IF current_config IS NOT NULL THEN
        current_deposit_rate := (current_config->>'depositRate')::NUMERIC;
        
        RAISE NOTICE '========================================';
        RAISE NOTICE '📊 現有訂金比例';
        RAISE NOTICE '========================================';
        RAISE NOTICE '訂金比例: %', current_deposit_rate;
        RAISE NOTICE '========================================';
        
        IF current_deposit_rate = 0.3 THEN
            RAISE WARNING '⚠️  訂金比例為 30%%，需要更新為 25%%';
        ELSIF current_deposit_rate = 0.25 THEN
            RAISE NOTICE '✅ 訂金比例已經是 25%%';
        ELSE
            RAISE WARNING '⚠️  訂金比例為 %，預期為 25%%', current_deposit_rate;
        END IF;
    ELSE
        RAISE NOTICE '⚠️  沒有找到價格配置';
    END IF;
END $$;

-- ============================================
-- 第二部分: 更新訂金比例為 25%
-- ============================================

UPDATE system_settings
SET 
    value = jsonb_set(
        value,
        '{depositRate}',
        '0.25'::jsonb
    ),
    updated_at = NOW()
WHERE key = 'pricing_config';

-- 驗證更新
DO $$
DECLARE
    updated_deposit_rate NUMERIC;
BEGIN
    SELECT (value->>'depositRate')::NUMERIC INTO updated_deposit_rate
    FROM system_settings
    WHERE key = 'pricing_config';
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ 訂金比例已更新';
    RAISE NOTICE '========================================';
    RAISE NOTICE '新訂金比例: %', updated_deposit_rate;
    RAISE NOTICE '========================================';
    
    IF updated_deposit_rate = 0.25 THEN
        RAISE NOTICE '✅ 訂金比例更新成功！';
    ELSE
        RAISE WARNING '⚠️  訂金比例更新失敗，當前值: %', updated_deposit_rate;
    END IF;
END $$;

-- ============================================
-- 第三部分: 顯示更新後的完整配置
-- ============================================

SELECT 
    key,
    value->>'currency' AS currency,
    (value->>'depositRate')::NUMERIC AS deposit_rate,
    updated_at
FROM system_settings
WHERE key = 'pricing_config';

