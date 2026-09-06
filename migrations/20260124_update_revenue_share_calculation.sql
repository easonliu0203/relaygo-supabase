-- ============================================
-- 更新分潤計算邏輯以支援動態分潤設定
-- ============================================
-- 創建日期: 2026-01-24
-- 用途: 根據是否使用優惠碼，動態計算平台抽成和司機收入
-- 場景 1：未使用優惠碼（預設：公司 25%, 司機 75%）
-- 場景 2：使用優惠碼（預設：公司基準 30%, 司機 70%，推廣者從公司基準扣除）
-- ============================================

-- 1. 刪除舊的觸發器
DROP TRIGGER IF EXISTS trigger_calculate_booking_financials ON bookings;

-- 2. 創建新的分潤計算函數
CREATE OR REPLACE FUNCTION calculate_booking_financials()
RETURNS TRIGGER AS $$
DECLARE
  v_revenue_share_settings JSONB;
  v_company_percentage DECIMAL(5,2);
  v_driver_percentage DECIMAL(5,2);
  v_has_promo_code BOOLEAN;
  v_influencer_commission DECIMAL(10,2);
BEGIN
  -- 檢查是否使用優惠碼
  v_has_promo_code := (NEW.promo_code IS NOT NULL AND NEW.promo_code != '');
  
  -- 根據是否使用優惠碼，獲取對應的分潤設定
  IF v_has_promo_code THEN
    -- 場景 2：使用優惠碼
    SELECT value INTO v_revenue_share_settings
    FROM system_settings
    WHERE key = 'revenue_share_with_promo'
    LIMIT 1;
    
    -- 如果找不到設定，使用預設值（公司基準 30%, 司機 70%）
    IF v_revenue_share_settings IS NULL THEN
      v_company_percentage := 30;
      v_driver_percentage := 70;
      RAISE NOTICE '[Revenue Share] 使用預設值（場景 2）: 公司基準 30%%, 司機 70%%';
    ELSE
      v_company_percentage := (v_revenue_share_settings->>'company_base_percentage')::DECIMAL;
      v_driver_percentage := (v_revenue_share_settings->>'driver_percentage')::DECIMAL;
      RAISE NOTICE '[Revenue Share] 使用設定值（場景 2）';
    END IF;
    
    -- 計算平台抽成（公司基準）
    NEW.platform_fee := ROUND((COALESCE(NEW.total_amount, 0) * v_company_percentage / 100)::numeric, 2);
    
    -- 計算司機收入
    NEW.driver_earning := ROUND((COALESCE(NEW.total_amount, 0) * v_driver_percentage / 100)::numeric, 2);
    
    -- 如果有推廣者佣金，從平台抽成中扣除
    v_influencer_commission := COALESCE(NEW.influencer_commission, 0);
    IF v_influencer_commission > 0 THEN
      NEW.platform_fee := NEW.platform_fee - v_influencer_commission;
      RAISE NOTICE '[Revenue Share] 推廣者佣金已從公司抽成中扣除';
    END IF;
    
  ELSE
    -- 場景 1：未使用優惠碼
    SELECT value INTO v_revenue_share_settings
    FROM system_settings
    WHERE key = 'revenue_share_no_promo'
    LIMIT 1;
    
    -- 如果找不到設定，使用預設值（公司 25%, 司機 75%）
    IF v_revenue_share_settings IS NULL THEN
      v_company_percentage := 25;
      v_driver_percentage := 75;
      RAISE NOTICE '[Revenue Share] 使用預設值（場景 1）: 公司 25%%, 司機 75%%';
    ELSE
      v_company_percentage := (v_revenue_share_settings->>'company_percentage')::DECIMAL;
      v_driver_percentage := (v_revenue_share_settings->>'driver_percentage')::DECIMAL;
      RAISE NOTICE '[Revenue Share] 使用設定值（場景 1）';
    END IF;
    
    -- 計算平台抽成
    NEW.platform_fee := ROUND((COALESCE(NEW.total_amount, 0) * v_company_percentage / 100)::numeric, 2);
    
    -- 計算司機收入
    NEW.driver_earning := ROUND((COALESCE(NEW.total_amount, 0) * v_driver_percentage / 100)::numeric, 2);
  END IF;
  
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

-- 3. 創建新的觸發器
CREATE TRIGGER trigger_calculate_booking_financials
BEFORE INSERT OR UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION calculate_booking_financials();

-- 4. 驗證觸發器創建
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ 分潤計算函數已更新';
    RAISE NOTICE '========================================';
    RAISE NOTICE '場景 1（未使用優惠碼）: 從 system_settings.revenue_share_no_promo 讀取';
    RAISE NOTICE '場景 2（使用優惠碼）: 從 system_settings.revenue_share_with_promo 讀取';
    RAISE NOTICE '推廣者佣金: 從公司分潤中扣除';
    RAISE NOTICE '觸發器: trigger_calculate_booking_financials';
    RAISE NOTICE '========================================';
END $$;

-- 5. 更新現有訂單的分潤（可選，如果需要重新計算所有訂單）
-- 注意：這會觸發 trigger，所以會自動使用新的計算邏輯
-- UPDATE bookings
-- SET updated_at = NOW()
-- WHERE total_amount IS NOT NULL;

-- 6. 廢除訂單促成費設定（如果存在）
-- 注意：這不會刪除數據，只是標記為不再使用
UPDATE system_settings
SET description = '【已廢除】訂單促成費設定（Order Acquisition Fee / Referral Fee）- 已由新的分潤系統取代'
WHERE key = 'order_acquisition_fee';

-- 7. 完成訊息
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ 分潤系統更新完成';
    RAISE NOTICE '========================================';
    RAISE NOTICE '1. 新的分潤計算函數已創建';
    RAISE NOTICE '2. 觸發器已更新';
    RAISE NOTICE '3. 訂單促成費設定已標記為廢除';
    RAISE NOTICE '4. 所有新訂單將使用新的分潤規則';
    RAISE NOTICE '========================================';
END $$;

