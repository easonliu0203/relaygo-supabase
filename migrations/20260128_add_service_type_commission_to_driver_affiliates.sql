-- ============================================================
-- Migration: 為司機推廣人分潤系統新增服務類型維度
-- Date: 2026-01-28
-- Description: 
--   1. 新增 commission_percent_charter（包車旅遊分潤百分比）
--   2. 新增 commission_percent_instant_ride（即時派車分潤百分比）
--   3. 在 bookings 表新增司機推薦人分潤快照欄位
--   4. 更新 calculate_driver_referral_commission 觸發器以支援服務類型維度分潤
-- ============================================================

-- ============================================================
-- 1. 新增欄位到 driver_affiliates 表
-- ============================================================

-- 新增包車旅遊分潤百分比欄位
ALTER TABLE driver_affiliates
ADD COLUMN IF NOT EXISTS commission_percent_charter DOUBLE PRECISION DEFAULT NULL;

-- 新增即時派車分潤百分比欄位
ALTER TABLE driver_affiliates
ADD COLUMN IF NOT EXISTS commission_percent_instant_ride DOUBLE PRECISION DEFAULT NULL;

-- 新增欄位註解
COMMENT ON COLUMN driver_affiliates.commission_percent_charter IS '包車旅遊服務的分潤百分比';
COMMENT ON COLUMN driver_affiliates.commission_percent_instant_ride IS '即時派車服務的分潤百分比';

-- ============================================================
-- 2. 在 bookings 表新增司機推薦人分潤快照欄位
-- ============================================================

-- 司機推薦人分潤百分比快照（訂單創建時的設定）
ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS driver_referral_commission_rate DOUBLE PRECISION DEFAULT 0;

-- 司機推薦人分潤類型快照（fixed 或 percent）
ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS driver_referral_commission_type TEXT DEFAULT NULL;

-- 欄位註解
COMMENT ON COLUMN bookings.driver_referral_commission_rate IS '司機推薦人分潤百分比快照（訂單創建時的設定）';
COMMENT ON COLUMN bookings.driver_referral_commission_type IS '司機推薦人分潤類型快照（fixed 或 percent）';

-- ============================================================
-- 3. 更新 calculate_driver_referral_commission 觸發器函數
-- ============================================================

CREATE OR REPLACE FUNCTION calculate_driver_referral_commission()
RETURNS TRIGGER AS $function$
DECLARE
  v_referral RECORD;
  v_affiliate RECORD;
  v_commission_amount DOUBLE PRECISION;
  v_commission_rate DOUBLE PRECISION;
  v_commission_type TEXT;
  v_order_amount DOUBLE PRECISION;
  v_service_type TEXT;
