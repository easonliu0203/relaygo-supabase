-- ============================================================================
-- 客戶推廣人：首單分潤反轉
-- 日期：2026-09-11（皆已套用至線上）
--
-- 規則
--   推廣單的 30% 裡，平常公司 25%／推廣人 5%（依推廣人自己的設定）。
--   客人「第一張完成」的客戶推廣人訂單，改為推廣人拿首單％（預設 25%，
--   可在後台分成設定頁調整），公司剩 5%。司機一律 70%。
--   - 訂單完成才算用過：取消的單不佔首單資格
--   - 推廣人設固定金額分潤時，首單仍改用首單％
--   - 網紅碼、活動碼不參與（first_use_promoter_percentage 為 NULL）
--   - 推廣人用自己的帳號下單，不會產生推薦關係，算一般分潤
--
-- 作法
--   首單判定以 referrals.referee_id 的唯一約束在「訂單完成」時原子搶佔：
--   兩張同時進行的單，只有先完成的那張算首單。推薦關係也改在此時建立
--   （原本建單就建立，客人取消後首單資格就被佔掉）。
--   首單％於建單時鎖進訂單快照，判定結果（first_use／repeat）於完成時鎖定。
--
--   另統一兩套分潤機制：calculate_affiliate_commission 原本依「客人當初第一次
--   用誰的碼」另外重算並把累計收入記給那個人，客人改用別人的碼時同一筆分潤
--   會記給兩個推廣人。改為只記錄訂單本身（bookings.influencer_commission）的結果。
-- ============================================================================

-- ============================================================================
-- 客戶推廣人：首單分潤反轉 — 步驟 1：設定欄位與訂單快照欄位
-- ============================================================================

-- 1. 分成設定：首單推廣人％（只用在「使用優惠碼」的列）
ALTER TABLE revenue_share_configs
  ADD COLUMN IF NOT EXISTS first_use_promoter_percentage NUMERIC(5,2);

COMMENT ON COLUMN revenue_share_configs.first_use_promoter_percentage IS
  '客戶推廣人首單分潤％：客人第一張「完成」的客戶推廣人訂單，推廣人改拿此比例（取代推廣人自己的分潤設定）。只用在 has_promo_code=true 的列，不可超過公司抽成。';

UPDATE revenue_share_configs
SET first_use_promoter_percentage = 25
WHERE has_promo_code = true AND first_use_promoter_percentage IS NULL;

-- 不可超過公司那一份，否則公司留存變負數
ALTER TABLE revenue_share_configs DROP CONSTRAINT IF EXISTS revenue_share_configs_first_use_check;
ALTER TABLE revenue_share_configs ADD CONSTRAINT revenue_share_configs_first_use_check
  CHECK (
    first_use_promoter_percentage IS NULL
    OR (first_use_promoter_percentage >= 0
        AND first_use_promoter_percentage <= COALESCE(company_base_percentage, company_percentage))
  );

-- 2. 訂單快照
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS first_use_promoter_percentage NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS influencer_commission_reason  VARCHAR(20);

COMMENT ON COLUMN bookings.first_use_promoter_percentage IS
  '建單當下的首單推廣人％快照。只有使用客戶推廣人的碼才有值（網紅碼、活動碼為 NULL，不參與首單規則）。';
COMMENT ON COLUMN bookings.influencer_commission_reason IS
  '分潤原因：first_use=客人第一張完成的客戶推廣人訂單；repeat=一般推薦分潤；NULL=訂單尚未完成或不適用。訂單完成時決定並鎖定。';

ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_commission_reason_check;
ALTER TABLE bookings ADD CONSTRAINT bookings_commission_reason_check
  CHECK (influencer_commission_reason IS NULL OR influencer_commission_reason IN ('first_use', 'repeat'));

