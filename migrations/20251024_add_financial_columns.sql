-- ============================================
-- 添加財務相關欄位到 bookings 表
-- ============================================
-- 創建日期: 2025-10-24
-- 用途: 添加 driver_earning, platform_fee, completed_at 欄位
-- ============================================

-- 1. 添加 platform_fee 欄位（平台抽成）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS platform_fee DECIMAL(10, 2) DEFAULT 0;

-- 2. 添加 driver_earning 欄位（司機實際收入）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS driver_earning DECIMAL(10, 2) DEFAULT 0;

-- 3. 添加 completed_at 欄位（完成時間）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP WITH TIME ZONE;

-- 4. 更新現有資料：計算 platform_fee 和 driver_earning
-- 假設平台抽成 25%，司機收入 75%
UPDATE bookings 
SET 
  platform_fee = COALESCE(total_amount, 0) * 0.25,
  driver_earning = COALESCE(total_amount, 0) * 0.75,
  completed_at = actual_end_time
WHERE platform_fee IS NULL OR driver_earning IS NULL OR completed_at IS NULL;

-- 5. 創建觸發器函數：自動計算 platform_fee 和 driver_earning
CREATE OR REPLACE FUNCTION calculate_booking_financials()
RETURNS TRIGGER AS $$
BEGIN
  -- 計算平台抽成（25%）
  NEW.platform_fee := COALESCE(NEW.total_amount, 0) * 0.25;
  
  -- 計算司機收入（75%）
  NEW.driver_earning := COALESCE(NEW.total_amount, 0) * 0.75;
  
  -- 如果狀態變為 completed，設定 completed_at
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    NEW.completed_at := NOW();
  END IF;
  
  -- 如果有 actual_end_time 但沒有 completed_at，同步
  IF NEW.actual_end_time IS NOT NULL AND NEW.completed_at IS NULL THEN
    NEW.completed_at := NEW.actual_end_time;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 6. 創建觸發器：在插入或更新時自動計算
DROP TRIGGER IF EXISTS trigger_calculate_booking_financials ON bookings;
CREATE TRIGGER trigger_calculate_booking_financials
  BEFORE INSERT OR UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION calculate_booking_financials();

-- 7. 創建索引以優化查詢效能
CREATE INDEX IF NOT EXISTS idx_bookings_driver_id 
ON bookings(driver_id) 
WHERE driver_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_completed_at 
ON bookings(completed_at) 
WHERE completed_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_driver_status_completed 
ON bookings(driver_id, status, completed_at) 
WHERE driver_id IS NOT NULL AND completed_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_status_completed 
ON bookings(status, completed_at) 
WHERE completed_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_actual_end_time 
ON bookings(actual_end_time) 
WHERE actual_end_time IS NOT NULL;

-- 8. 添加註釋
COMMENT ON COLUMN bookings.platform_fee IS '平台抽成（25% of total_amount）';
COMMENT ON COLUMN bookings.driver_earning IS '司機實際收入（75% of total_amount）';
COMMENT ON COLUMN bookings.completed_at IS '訂單完成時間（與 actual_end_time 同步）';

