-- ============================================================================
-- 分潤設定：統一真實來源 + 歷史快照
-- 日期：2026-09-05
--
-- 背景
--   後台「系統設定 → 分成設定」頁寫入 revenue_share_configs，但
--   calculate_booking_financials() 內的判斷式寫成 "IF v_revenue_config IS NOT NULL"。
--   PostgreSQL 的 record IS NOT NULL 要「所有欄位皆非 NULL」才成立，而未使用
--   優惠碼的設定 company_base_percentage 為 NULL，使該判斷恆為 false，設定表被
--   完全忽略、改讀 system_settings。結果：後台頁面對「未使用優惠碼」的所有服務
--   類型改什麼都無效。
--
--   另外分潤比例沒有快照，trigger 為 BEFORE INSERT OR UPDATE，歷史訂單只要被
--   更新就會用「當下的設定」重算，竄改已結算的帳。
--
-- 本次變更
--   1. bookings 新增分潤快照欄位，並回填既有訂單（用已入帳金額反推）
--   2. revenue_share_configs 的值對齊實際規則：一般單 25/75、推廣單 30/70
--   3. 修正 IS NOT NULL 判斷 → 改判單一欄位
--   4. trigger 改為「建單寫快照、之後永遠沿用快照」
--   5. 推廣佣金費率同樣鎖快照；金額仍隨 total_amount 連動
--   6. by_service_type 佣金補上 airport_transfer（原本漏了，會蓋掉後端算好的值）
--   7. completed_at 判斷加 TG_OP 短路，避免 BEFORE INSERT 存取未賦值的 OLD
-- ============================================================================

-- 步驟 1：訂單加上分潤快照欄位
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS revenue_share_company_percentage NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS revenue_share_driver_percentage  NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS revenue_share_config_id          UUID,
  ADD COLUMN IF NOT EXISTS revenue_share_locked_at          TIMESTAMPTZ;

COMMENT ON COLUMN bookings.revenue_share_company_percentage IS '建單當下的公司抽成％快照，之後永不變動';
COMMENT ON COLUMN bookings.revenue_share_driver_percentage  IS '建單當下的司機分潤％快照，之後永不變動';
COMMENT ON COLUMN bookings.revenue_share_config_id          IS '快照來源 revenue_share_configs.id，供追溯';
COMMENT ON COLUMN bookings.revenue_share_locked_at          IS '快照鎖定時間';

-- 步驟 2：回填既有訂單的快照，用「實際已入帳的金額」反推，真正凍結歷史
UPDATE bookings b
SET revenue_share_driver_percentage = ROUND((b.driver_earning / b.total_amount * 100)::numeric, 2),
    revenue_share_company_percentage = ROUND(((b.platform_fee + COALESCE(b.influencer_commission,0)) / b.total_amount * 100)::numeric, 2),
    revenue_share_locked_at = COALESCE(b.created_at, now())
WHERE b.revenue_share_driver_percentage IS NULL
  AND COALESCE(b.total_amount, 0) > 0;

-- 沒有金額的訂單：用當下規則補上，避免留 NULL
UPDATE bookings b
SET revenue_share_driver_percentage = CASE WHEN b.promo_code IS NOT NULL AND b.promo_code <> '' THEN 70 ELSE 75 END,
    revenue_share_company_percentage = CASE WHEN b.promo_code IS NOT NULL AND b.promo_code <> '' THEN 30 ELSE 25 END,
    revenue_share_locked_at = COALESCE(b.created_at, now())
WHERE b.revenue_share_driver_percentage IS NULL;


-- 步驟 3：設定表的值對齊成實際在跑的規則（一般單 25/75、推廣單 30/70）
UPDATE revenue_share_configs
SET company_percentage = 25, driver_percentage = 75, company_base_percentage = NULL,
    description = '台灣全國 - ' || CASE service_type
        WHEN 'charter' THEN '包車旅遊' WHEN 'airport_transfer' THEN '機場接送'
        WHEN 'instant_ride' THEN '即時派車' ELSE service_type END
      || ' - 未使用優惠碼', updated_at = now(), updated_by = 'align-single-source'
