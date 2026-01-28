-- ============================================================
-- Migration: 為推廣人分潤系統新增服務類型維度
-- Date: 2026-01-28
-- Description: 
--   1. 新增 commission_type 欄位（'unified' 或 'by_service_type'）
--   2. 新增 commission_percent_charter（包車旅遊分潤百分比）
--   3. 新增 commission_percent_instant_ride（即時派車分潤百分比）
--   4. 更新 calculate_booking_financials 觸發器以支援服務類型維度分潤
-- ============================================================

-- ============================================================
-- 1. 新增欄位到 influencers 表
-- ============================================================

-- 新增分潤類型欄位
ALTER TABLE influencers
ADD COLUMN IF NOT EXISTS commission_type TEXT DEFAULT 'unified';

-- 新增包車旅遊分潤百分比欄位
ALTER TABLE influencers
ADD COLUMN IF NOT EXISTS commission_percent_charter DOUBLE PRECISION DEFAULT NULL;

-- 新增即時派車分潤百分比欄位
ALTER TABLE influencers
ADD COLUMN IF NOT EXISTS commission_percent_instant_ride DOUBLE PRECISION DEFAULT NULL;

-- 新增欄位註解
COMMENT ON COLUMN influencers.commission_type IS '分潤類型: unified（統一比例）或 by_service_type（依服務類型）';
COMMENT ON COLUMN influencers.commission_percent_charter IS '包車旅遊服務的分潤百分比（僅當 commission_type = by_service_type 時使用）';
COMMENT ON COLUMN influencers.commission_percent_instant_ride IS '即時派車服務的分潤百分比（僅當 commission_type = by_service_type 時使用）';

-- 新增約束：確保 commission_type 只能是 'unified' 或 'by_service_type'
ALTER TABLE influencers
DROP CONSTRAINT IF EXISTS check_commission_type;

ALTER TABLE influencers
ADD CONSTRAINT check_commission_type 
CHECK (commission_type IN ('unified', 'by_service_type'));

-- ============================================================
-- 2. 更新現有推廣人的預設值
-- ============================================================

-- 確保所有現有推廣人的 commission_type 為 'unified'
UPDATE influencers
SET commission_type = 'unified'
WHERE commission_type IS NULL;

-- ============================================================
-- 3. 更新 calculate_booking_financials 觸發器函數
-- ============================================================

CREATE OR REPLACE FUNCTION calculate_booking_financials()
RETURNS TRIGGER AS $function$
DECLARE
  v_revenue_share_settings JSONB;
  v_revenue_config RECORD;
  v_company_percentage DECIMAL(5,2);
  v_driver_percentage DECIMAL(5,2);
  v_has_promo_code BOOLEAN;
  v_influencer_commission DECIMAL(10,2);
  v_influencer_record RECORD;
  v_commission_type TEXT;
  v_commission_rate DECIMAL(5,2);
  v_commission_fixed DECIMAL(10,2);
  v_service_type TEXT;
