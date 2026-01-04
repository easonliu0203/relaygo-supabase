-- =====================================================
-- 遷移腳本：添加司機出發和到達位置欄位
-- 創建日期：2025-11-30
-- 描述：
--   在 bookings 表中添加司機出發和到達位置的經緯度欄位
--   用於記錄司機點擊「出發」和「到達」按鈕時的位置
-- =====================================================

-- 添加司機出發位置欄位
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS driver_depart_latitude DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS driver_depart_longitude DECIMAL(11, 8);

-- 添加司機到達位置欄位
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS driver_arrive_latitude DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS driver_arrive_longitude DECIMAL(11, 8);

-- 添加欄位註釋
COMMENT ON COLUMN bookings.driver_depart_latitude IS '司機出發時的緯度';
COMMENT ON COLUMN bookings.driver_depart_longitude IS '司機出發時的經度';
COMMENT ON COLUMN bookings.driver_arrive_latitude IS '司機到達時的緯度';
COMMENT ON COLUMN bookings.driver_arrive_longitude IS '司機到達時的經度';

-- 創建索引以提高查詢效率（可選）
CREATE INDEX IF NOT EXISTS idx_bookings_driver_depart_location 
ON bookings(driver_depart_latitude, driver_depart_longitude) 
WHERE driver_depart_latitude IS NOT NULL AND driver_depart_longitude IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_driver_arrive_location 
ON bookings(driver_arrive_latitude, driver_arrive_longitude) 
WHERE driver_arrive_latitude IS NOT NULL AND driver_arrive_longitude IS NOT NULL;

