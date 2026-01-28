-- ============================================================
-- Migration: 建立司機推廣人系統（Driver Affiliate System）
-- Date: 2026-01-28
-- Description:
--   1. 建立 driver_affiliates 表（司機推廣人資料）
--   2. 建立 driver_referrals 表（司機推薦關係）
--   3. 在 bookings 表新增司機推薦人分潤欄位
--   4. 建立觸發器：訂單完成時自動計算司機推薦人分潤
-- ============================================================

-- ============================================================
-- 1. 建立 driver_affiliates 表（司機推廣人資料）
-- ============================================================

CREATE TABLE IF NOT EXISTS driver_affiliates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  promo_code TEXT NOT NULL,
  affiliate_status TEXT NOT NULL DEFAULT 'pending',

  -- 固定金額分潤設定
  commission_fixed_enabled BOOLEAN DEFAULT FALSE,
  commission_fixed DOUBLE PRECISION DEFAULT 0,

  -- 百分比分潤設定
  commission_percent_enabled BOOLEAN DEFAULT FALSE,
  commission_percent DOUBLE PRECISION DEFAULT 1.0,

  -- 統計欄位
  total_referrals INTEGER DEFAULT 0,
  total_earnings DOUBLE PRECISION DEFAULT 0,

  -- 狀態控制
  is_active BOOLEAN DEFAULT FALSE,

  -- 時間欄位
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- 審核相關
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  review_notes TEXT,

  -- 約束
  UNIQUE(driver_id),
  UNIQUE(promo_code),
  CONSTRAINT check_affiliate_status CHECK (affiliate_status IN ('pending', 'active', 'suspended', 'rejected'))
);

-- 建立索引
CREATE INDEX IF NOT EXISTS idx_driver_affiliates_promo_code ON driver_affiliates(promo_code);
CREATE INDEX IF NOT EXISTS idx_driver_affiliates_driver_id ON driver_affiliates(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_affiliates_status ON driver_affiliates(affiliate_status);

-- 表註解
COMMENT ON TABLE driver_affiliates IS '司機推廣人資料表';
COMMENT ON COLUMN driver_affiliates.driver_id IS '司機的 user_id';
COMMENT ON COLUMN driver_affiliates.promo_code IS '推薦碼（唯一）';
COMMENT ON COLUMN driver_affiliates.affiliate_status IS '狀態：pending/active/suspended/rejected';
COMMENT ON COLUMN driver_affiliates.commission_fixed_enabled IS '是否啟用固定金額分潤';
COMMENT ON COLUMN driver_affiliates.commission_fixed IS '固定分潤金額（NT$）';
COMMENT ON COLUMN driver_affiliates.commission_percent_enabled IS '是否啟用百分比分潤';
COMMENT ON COLUMN driver_affiliates.commission_percent IS '分潤百分比（從公司抽成中扣除）';
COMMENT ON COLUMN driver_affiliates.total_referrals IS '推薦司機總數';
COMMENT ON COLUMN driver_affiliates.total_earnings IS '累計收入';

-- ============================================================
-- 2. 建立 driver_referrals 表（司機推薦關係）
-- ============================================================

CREATE TABLE IF NOT EXISTS driver_referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_driver_id UUID NOT NULL REFERENCES driver_affiliates(driver_id) ON DELETE CASCADE,
  referee_driver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  promo_code TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- 確保每個司機只能有一個推薦人（終身綁定）
  UNIQUE(referee_driver_id),

  -- 防止自我推薦
  CHECK (referrer_driver_id != referee_driver_id)
);

