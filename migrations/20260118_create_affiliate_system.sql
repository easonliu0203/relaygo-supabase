-- ============================================
-- 客戶推廣人（Affiliate）系統資料庫 Migration
-- ============================================
-- 創建日期: 2026-01-18
-- 用途: 建立客戶推廣人系統，支援推薦關係和分潤功能
-- 策略: 整合現有 influencers 系統，避免資料重複
-- ============================================

-- ============================================
-- 第一部分：擴展 influencers 表
-- ============================================

-- 新增推廣人類型欄位
ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS affiliate_type TEXT CHECK (affiliate_type IN ('influencer', 'customer_affiliate')) DEFAULT 'influencer';

-- 新增推廣人狀態欄位（用於客戶申請審核）
ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS affiliate_status TEXT CHECK (affiliate_status IN ('pending', 'active', 'suspended', 'rejected')) DEFAULT 'active';

-- 新增關聯用戶 ID（用於客戶推廣人）
ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE CASCADE;

-- 新增分潤設定欄位
ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS commission_fixed DECIMAL(10,2) DEFAULT 0;

ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS commission_percent FLOAT DEFAULT 5.0;

ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS is_commission_fixed_active BOOLEAN DEFAULT FALSE;

ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS is_commission_percent_active BOOLEAN DEFAULT TRUE;

-- 新增統計欄位
ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS total_referrals INTEGER DEFAULT 0;

ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS total_earnings DECIMAL(10,2) DEFAULT 0;

-- 新增申請日期欄位
ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS applied_at TIMESTAMPTZ;

-- 新增審核相關欄位
ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES users(id);

ALTER TABLE influencers 
ADD COLUMN IF NOT EXISTS review_notes TEXT;

-- 建立索引
CREATE INDEX IF NOT EXISTS idx_influencers_user_id ON influencers(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_influencers_affiliate_type ON influencers(affiliate_type);
CREATE INDEX IF NOT EXISTS idx_influencers_affiliate_status ON influencers(affiliate_status);

-- 新增註解
COMMENT ON COLUMN influencers.affiliate_type IS '推廣人類型：influencer（網紅）或 customer_affiliate（客戶推廣人）';
COMMENT ON COLUMN influencers.affiliate_status IS '推廣人狀態：pending（待審核）、active（已啟用）、suspended（已暫停）、rejected（已拒絕）';
COMMENT ON COLUMN influencers.user_id IS '關聯的用戶 ID（僅用於客戶推廣人）';
COMMENT ON COLUMN influencers.commission_fixed IS '固定金額分潤';
COMMENT ON COLUMN influencers.commission_percent IS '百分比分潤（預設 5%）';
COMMENT ON COLUMN influencers.is_commission_fixed_active IS '是否啟用固定金額分潤';
COMMENT ON COLUMN influencers.is_commission_percent_active IS '是否啟用百分比分潤';
COMMENT ON COLUMN influencers.total_referrals IS '累積推薦人數';
COMMENT ON COLUMN influencers.total_earnings IS '累積收益金額';

-- ============================================
-- 第二部分：創建 referrals 表（推薦關係表）
-- ============================================

CREATE TABLE IF NOT EXISTS referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  referee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  influencer_id UUID NOT NULL REFERENCES influencers(id) ON DELETE CASCADE,
  promo_code TEXT NOT NULL,
  first_booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  -- 確保每個用戶只能有一個推薦人
  UNIQUE(referee_id),
  
  -- 防止自我推薦
  CHECK (referrer_id != referee_id)
);