SELECT service_type, has_promo_code, company_percentage, company_base_percentage, first_use_promoter_percentage
FROM revenue_share_configs ORDER BY service_type, has_promo_code;

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
  v_tip_fee_pct DECIMAL(5,2);
  v_tip_after_fee DECIMAL(10,2);
  v_first_use_pct DECIMAL(5,2);
  v_influencer_affiliate_type TEXT;
  v_claimed INT;
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


    -- ── 客戶推廣人首單規則 ──────────────────────────────────────────────────
    -- 客人第一張「完成」的客戶推廣人訂單，推廣人改拿首單％（取代推廣人自己的
    -- 固定金額或百分比設定）；之後的訂單照推廣人自己的設定。
    -- 網紅碼、活動碼不參與：first_use_promoter_percentage 為 NULL。

    -- (a) 首單％快照：建單當下決定是否適用，之後永不變動
    IF TG_OP = 'UPDATE' THEN
      NEW.first_use_promoter_percentage := OLD.first_use_promoter_percentage;
    ELSE
      SELECT affiliate_type INTO v_influencer_affiliate_type
      FROM influencers WHERE id = NEW.influencer_id;

      IF v_influencer_affiliate_type = 'customer_affiliate' THEN
        SELECT first_use_promoter_percentage INTO v_first_use_pct
        FROM revenue_share_configs WHERE id = NEW.revenue_share_config_id;
        NEW.first_use_promoter_percentage := COALESCE(v_first_use_pct, 25);
      ELSE
        NEW.first_use_promoter_percentage := NULL;
      END IF;
    END IF;

    -- (b) 是否為首單：訂單「完成」的那一刻決定並鎖定
    IF NEW.first_use_promoter_percentage IS NOT NULL THEN
      IF TG_OP = 'UPDATE' AND OLD.status = 'completed' THEN
        -- 已完成的訂單：沿用當時的判定（費率也已在 OLD 快照中）
        NEW.influencer_commission_reason := OLD.influencer_commission_reason;

      ELSIF TG_OP = 'UPDATE' AND NEW.status = 'completed' THEN
        -- 用 referrals.referee_id 的唯一約束做原子搶佔：
        -- 客人第一張完成的客戶推廣人訂單才會搶到，兩張同時完成也只有一張算首單。
        -- 推廣人用自己的帳號下單時 user_id = customer_id，不會產生推薦關係，
        -- 自然算一般分潤（也避開 referrer ≠ referee 的約束錯誤）。
        INSERT INTO referrals (referrer_id, referee_id, influencer_id, promo_code, first_booking_id)
        SELECT i.user_id, NEW.customer_id, NEW.influencer_id, NEW.promo_code, NEW.id
        FROM influencers i
        WHERE i.id = NEW.influencer_id
          AND i.user_id IS NOT NULL
          AND i.user_id <> NEW.customer_id
        ON CONFLICT (referee_id) DO NOTHING;
        GET DIAGNOSTICS v_claimed = ROW_COUNT;

        IF v_claimed = 1 OR EXISTS (
             SELECT 1 FROM referrals
             WHERE referee_id = NEW.customer_id AND first_booking_id = NEW.id) THEN
          NEW.influencer_commission_reason := 'first_use';
        ELSE
          NEW.influencer_commission_reason := 'repeat';
        END IF;

        -- 首單：一律改用首單％
        IF NEW.influencer_commission_reason = 'first_use' THEN
          v_commission_type  := 'percent';
          v_commission_rate  := NEW.first_use_promoter_percentage;
          v_commission_fixed := 0;
        END IF;

      ELSE
        -- 尚未完成：不判定（App 端依此顯示「待確認」）
        NEW.influencer_commission_reason := NULL;
      END IF;
    ELSE
      NEW.influencer_commission_reason := NULL;
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
    NEW.influencer_commission_reason := NULL;
    NEW.first_use_promoter_percentage := NULL;
    v_influencer_commission := 0;
  END IF;

  -- ==========================================================================
  -- D. 小費
  --    平台完全不抽小費；司機拿扣除金流手續費後的淨額。
  --    費率來自 system_settings.tip_payment_fee，記錄小費當下鎖進訂單快照，
  --    之後調整設定不影響已成立的訂單。
  --    現金小費不經金流，由後端寫入費率 0。
  -- ==========================================================================
  IF TG_OP = 'UPDATE' AND OLD.tip_fee_percentage IS NOT NULL THEN
    -- 已鎖定，永不變動
    NEW.tip_fee_percentage := OLD.tip_fee_percentage;
  ELSIF NEW.tip_fee_percentage IS NULL AND COALESCE(NEW.tip_amount, 0) > 0 THEN
    -- 後端未指定費率時，取當下設定值並鎖定
    SELECT COALESCE((value->>'percent')::DECIMAL, 3)
    INTO v_tip_fee_pct
    FROM system_settings WHERE key = 'tip_payment_fee' LIMIT 1;
    NEW.tip_fee_percentage := COALESCE(v_tip_fee_pct, 3);
  END IF;

  v_tip_after_fee := ROUND((COALESCE(NEW.tip_amount, 0)
                            * (1 - COALESCE(NEW.tip_fee_percentage, 0) / 100))::numeric, 2);
  NEW.tip_after_fee := v_tip_after_fee;

  -- ==========================================================================
  -- E. 金額結算
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
    NEW.driver_earning := NEW.driver_earning + v_tip_after_fee;
  ELSE
    NEW.driver_earning := ROUND((COALESCE(NEW.total_amount, 0) * v_driver_percentage  / 100)::numeric, 2)
                          + v_tip_after_fee;
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

CREATE OR REPLACE FUNCTION calculate_affiliate_commission()
RETURNS TRIGGER AS $fn$
DECLARE
  v_existing_status TEXT;
BEGIN
  -- 只在訂單「變成已完成」的那一次處理
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status <> 'completed') THEN
    IF NEW.influencer_id IS NULL THEN
      RETURN NEW;
    END IF;

    -- ✅ 統一分潤來源：一律採用 calculate_booking_financials 算好的結果
    --    （bookings.influencer_commission，已含首單判定）。
    --    原本這裡會依「客人當初第一次用誰的碼」另外重算並把累計收入記給那個人，
    --    客人改用別人的碼時，同一筆分潤會同時記給兩個推廣人。
    SELECT commission_status INTO v_existing_status
    FROM promo_code_usage WHERE booking_id = NEW.id;

    UPDATE promo_code_usage
    SET commission_status = 'completed',
        influencer_id     = NEW.influencer_id,
        commission_type   = NEW.influencer_commission_type,
        commission_rate   = NEW.influencer_commission_rate,
        commission_amount = NEW.influencer_commission,
        order_amount      = NEW.total_amount,
        referee_id        = NEW.customer_id
    WHERE booking_id = NEW.id;

    -- 累計收入記給「這張單」的推廣人；已記過就不重複累加
    IF v_existing_status IS DISTINCT FROM 'completed' THEN
      UPDATE influencers
      SET total_earnings = COALESCE(total_earnings, 0) + COALESCE(NEW.influencer_commission, 0)
      WHERE id = NEW.influencer_id;
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- 分潤記帳失敗不可阻擋訂單完成（沿用原本的保護），但要留下警告
    RAISE WARNING '[calculate_affiliate_commission] booking % 分潤記錄失敗: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;
