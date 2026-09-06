-- 修復 bookings 表的 influencer_commission_type 檢查約束
-- 問題: 原約束只允許 'fixed' 或 'percent'，但後端代碼會產生 'both' 值
-- 解決: 修改約束允許 'fixed', 'percent', 'both' 三種值

-- 刪除舊約束
ALTER TABLE bookings 
DROP CONSTRAINT IF EXISTS bookings_influencer_commission_type_check;

-- 新增更新後的約束
ALTER TABLE bookings 
ADD CONSTRAINT bookings_influencer_commission_type_check 
CHECK (influencer_commission_type IN ('fixed', 'percent', 'both'));

-- 驗證約束
COMMENT ON CONSTRAINT bookings_influencer_commission_type_check ON bookings IS 
'推廣者佣金類型: fixed (固定金額), percent (百分比), both (固定金額+百分比)';

