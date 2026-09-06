-- ============================================================================
-- 活動優惠碼（campaign）+ 司機固定給付
-- 日期：2026-09-05
--
-- 需求
--   推一檔活動：L 九人座 8 小時基本車資打七折，司機改領固定額（4000/4500，
--   隨時可調），跨區費／超時費等附加費照原價、照一般單 25/75 分潤，
--   不給推廣人佣金，限一個帳號用一次，活動期間可手動設定。
--
-- 設計
--   活動碼與推廣人碼同存 influencers 表，以 affiliate_type='campaign' 區隔，
--   佣金開關全關即自動不分潤（沿用既有邏輯，不需額外處理）。
--
--   分潤 trigger 新增「固定給付」分支：
--       折後基本車資 = base_price - discount_amount
--       附加費       = total_amount - 折後基本車資
--       司機         = 固定額 + 附加費 × 司機%
--       平台         = total_amount - 司機
--   司機給付模式與固定額同樣寫入訂單快照，改活動設定不影響已成立的訂單。
--
--   活動單雖然帶優惠碼，但沒有推廣人抽佣，附加費一律用「未使用優惠碼」的
--   比例（25/75），否則司機平白少 5%，而那 5% 沒有任何人領走。
--
--   另加保險絲：固定給付設得太高導致平台留存為負時直接擋下建單。
-- ============================================================================

-- 活動碼設定欄位（沿用 influencers 表，以 affiliate_type='campaign' 區隔）
ALTER TABLE influencers
  ADD COLUMN IF NOT EXISTS limit_vehicle_types  TEXT[],
  ADD COLUMN IF NOT EXISTS limit_service_types  TEXT[],
  ADD COLUMN IF NOT EXISTS discount_base        VARCHAR(20) DEFAULT 'total',
  ADD COLUMN IF NOT EXISTS driver_payout_mode   VARCHAR(10) DEFAULT 'percent',
  ADD COLUMN IF NOT EXISTS driver_fixed_amount  NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS valid_from           TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS valid_until          TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS per_user_limit       INT;

COMMENT ON COLUMN influencers.limit_vehicle_types IS '限定車型，如 {L}；NULL 表示不限';
COMMENT ON COLUMN influencers.limit_service_types IS '限定服務類型，如 {charter}；NULL 表示不限';
COMMENT ON COLUMN influencers.discount_base      IS 'total=折總額（推廣人碼慣例）；base_price=只折基本車資（活動碼）';
COMMENT ON COLUMN influencers.driver_payout_mode IS 'percent=照分潤比例；fixed=基本車資固定給付，附加費仍照比例';
COMMENT ON COLUMN influencers.driver_fixed_amount IS 'fixed 模式下司機的基本車資固定給付額，可隨時調整（僅影響之後的新單）';
COMMENT ON COLUMN influencers.valid_from  IS '活動開始時間，NULL 表示不限';
COMMENT ON COLUMN influencers.valid_until IS '活動結束時間，NULL 表示不限';
COMMENT ON COLUMN influencers.per_user_limit IS '每個帳號可使用次數，NULL 表示不限';

-- 訂單端快照
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS driver_payout_mode  VARCHAR(10) DEFAULT 'percent',
  ADD COLUMN IF NOT EXISTS driver_fixed_amount NUMERIC(10,2) DEFAULT 0;

COMMENT ON COLUMN bookings.driver_payout_mode  IS '建單當下的司機給付模式快照，之後永不變動';
COMMENT ON COLUMN bookings.driver_fixed_amount IS '建單當下的司機固定給付額快照，之後永不變動';

-- 允許 affiliate_type = 'campaign'（活動優惠碼，非真人推廣者）
ALTER TABLE influencers DROP CONSTRAINT IF EXISTS influencers_affiliate_type_check;
ALTER TABLE influencers ADD CONSTRAINT influencers_affiliate_type_check
  CHECK (affiliate_type = ANY (ARRAY['influencer'::text, 'customer_affiliate'::text, 'campaign'::text]));

-- 新欄位的值域約束
ALTER TABLE influencers DROP CONSTRAINT IF EXISTS influencers_discount_base_check;
ALTER TABLE influencers ADD CONSTRAINT influencers_discount_base_check
  CHECK (discount_base = ANY (ARRAY['total'::text, 'base_price'::text]));