BEGIN
  v_has_promo_code := (NEW.promo_code IS NOT NULL AND NEW.promo_code != '');
  v_service_type := COALESCE(NEW.service_type, 'charter');
  
  -- 如果有推廣者 ID，讀取推廣者的佣金設定
  IF NEW.influencer_id IS NOT NULL THEN
    SELECT 
      commission_fixed,
      commission_percent,
      commission_type,
      commission_percent_charter,
      commission_percent_instant_ride,
      is_commission_fixed_active,
      is_commission_percent_active
    INTO v_influencer_record
    FROM influencers
    WHERE id = NEW.influencer_id
    LIMIT 1;
    
    -- 判斷使用哪種佣金類型
    IF v_influencer_record.is_commission_fixed_active = true THEN
      v_commission_type := 'fixed';
      v_commission_fixed := COALESCE(v_influencer_record.commission_fixed, 0);
      v_commission_rate := 0;
      v_influencer_commission := v_commission_fixed;
      RAISE NOTICE '[Commission] 使用固定金額佣金';
    ELSIF v_influencer_record.is_commission_percent_active = true THEN
      v_commission_type := 'percent';
      
      -- ✅ 新增：根據 commission_type 決定使用哪個百分比
      IF v_influencer_record.commission_type = 'by_service_type' THEN
        -- 依服務類型使用不同百分比
        IF v_service_type = 'charter' THEN
          v_commission_rate := COALESCE(v_influencer_record.commission_percent_charter, v_influencer_record.commission_percent, 0);
          RAISE NOTICE '[Commission] 使用包車旅遊專屬百分比: %', v_commission_rate;
        ELSIF v_service_type = 'instant_ride' THEN
          v_commission_rate := COALESCE(v_influencer_record.commission_percent_instant_ride, v_influencer_record.commission_percent, 0);
          RAISE NOTICE '[Commission] 使用即時派車專屬百分比: %', v_commission_rate;
        ELSE
          -- 未知服務類型，使用預設百分比
          v_commission_rate := COALESCE(v_influencer_record.commission_percent, 0);
          RAISE NOTICE '[Commission] 未知服務類型，使用預設百分比: %', v_commission_rate;
        END IF;
      ELSE
        -- 統一比例模式，使用原始的 commission_percent
        v_commission_rate := COALESCE(v_influencer_record.commission_percent, 0);
        RAISE NOTICE '[Commission] 使用統一百分比佣金: %', v_commission_rate;
      END IF;
      
      v_commission_fixed := 0;
      v_influencer_commission := ROUND((COALESCE(NEW.total_amount, 0) * v_commission_rate / 100)::numeric, 2);
    ELSE
      v_commission_type := 'none';
      v_commission_rate := 0;
      v_commission_fixed := 0;
      v_influencer_commission := 0;
      RAISE NOTICE '[Commission] 推廣者未啟用任何佣金類型';
    END IF;
    
    -- 記錄佣金類型和計算參數到新欄位
    NEW.influencer_commission_type := v_commission_type;
    NEW.influencer_commission_rate := v_commission_rate;
    NEW.influencer_commission_fixed := v_commission_fixed;
    NEW.influencer_commission := v_influencer_commission;
  ELSE
    -- 沒有推廣者，清空佣金相關欄位
    NEW.influencer_commission_type := NULL;
    NEW.influencer_commission_rate := 0;
    NEW.influencer_commission_fixed := 0;
    NEW.influencer_commission := 0;
    v_influencer_commission := 0;
  END IF;
  
  -- ✅ 新增：嘗試從 revenue_share_configs 查詢多維度配置
  SELECT * INTO v_revenue_config
  FROM get_revenue_share_config(
    COALESCE(NEW.country, 'TW'),
    NULL,  -- region 參數（目前不使用）
    v_service_type,
    v_has_promo_code
  );
  
  -- 如果找到多維度配置，使用新系統
  IF v_revenue_config IS NOT NULL THEN
    v_company_percentage := v_revenue_config.company_percentage;
    v_driver_percentage := v_revenue_config.driver_percentage;
    
    RAISE NOTICE '[Revenue Share] ✅ 使用多維度配置: country=%, service_type=%, promo=%, config_id=%',
      NEW.country, v_service_type, v_has_promo_code, v_revenue_config.id;
  ELSE
    -- 回退到 system_settings（向後兼容）
    RAISE NOTICE '[Revenue Share] ⚠️ 未找到多維度配置，回退到 system_settings';
    
    IF v_has_promo_code THEN
      SELECT value INTO v_revenue_share_settings
      FROM system_settings
      WHERE key = 'revenue_share_with_promo'
      LIMIT 1;
      
      IF v_revenue_share_settings IS NULL THEN
        v_company_percentage := 30;
        v_driver_percentage := 70;
      ELSE
        v_company_percentage := (v_revenue_share_settings->>'company_base_percentage')::DECIMAL;
        v_driver_percentage := (v_revenue_share_settings->>'driver_percentage')::DECIMAL;
      END IF;
    ELSE
      SELECT value INTO v_revenue_share_settings
      FROM system_settings
      WHERE key = 'revenue_share_no_promo'
      LIMIT 1;
      
      IF v_revenue_share_settings IS NULL THEN
        v_company_percentage := 25;
        v_driver_percentage := 75;
      ELSE
        v_company_percentage := (v_revenue_share_settings->>'company_percentage')::DECIMAL;
        v_driver_percentage := (v_revenue_share_settings->>'driver_percentage')::DECIMAL;
      END IF;
    END IF;
  END IF;
  
  -- 計算平台費用和司機收入
  NEW.platform_fee := ROUND((COALESCE(NEW.total_amount, 0) * v_company_percentage / 100)::numeric, 2);
  NEW.driver_earning := ROUND((COALESCE(NEW.total_amount, 0) * v_driver_percentage / 100)::numeric, 2);
  
  -- 從公司分潤中扣除推廣者佣金
  IF v_influencer_commission > 0 AND v_has_promo_code THEN
    NEW.platform_fee := NEW.platform_fee - v_influencer_commission;
  END IF;
  
  -- 處理訂單完成時間
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    NEW.completed_at := NOW();
  END IF;
  
  IF NEW.actual_end_time IS NOT NULL AND NEW.completed_at IS NULL THEN
    NEW.completed_at := NEW.actual_end_time;
  END IF;
  
  RETURN NEW;
END;
$function$ LANGUAGE plpgsql;

-- 確認觸發器存在
DROP TRIGGER IF EXISTS calculate_booking_financials_trigger ON bookings;
CREATE TRIGGER calculate_booking_financials_trigger
BEFORE INSERT OR UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION calculate_booking_financials();

-- ============================================================
-- 完成
-- ============================================================