BEGIN
  -- 只在訂單狀態變更為 'completed' 時執行
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN

    RAISE NOTICE '[Driver Referral] 訂單完成，開始計算司機推薦人分潤: booking_id=%, driver_id=%', NEW.id, NEW.driver_id;

    -- 獲取訂單金額（使用 platform_fee 作為基準，因為分潤從公司抽成中扣除）
    v_order_amount := COALESCE(NEW.platform_fee, 0);
    v_service_type := COALESCE(NEW.service_type, 'charter');

    -- 查詢完成訂單的司機是否有推薦人
    SELECT * INTO v_referral
    FROM driver_referrals
    WHERE referee_driver_id = NEW.driver_id
    LIMIT 1;

    IF v_referral IS NOT NULL THEN
      RAISE NOTICE '[Driver Referral] 找到推薦關係: referrer_driver_id=%, promo_code=%',
        v_referral.referrer_driver_id, v_referral.promo_code;

      -- 查詢推薦人的分潤設定
      SELECT * INTO v_affiliate
      FROM driver_affiliates
      WHERE driver_id = v_referral.referrer_driver_id
        AND affiliate_status = 'active'
        AND is_active = TRUE
      LIMIT 1;

      IF v_affiliate IS NOT NULL THEN
        -- 計算分潤金額
        IF v_affiliate.commission_fixed_enabled = TRUE AND v_affiliate.commission_fixed > 0 THEN
          -- 優先使用固定金額
          v_commission_amount := v_affiliate.commission_fixed;
          v_commission_type := 'fixed';
          v_commission_rate := 0;
          RAISE NOTICE '[Driver Referral] 使用固定金額分潤: %', v_commission_amount;
        ELSIF v_affiliate.commission_percent_enabled = TRUE THEN
          -- 使用百分比（根據服務類型選擇對應的百分比）
          v_commission_type := 'percent';
          
          -- ✅ 新增：根據服務類型選擇對應的分潤百分比
          IF v_service_type = 'charter' AND v_affiliate.commission_percent_charter IS NOT NULL THEN
            v_commission_rate := v_affiliate.commission_percent_charter;
            RAISE NOTICE '[Driver Referral] 使用包車旅遊專屬百分比: %', v_commission_rate;
          ELSIF v_service_type = 'instant_ride' AND v_affiliate.commission_percent_instant_ride IS NOT NULL THEN
            v_commission_rate := v_affiliate.commission_percent_instant_ride;
            RAISE NOTICE '[Driver Referral] 使用即時派車專屬百分比: %', v_commission_rate;
          ELSE
            -- 回退到統一百分比
            v_commission_rate := COALESCE(v_affiliate.commission_percent, 0);
            RAISE NOTICE '[Driver Referral] 使用統一百分比: %', v_commission_rate;
          END IF;
          
          v_commission_amount := ROUND((v_order_amount * v_commission_rate / 100)::numeric, 2);
          RAISE NOTICE '[Driver Referral] 百分比分潤計算: % %% of % = %',
            v_commission_rate, v_order_amount, v_commission_amount;
        ELSE
          v_commission_amount := 0;
          v_commission_type := NULL;
          v_commission_rate := 0;
          RAISE NOTICE '[Driver Referral] 推薦人未啟用任何分潤設定';
        END IF;

        -- 確保分潤金額不超過公司抽成
        IF v_commission_amount > v_order_amount THEN
          v_commission_amount := v_order_amount;
          RAISE NOTICE '[Driver Referral] 分潤金額超過公司抽成，調整為: %', v_commission_amount;
        END IF;

        -- 更新訂單的司機推薦人分潤快照
        NEW.driver_referral_commission := v_commission_amount;
        NEW.driver_referrer_id := v_referral.referrer_driver_id;
        NEW.driver_referral_commission_rate := v_commission_rate;
        NEW.driver_referral_commission_type := v_commission_type;

        -- 從公司抽成中扣除分潤
        NEW.platform_fee := NEW.platform_fee - v_commission_amount;

        -- 更新推薦人的累計收入
        UPDATE driver_affiliates
        SET total_earnings = total_earnings + v_commission_amount,
            updated_at = NOW()
        WHERE driver_id = v_referral.referrer_driver_id;

        RAISE NOTICE '[Driver Referral] ✅ 分潤計算完成: commission=%, rate=%, type=%, 新 platform_fee=%',
          v_commission_amount, v_commission_rate, v_commission_type, NEW.platform_fee;
      ELSE
        RAISE NOTICE '[Driver Referral] ⚠️ 推薦人不是活躍狀態或未啟用';
        NEW.driver_referral_commission := 0;
        NEW.driver_referrer_id := NULL;
        NEW.driver_referral_commission_rate := 0;
        NEW.driver_referral_commission_type := NULL;
      END IF;
    ELSE
      RAISE NOTICE '[Driver Referral] 該司機沒有推薦人';
      NEW.driver_referral_commission := 0;
      NEW.driver_referrer_id := NULL;
      NEW.driver_referral_commission_rate := 0;
      NEW.driver_referral_commission_type := NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$ LANGUAGE plpgsql;

-- 確認觸發器存在
DROP TRIGGER IF EXISTS calculate_driver_referral_commission_trigger ON bookings;
CREATE TRIGGER calculate_driver_referral_commission_trigger
BEFORE INSERT OR UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION calculate_driver_referral_commission();

-- ============================================================
-- 完成
-- ============================================================