ALTER TABLE influencers DROP CONSTRAINT IF EXISTS influencers_driver_payout_mode_check;
ALTER TABLE influencers ADD CONSTRAINT influencers_driver_payout_mode_check
  CHECK (driver_payout_mode = ANY (ARRAY['percent'::text, 'fixed'::text]));

ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_driver_payout_mode_check;
ALTER TABLE bookings ADD CONSTRAINT bookings_driver_payout_mode_check
  CHECK (driver_payout_mode = ANY (ARRAY['percent'::text, 'fixed'::text]));

CREATE OR REPLACE FUNCTION calculate_booking_financials()
RETURNS TRIGGER AS $fn$
DECLARE
  v_revenue_share_settings JSONB;
  v_revenue_config RECORD;
  v_company_percentage DECIMAL(5,2);
  v_driver_percentage DECIMAL(5,2);
  v_has_promo_code BOOLEAN;
  v_lookup_has_promo BOOLEAN;
  v_influencer_commission DECIMAL(10,2);
  v_influencer_record RECORD;
  v_commission_type TEXT;
  v_commission_rate DECIMAL(5,2);
  v_commission_fixed DECIMAL(10,2);
  v_service_type TEXT;
  v_payout_mode TEXT;
  v_discounted_base DECIMAL(10,2);
  v_surcharge DECIMAL(10,2);
BEGIN
  v_has_promo_code := (NEW.promo_code IS NOT NULL AND NEW.promo_code != '');
  v_service_type := COALESCE(NEW.service_type, 'charter');

  -- ==========================================================================
  -- A. 司機給付模式快照（活動單固定給付 / 一般單照比例）
  -- ==========================================================================
  IF TG_OP = 'UPDATE' AND OLD.revenue_share_driver_percentage IS NOT NULL THEN
    NEW.driver_payout_mode  := OLD.driver_payout_mode;
    NEW.driver_fixed_amount := OLD.driver_fixed_amount;
  END IF;
  v_payout_mode := COALESCE(NEW.driver_payout_mode, 'percent');

  -- ==========================================================================
  -- B. 分潤比例
  --    唯一真實來源 = revenue_share_configs（後台「系統設定 → 分成設定」頁）
  --    建單當下寫快照，之後永遠沿用，改設定不會竄改歷史訂單
  -- ==========================================================================
  IF TG_OP = 'UPDATE' AND OLD.revenue_share_driver_percentage IS NOT NULL THEN
    NEW.revenue_share_company_percentage := OLD.revenue_share_company_percentage;
    NEW.revenue_share_driver_percentage  := OLD.revenue_share_driver_percentage;
    NEW.revenue_share_config_id          := OLD.revenue_share_config_id;
    NEW.revenue_share_locked_at          := OLD.revenue_share_locked_at;

    v_company_percentage := OLD.revenue_share_company_percentage;
    v_driver_percentage  := OLD.revenue_share_driver_percentage;
  ELSE
    -- 活動單（固定給付）沒有推廣人抽佣，附加費一律用「未使用優惠碼」的比例，
    -- 否則司機會平白少 5%，而那 5% 沒有任何人領走。
    v_lookup_has_promo := (v_has_promo_code AND v_payout_mode <> 'fixed');

    SELECT * INTO v_revenue_config
    FROM get_revenue_share_config(
      COALESCE(NEW.country, 'TW'), NULL, v_service_type, v_lookup_has_promo
    );

    IF v_revenue_config.driver_percentage IS NOT NULL THEN
      v_company_percentage := v_revenue_config.company_percentage;
      v_driver_percentage  := v_revenue_config.driver_percentage;
      NEW.revenue_share_config_id := v_revenue_config.id;
    ELSE
      NEW.revenue_share_config_id := NULL;
      RAISE WARNING '[Revenue Share] 設定表查無資料，改用 system_settings: country=%, service=%, promo=%',
        NEW.country, v_service_type, v_lookup_has_promo;

      IF v_lookup_has_promo THEN
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
  -- C. 推廣佣金：費率鎖快照，金額隨 total_amount 連動
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
          v_commission_rate := CASE v_service_type
            WHEN 'charter'          THEN COALESCE(v_influencer_record.commission_percent_charter,          v_influencer_record.commission_percent, 0)
            WHEN 'instant_ride'     THEN COALESCE(v_influencer_record.commission_percent_instant_ride,     v_influencer_record.commission_percent, 0)
            WHEN 'airport_transfer' THEN COALESCE(v_influencer_record.commission_percent_airport_transfer, v_influencer_record.commission_percent, 0)
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
  -- D. 金額結算
  -- ==========================================================================
  IF v_payout_mode = 'fixed' THEN
    -- 活動單：基本車資給固定額，其餘（跨區費、超時費等附加費）照比例
    -- 折後基本車資 = base_price - discount_amount
    --   活動碼的折扣只作用在基本車資，故 discount_amount 即基本車資的折讓
    v_discounted_base := GREATEST(COALESCE(NEW.base_price, 0) - COALESCE(NEW.discount_amount, 0), 0);
    v_surcharge       := GREATEST(COALESCE(NEW.total_amount, 0) - v_discounted_base, 0);

    NEW.driver_earning := ROUND((COALESCE(NEW.driver_fixed_amount, 0)
                                 + v_surcharge * v_driver_percentage / 100)::numeric, 2);
    NEW.platform_fee   := ROUND((COALESCE(NEW.total_amount, 0) - NEW.driver_earning)::numeric, 2);
  ELSE
    NEW.driver_earning := ROUND((COALESCE(NEW.total_amount, 0) * v_driver_percentage  / 100)::numeric, 2);
    NEW.platform_fee   := ROUND((COALESCE(NEW.total_amount, 0) * v_company_percentage / 100)::numeric, 2);
  END IF;

  -- 推廣佣金從公司那一份內扣，司機不受影響
  IF v_influencer_commission > 0 AND v_has_promo_code THEN
    NEW.platform_fee := NEW.platform_fee - v_influencer_commission;
  END IF;

  -- 保險絲：固定給付設得太高會讓平台倒貼，直接擋下而不是默默虧錢
  IF v_payout_mode = 'fixed' AND NEW.platform_fee < 0 THEN
    RAISE EXCEPTION '[分潤] 活動單平台留存為負數（總額 %, 司機 %, 平台 %），請調低司機固定給付額',
      NEW.total_amount, NEW.driver_earning, NEW.platform_fee;
  END IF;

  IF NEW.status = 'completed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'completed') THEN
    NEW.completed_at := NOW();
  END IF;

  IF NEW.actual_end_time IS NOT NULL AND NEW.completed_at IS NULL THEN
    NEW.completed_at := NEW.actual_end_time;
  END IF;

  RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;