WHERE country = 'TW' AND has_promo_code = false;

UPDATE revenue_share_configs
SET company_percentage = 30, driver_percentage = 70, company_base_percentage = 30,
    description = '台灣全國 - ' || CASE service_type
        WHEN 'charter' THEN '包車旅遊' WHEN 'airport_transfer' THEN '機場接送'
        WHEN 'instant_ride' THEN '即時派車' ELSE service_type END
      || ' - 使用優惠碼（推廣者佣金從公司 30% 內扣）', updated_at = now(), updated_by = 'align-single-source'
WHERE country = 'TW' AND has_promo_code = true;


CREATE OR REPLACE FUNCTION calculate_booking_financials()
RETURNS TRIGGER AS $fn$
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

  -- ==========================================================================
  -- A. 分潤比例
  --    唯一真實來源 = revenue_share_configs（後台「系統設定 → 分成設定」頁）
  --    建單當下寫入快照，之後永遠沿用快照，改設定不會竄改歷史訂單
  -- ==========================================================================
  IF TG_OP = 'UPDATE' AND OLD.revenue_share_driver_percentage IS NOT NULL THEN
    -- 已鎖定：沿用建單當下的比例
    NEW.revenue_share_company_percentage := OLD.revenue_share_company_percentage;
    NEW.revenue_share_driver_percentage  := OLD.revenue_share_driver_percentage;
    NEW.revenue_share_config_id          := OLD.revenue_share_config_id;
    NEW.revenue_share_locked_at          := OLD.revenue_share_locked_at;

    v_company_percentage := OLD.revenue_share_company_percentage;
    v_driver_percentage  := OLD.revenue_share_driver_percentage;
  ELSE
    SELECT * INTO v_revenue_config
    FROM get_revenue_share_config(
      COALESCE(NEW.country, 'TW'), NULL, v_service_type, v_has_promo_code
    );

    -- ✅ 修正：原本寫 "IF v_revenue_config IS NOT NULL"。
    --    PostgreSQL 的 record IS NOT NULL 要「所有欄位皆非 NULL」才成立，
    --    而未使用優惠碼的設定 company_base_percentage 為 NULL，
    --    導致設定表永遠被判定為空、掉進 system_settings fallback，
    --    後台「分成設定」頁改的值對一般單完全無效。
    IF v_revenue_config.driver_percentage IS NOT NULL THEN
      v_company_percentage := v_revenue_config.company_percentage;
      v_driver_percentage  := v_revenue_config.driver_percentage;
      NEW.revenue_share_config_id := v_revenue_config.id;
    ELSE
      -- 保險絲：設定表查無對應資料才會走到（正常不應發生）
      NEW.revenue_share_config_id := NULL;
      RAISE WARNING '[Revenue Share] 設定表查無資料，改用 system_settings: country=%, service=%, promo=%',
        NEW.country, v_service_type, v_has_promo_code;

      IF v_has_promo_code THEN
        SELECT value INTO v_revenue_share_settings FROM system_settings WHERE key = 'revenue_share_with_promo' LIMIT 1;
        v_company_percentage := COALESCE((v_revenue_share_settings->>'company_base_percentage')::DECIMAL, 30);
        v_driver_percentage  := COALESCE((v_revenue_share_settings->>'driver_percentage')::DECIMAL, 70);
      ELSE
        SELECT value INTO v_revenue_share_settings FROM system_settings WHERE key = 'revenue_share_no_promo' LIMIT 1;
        v_company_percentage := COALESCE((v_revenue_share_settings->>'company_percentage')::DECIMAL, 25);
        v_driver_percentage  := COALESCE((v_revenue_share_settings->>'driver_percentage')::DECIMAL, 75);
      END IF;
    END IF;

    NEW.revenue_share_company_percentage := v_company_percentage;
    NEW.revenue_share_driver_percentage  := v_driver_percentage;
    NEW.revenue_share_locked_at          := now();
  END IF;

  -- ==========================================================================
  -- B. 推廣佣金
  --    佣金「費率」同樣鎖定快照；金額隨 total_amount 連動重算
  -- ==========================================================================
  IF NEW.influencer_id IS NOT NULL THEN
    IF TG_OP = 'UPDATE' AND OLD.influencer_commission_type IS NOT NULL THEN
      v_commission_type  := OLD.influencer_commission_type;
      v_commission_rate  := COALESCE(OLD.influencer_commission_rate, 0);
      v_commission_fixed := COALESCE(OLD.influencer_commission_fixed, 0);
    ELSE
      SELECT commission_fixed, commission_percent, commission_type,
             commission_percent_charter, commission_percent_instant_ride,
             commission_percent_airport_transfer,
             is_commission_fixed_active, is_commission_percent_active
      INTO v_influencer_record
      FROM influencers WHERE id = NEW.influencer_id LIMIT 1;

      IF v_influencer_record.is_commission_fixed_active = true THEN
        v_commission_type  := 'fixed';
        v_commission_fixed := COALESCE(v_influencer_record.commission_fixed, 0);
        v_commission_rate  := 0;
      ELSIF v_influencer_record.is_commission_percent_active = true THEN
        v_commission_type := 'percent';
        IF v_influencer_record.commission_type = 'by_service_type' THEN
          -- ✅ 修正：原本漏了 airport_transfer，會退回統一費率蓋掉後端算好的值
          v_commission_rate := CASE v_service_type
            WHEN 'charter'           THEN COALESCE(v_influencer_record.commission_percent_charter,           v_influencer_record.commission_percent, 0)
            WHEN 'instant_ride'      THEN COALESCE(v_influencer_record.commission_percent_instant_ride,      v_influencer_record.commission_percent, 0)
            WHEN 'airport_transfer'  THEN COALESCE(v_influencer_record.commission_percent_airport_transfer,  v_influencer_record.commission_percent, 0)
            ELSE COALESCE(v_influencer_record.commission_percent, 0)
          END;
        ELSE
          v_commission_rate := COALESCE(v_influencer_record.commission_percent, 0);
        END IF;
        v_commission_fixed := 0;
      ELSE
        v_commission_type  := 'none';
        v_commission_rate  := 0;
        v_commission_fixed := 0;
      END IF;
    END IF;

    v_influencer_commission := CASE v_commission_type
      WHEN 'fixed'   THEN v_commission_fixed
      WHEN 'percent' THEN ROUND((COALESCE(NEW.total_amount, 0) * v_commission_rate / 100)::numeric, 2)
      ELSE 0
    END;

    NEW.influencer_commission_type  := v_commission_type;
    NEW.influencer_commission_rate  := v_commission_rate;
    NEW.influencer_commission_fixed := v_commission_fixed;
    NEW.influencer_commission       := v_influencer_commission;
  ELSE
    NEW.influencer_commission_type  := NULL;
    NEW.influencer_commission_rate  := 0;
    NEW.influencer_commission_fixed := 0;
    NEW.influencer_commission       := 0;
    v_influencer_commission := 0;
  END IF;

  -- ==========================================================================
  -- C. 金額結算
  -- ==========================================================================
  NEW.platform_fee   := ROUND((COALESCE(NEW.total_amount, 0) * v_company_percentage / 100)::numeric, 2);
  NEW.driver_earning := ROUND((COALESCE(NEW.total_amount, 0) * v_driver_percentage  / 100)::numeric, 2);

  -- 推廣佣金從公司那一份內扣，司機不受影響
  IF v_influencer_commission > 0 AND v_has_promo_code THEN
    NEW.platform_fee := NEW.platform_fee - v_influencer_commission;
  END IF;

  -- ✅ 修正：TG_OP 短路，避免 BEFORE INSERT 直接建立 completed 訂單時存取未賦值的 OLD
  IF NEW.status = 'completed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'completed') THEN
    NEW.completed_at := NOW();
  END IF;

  IF NEW.actual_end_time IS NOT NULL AND NEW.completed_at IS NULL THEN
    NEW.completed_at := NEW.actual_end_time;
  END IF;

  RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;