-- 建立索引
CREATE INDEX IF NOT EXISTS idx_driver_referrals_referrer ON driver_referrals(referrer_driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_referrals_referee ON driver_referrals(referee_driver_id);

-- 表註解
COMMENT ON TABLE driver_referrals IS '司機推薦關係表（終身綁定）';
COMMENT ON COLUMN driver_referrals.referrer_driver_id IS '推薦人司機的 user_id';
COMMENT ON COLUMN driver_referrals.referee_driver_id IS '被推薦司機的 user_id';
COMMENT ON COLUMN driver_referrals.promo_code IS '使用的推薦碼';

-- ============================================================
-- 3. 在 bookings 表新增司機推薦人分潤欄位
-- ============================================================

-- 司機推薦人分潤金額（快照值）
ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS driver_referral_commission DOUBLE PRECISION DEFAULT 0;

-- 推薦人司機 ID（快照值）
ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS driver_referrer_id UUID REFERENCES users(id) ON DELETE SET NULL;

-- 欄位註解

-- ============================================================
-- 4. 建立觸發器：訂單完成時自動計算司機推薦人分潤
-- ============================================================

CREATE OR REPLACE FUNCTION calculate_driver_referral_commission()
RETURNS TRIGGER AS $function$
DECLARE
  v_referral RECORD;
  v_affiliate RECORD;
  v_commission_amount DOUBLE PRECISION;
  v_order_amount DOUBLE PRECISION;
BEGIN
  -- 只在訂單狀態變更為 'completed' 時執行
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN

    RAISE NOTICE '[Driver Referral] 訂單完成，開始計算司機推薦人分潤: booking_id=%, driver_id=%', NEW.id, NEW.driver_id;

    -- 獲取訂單金額（使用 platform_fee 作為基準，因為分潤從公司抽成中扣除）
    v_order_amount := COALESCE(NEW.platform_fee, 0);

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
          RAISE NOTICE '[Driver Referral] 使用固定金額分潤: %', v_commission_amount;
        ELSIF v_affiliate.commission_percent_enabled = TRUE AND v_affiliate.commission_percent > 0 THEN
          -- 使用百分比（基於公司抽成）
          v_commission_amount := ROUND((v_order_amount * v_affiliate.commission_percent / 100)::numeric, 2);
          RAISE NOTICE '[Driver Referral] 使用百分比分潤: % %% of % = %',
            v_affiliate.commission_percent, v_order_amount, v_commission_amount;
        ELSE
          v_commission_amount := 0;
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

        -- 從公司抽成中扣除分潤
        NEW.platform_fee := NEW.platform_fee - v_commission_amount;

        -- 更新推薦人的累計收入
        UPDATE driver_affiliates
        SET total_earnings = total_earnings + v_commission_amount,
            updated_at = NOW()
        WHERE driver_id = v_referral.referrer_driver_id;

        RAISE NOTICE '[Driver Referral] ✅ 分潤計算完成: commission=%, 新 platform_fee=%',
          v_commission_amount, NEW.platform_fee;
      ELSE
        RAISE NOTICE '[Driver Referral] ⚠️ 推薦人不是活躍狀態或未啟用';
        NEW.driver_referral_commission := 0;
        NEW.driver_referrer_id := NULL;
      END IF;
    ELSE
      RAISE NOTICE '[Driver Referral] 該司機沒有推薦人';
      NEW.driver_referral_commission := 0;
      NEW.driver_referrer_id := NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$ LANGUAGE plpgsql;

-- 建立觸發器（在 calculate_booking_financials 之後執行）
DROP TRIGGER IF EXISTS calculate_driver_referral_commission_trigger ON bookings;
CREATE TRIGGER calculate_driver_referral_commission_trigger
BEFORE INSERT OR UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION calculate_driver_referral_commission();

-- ============================================================
-- 5. 建立自動更新 updated_at 的觸發器
-- ============================================================

CREATE OR REPLACE FUNCTION update_driver_affiliates_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_driver_affiliates_timestamp ON driver_affiliates;
CREATE TRIGGER update_driver_affiliates_timestamp
BEFORE UPDATE ON driver_affiliates
FOR EACH ROW
EXECUTE FUNCTION update_driver_affiliates_updated_at();

-- ============================================================
-- 6. 建立更新推薦人統計的觸發器
-- ============================================================

CREATE OR REPLACE FUNCTION update_driver_affiliate_referral_count()
RETURNS TRIGGER AS $$
BEGIN
  -- 新增推薦關係時，增加推薦人的 total_referrals
  IF TG_OP = 'INSERT' THEN
    UPDATE driver_affiliates
    SET total_referrals = total_referrals + 1,
        updated_at = NOW()
    WHERE driver_id = NEW.referrer_driver_id;
    RETURN NEW;
  -- 刪除推薦關係時，減少推薦人的 total_referrals
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE driver_affiliates
    SET total_referrals = GREATEST(0, total_referrals - 1),
        updated_at = NOW()
    WHERE driver_id = OLD.referrer_driver_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_driver_affiliate_referral_count_trigger ON driver_referrals;
CREATE TRIGGER update_driver_affiliate_referral_count_trigger
AFTER INSERT OR DELETE ON driver_referrals
FOR EACH ROW
EXECUTE FUNCTION update_driver_affiliate_referral_count();

-- ============================================================
-- 完成
-- ============================================================

COMMENT ON COLUMN bookings.driver_referral_commission IS '司機推薦人分潤金額（訂單完成時的快照值）';
COMMENT ON COLUMN bookings.driver_referrer_id IS '推薦人司機的 user_id（訂單完成時的快照值）';