-- 建立本次活動碼（預設未啟用，確認前端就緒後再開啟）
INSERT INTO influencers (
  name, promo_code, affiliate_type, affiliate_status, is_active,
  account_username, account_password,
  discount_amount_enabled, discount_amount,
  discount_percentage_enabled, discount_type,
  discount_percentage, discount_percent_charter,
  discount_percent_instant_ride, discount_percent_airport_transfer,
  is_commission_fixed_active, is_commission_percent_active,
  commission_fixed, commission_percent,
  limit_vehicle_types, limit_service_types, discount_base,
  driver_payout_mode, driver_fixed_amount, per_user_limit,
  valid_from, valid_until
) VALUES (
  'RG202609 九人座七折活動', 'RG202609', 'campaign', 'active', false,
  'campaign_RG202609', 'NO_LOGIN_CAMPAIGN',
  false, 0,
  true, 'by_service_type',
  0, 30,
  0, 0,
  false, false,
  0, 0,
  ARRAY['L'], ARRAY['charter'], 'base_price',
  'fixed', 4000, 1,
  NULL, NULL
)
ON CONFLICT DO NOTHING;

SELECT id, name, promo_code, affiliate_type, is_active,
       discount_percent_charter, limit_vehicle_types, limit_service_types,
       discount_base, driver_payout_mode, driver_fixed_amount, per_user_limit,
       is_commission_percent_active, is_commission_fixed_active,
       valid_from, valid_until
FROM influencers WHERE promo_code = 'RG202609';
