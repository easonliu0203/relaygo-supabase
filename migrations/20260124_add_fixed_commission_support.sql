-- Migration: 新增固定金額分潤支援
-- Date: 2026-01-24
-- Description: 為 bookings 和 promo_code_usage 表新增固定金額佣金欄位，並更新觸發器函數

-- ============================================================================
-- 1. 修改 bookings 表 - 新增固定金額分潤相關欄位
-- ============================================================================

-- 新增佣金類型欄位
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS influencer_commission_type TEXT DEFAULT 'percent' 
CHECK (influencer_commission_type IN ('fixed', 'percent'));

-- 新增百分比佣金率欄位
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS influencer_commission_rate NUMERIC DEFAULT 0;

-- 新增固定金額佣金欄位
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS influencer_commission_fixed NUMERIC DEFAULT 0;

-- 添加欄位註解
COMMENT ON COLUMN bookings.influencer_commission_type IS '推廣者佣金類型：fixed=固定金額, percent=百分比';
COMMENT ON COLUMN bookings.influencer_commission_rate IS '推廣者佣金百分比率（如 5.0 表示 5%）';
COMMENT ON COLUMN bookings.influencer_commission_fixed IS '推廣者固定金額佣金（如 500 表示 500 元）';

-- ============================================================================
-- 2. 修改 promo_code_usage 表 - 新增固定金額佣金欄位
-- ============================================================================

-- 新增固定金額佣金欄位
ALTER TABLE promo_code_usage 
ADD COLUMN IF NOT EXISTS commission_fixed_amount NUMERIC DEFAULT 0;

-- 添加欄位註解
COMMENT ON COLUMN promo_code_usage.commission_fixed_amount IS '固定金額佣金（當 commission_type = fixed 時使用）';

-- ============================================================================
-- 3. 更新 calculate_booking_financials 觸發器函數
-- ============================================================================

CREATE OR REPLACE FUNCTION public.calculate_booking_financials()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  v_revenue_share_settings JSONB;
  v_company_percentage DECIMAL(5,2);
  v_driver_percentage DECIMAL(5,2);
  v_has_promo_code BOOLEAN;
  v_influencer_commission DECIMAL(10,2);
  v_influencer_record RECORD;
  v_commission_type TEXT;
  v_commission_rate DECIMAL(5,2);
  v_commission_fixed DECIMAL(10,2);
BEGIN
  v_has_promo_code := (NEW.promo_code IS NOT NULL AND NEW.promo_code != '');
  
  -- 如果有推廣者 ID，讀取推廣者的佣金設定
  IF NEW.influencer_id IS NOT NULL THEN
    SELECT 
      commission_fixed,
      commission_percent,
      is_commission_fixed_active,
      is_commission_percent_active
    INTO v_influencer_record
    FROM influencers
    WHERE id = NEW.influencer_id
    LIMIT 1;
    
    -- 判斷使用哪種佣金類型
    IF v_influencer_record.is_commission_fixed_active = true THEN
      -- 使用固定金額佣金
      v_commission_type := 'fixed';
      v_commission_fixed := COALESCE(v_influencer_record.commission_fixed, 0);
      v_commission_rate := 0;
      v_influencer_commission := v_commission_fixed;
      RAISE NOTICE '[Commission] 使用固定金額佣金';
    ELSIF v_influencer_record.is_commission_percent_active = true THEN
      -- 使用百分比佣金
      v_commission_type := 'percent';
      v_commission_rate := COALESCE(v_influencer_record.commission_percent, 0);
      v_commission_fixed := 0;
      v_influencer_commission := ROUND((COALESCE(NEW.total_amount, 0) * v_commission_rate / 100)::numeric, 2);
      RAISE NOTICE '[Commission] 使用百分比佣金';
    ELSE
      -- 兩者都未啟用，不計算佣金
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
  
  -- 計算平台費用和司機收入
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
    
    NEW.platform_fee := ROUND((COALESCE(NEW.total_amount, 0) * v_company_percentage / 100)::numeric, 2);
    NEW.driver_earning := ROUND((COALESCE(NEW.total_amount, 0) * v_driver_percentage / 100)::numeric, 2);
    
    -- 從公司分潤中扣除推廣者佣金
    IF v_influencer_commission > 0 THEN
      NEW.platform_fee := NEW.platform_fee - v_influencer_commission;
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
    
    NEW.platform_fee := ROUND((COALESCE(NEW.total_amount, 0) * v_company_percentage / 100)::numeric, 2);
    NEW.driver_earning := ROUND((COALESCE(NEW.total_amount, 0) * v_driver_percentage / 100)::numeric, 2);
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
$function$;

