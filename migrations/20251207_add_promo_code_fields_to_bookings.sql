-- ============================================
-- 添加優惠碼相關欄位到 bookings 表
-- ============================================
-- 創建日期: 2025-12-07
-- 用途: 添加優惠碼折扣資訊欄位，支援優惠碼功能
-- ============================================

-- 1. 添加 promo_code 欄位（優惠碼）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS promo_code VARCHAR(50);

-- 2. 添加 influencer_id 欄位（網紅 ID）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS influencer_id UUID;

-- 3. 添加 influencer_commission 欄位（網紅推廣獎金）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS influencer_commission DECIMAL(10, 2) DEFAULT 0;

-- 4. 添加 original_price 欄位（原始價格，未折扣前）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS original_price DECIMAL(10, 2);

-- 5. 添加 discount_amount 欄位（折扣金額）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS discount_amount DECIMAL(10, 2) DEFAULT 0;

-- 6. 添加 final_price 欄位（折扣後最終價格）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS final_price DECIMAL(10, 2);

-- 7. 添加外鍵約束（關聯到 influencers 表）
ALTER TABLE bookings 
ADD CONSTRAINT fk_influencer 
FOREIGN KEY (influencer_id) 
REFERENCES influencers(id) 
ON DELETE SET NULL;

-- 8. 添加註釋
COMMENT ON COLUMN bookings.promo_code IS '優惠碼（例如：M1、L1、W1）';
COMMENT ON COLUMN bookings.influencer_id IS '網紅 ID（關聯 influencers 表）';
COMMENT ON COLUMN bookings.influencer_commission IS '網紅推廣獎金（從訂單促成費中分配）';
COMMENT ON COLUMN bookings.original_price IS '原始價格（未使用優惠碼前的價格）';
COMMENT ON COLUMN bookings.discount_amount IS '折扣金額（現金折扣 + 百分比折扣）';
COMMENT ON COLUMN bookings.final_price IS '折扣後最終價格（客戶實際支付金額）';

-- 9. 創建索引以提高查詢效能
CREATE INDEX IF NOT EXISTS idx_bookings_promo_code ON bookings(promo_code) WHERE promo_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bookings_influencer_id ON bookings(influencer_id) WHERE influencer_id IS NOT NULL;

-- 10. 更新現有訂單的價格欄位
-- 對於沒有使用優惠碼的訂單，original_price 和 final_price 都等於 total_amount
UPDATE bookings
SET 
  original_price = total_amount,
  final_price = total_amount,
  discount_amount = 0
WHERE original_price IS NULL OR final_price IS NULL;

-- 11. 驗證欄位已添加
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'bookings'
  AND column_name IN ('promo_code', 'influencer_id', 'influencer_commission', 'original_price', 'discount_amount', 'final_price')
ORDER BY column_name;

-- 12. 顯示完成訊息
DO $$
BEGIN
    RAISE NOTICE '✅ 優惠碼欄位已成功添加到 bookings 表！';
    RAISE NOTICE '   - promo_code: 優惠碼';
    RAISE NOTICE '   - influencer_id: 網紅 ID';
    RAISE NOTICE '   - influencer_commission: 網紅推廣獎金';
    RAISE NOTICE '   - original_price: 原始價格';
    RAISE NOTICE '   - discount_amount: 折扣金額';
    RAISE NOTICE '   - final_price: 折扣後最終價格';
    RAISE NOTICE '   - 已創建索引和外鍵約束';
    RAISE NOTICE '   - 已更新現有訂單的價格欄位';
END $$;

