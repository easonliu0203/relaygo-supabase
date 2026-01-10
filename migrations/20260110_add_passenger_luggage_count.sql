-- ============================================
-- 添加乘客數量和行李數量欄位到 bookings 表
-- ============================================
-- 創建日期: 2026-01-10
-- 用途: 修復訂單創建時缺少 passenger_count 和 luggage_count 欄位的問題
-- 問題: Outbox trigger 試圖讀取這些欄位，但它們不存在於資料庫中
-- ============================================

-- 1. 添加 passenger_count 欄位（乘客數量）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS passenger_count INTEGER DEFAULT 1;

-- 2. 添加 luggage_count 欄位（行李數量）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS luggage_count INTEGER DEFAULT 0;

-- 3. 添加檢查約束（確保數值合理）
ALTER TABLE bookings 
ADD CONSTRAINT check_passenger_count 
CHECK (passenger_count >= 1 AND passenger_count <= 20);

ALTER TABLE bookings 
ADD CONSTRAINT check_luggage_count 
CHECK (luggage_count >= 0 AND luggage_count <= 50);

-- 4. 添加註釋
COMMENT ON COLUMN bookings.passenger_count IS '乘客數量（預設為 1）';
COMMENT ON COLUMN bookings.luggage_count IS '行李數量（預設為 0）';

-- 5. 創建索引（如果需要按乘客數量查詢）
CREATE INDEX IF NOT EXISTS idx_bookings_passenger_count ON bookings(passenger_count);

-- 6. 驗證欄位已添加
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'bookings'
  AND column_name IN ('passenger_count', 'luggage_count')
ORDER BY column_name;

-- 7. 顯示完成訊息
DO $$
BEGIN
    RAISE NOTICE '✅ passenger_count 和 luggage_count 欄位已成功添加到 bookings 表！';
    RAISE NOTICE '   - passenger_count: 乘客數量（預設為 1，範圍 1-20）';
    RAISE NOTICE '   - luggage_count: 行李數量（預設為 0，範圍 0-50）';
    RAISE NOTICE '   - 已創建索引和檢查約束';
END $$;