-- 建立索引
CREATE INDEX IF NOT EXISTS idx_referrals_referrer_id ON referrals(referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referee_id ON referrals(referee_id);
CREATE INDEX IF NOT EXISTS idx_referrals_influencer_id ON referrals(influencer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_promo_code ON referrals(promo_code);

-- 新增註解
COMMENT ON TABLE referrals IS '推薦關係表：記錄用戶之間的推薦關係（終身綁定）';
COMMENT ON COLUMN referrals.referrer_id IS '推薦人用戶 ID';
COMMENT ON COLUMN referrals.referee_id IS '被推薦人用戶 ID';
COMMENT ON COLUMN referrals.influencer_id IS '推廣人 ID（influencers 表）';
COMMENT ON COLUMN referrals.promo_code IS '使用的推薦碼';
COMMENT ON COLUMN referrals.first_booking_id IS '首次使用推薦碼的訂單 ID';

-- ============================================
-- 第三部分：擴展 promo_code_usage 表
-- ============================================

-- 新增被推薦人 ID
ALTER TABLE promo_code_usage 
ADD COLUMN IF NOT EXISTS referee_id UUID REFERENCES users(id) ON DELETE CASCADE;

-- 新增分潤狀態
ALTER TABLE promo_code_usage 
ADD COLUMN IF NOT EXISTS commission_status TEXT CHECK (commission_status IN ('pending', 'paid', 'cancelled')) DEFAULT 'pending';

-- 新增分潤類型
ALTER TABLE promo_code_usage 
ADD COLUMN IF NOT EXISTS commission_type TEXT CHECK (commission_type IN ('fixed', 'percent'));

-- 新增分潤比率（百分比時使用）
ALTER TABLE promo_code_usage 
ADD COLUMN IF NOT EXISTS commission_rate FLOAT;

-- 新增訂單金額
ALTER TABLE promo_code_usage 
ADD COLUMN IF NOT EXISTS order_amount DECIMAL(10,2);

-- 建立索引
CREATE INDEX IF NOT EXISTS idx_promo_code_usage_referee_id ON promo_code_usage(referee_id) WHERE referee_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_promo_code_usage_commission_status ON promo_code_usage(commission_status);

-- 新增註解
COMMENT ON COLUMN promo_code_usage.referee_id IS '被推薦人用戶 ID';
COMMENT ON COLUMN promo_code_usage.commission_status IS '分潤狀態：pending（待發放）、paid（已發放）、cancelled（已取消）';
COMMENT ON COLUMN promo_code_usage.commission_type IS '分潤類型：fixed（固定金額）或 percent（百分比）';
COMMENT ON COLUMN promo_code_usage.commission_rate IS '分潤比率（百分比時使用）';
COMMENT ON COLUMN promo_code_usage.order_amount IS '訂單金額';

-- ============================================
-- 第四部分：創建觸發器和函數
-- ============================================

-- 函數：更新推廣人統計資料
CREATE OR REPLACE FUNCTION update_influencer_stats()
RETURNS TRIGGER AS $$
BEGIN
  -- 更新推薦人數
  UPDATE influencers
  SET total_referrals = (
    SELECT COUNT(*) FROM referrals WHERE influencer_id = NEW.influencer_id
  )
  WHERE id = NEW.influencer_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 觸發器：當新增推薦關係時更新統計
DROP TRIGGER IF EXISTS trigger_update_referral_stats ON referrals;
CREATE TRIGGER trigger_update_referral_stats
AFTER INSERT ON referrals
FOR EACH ROW
EXECUTE FUNCTION update_influencer_stats();

-- ============================================
-- 完成
-- ============================================

-- 輸出完成訊息
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ 客戶推廣人系統資料庫 Migration 完成！';
  RAISE NOTICE '========================================';
  RAISE NOTICE '已完成的操作：';
  RAISE NOTICE '1. ✅ 擴展 influencers 表（新增推廣人相關欄位）';
  RAISE NOTICE '2. ✅ 創建 referrals 表（推薦關係）';
  RAISE NOTICE '3. ✅ 擴展 promo_code_usage 表（新增分潤欄位）';
  RAISE NOTICE '4. ✅ 創建觸發器（自動更新統計）';
  RAISE NOTICE '========================================';
END $$;

