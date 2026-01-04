-- 添加 deposit_paid 欄位到 bookings 表
-- 用於標記訂金是否已支付

-- 1. 添加 deposit_paid 欄位（布林值，默認為 false）
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS deposit_paid BOOLEAN DEFAULT false;

-- 2. 添加註釋
COMMENT ON COLUMN bookings.deposit_paid IS '訂金是否已支付';

-- 3. 更新現有訂單的 deposit_paid 欄位
-- 如果訂單狀態是 'paid_deposit' 或之後的狀態，則設置為 true
UPDATE bookings 
SET deposit_paid = true 
WHERE status IN (
  'paid_deposit',
  'assigned',
  'matched',
  'driver_confirmed',
  'driver_departed',
  'driver_arrived',
  'trip_started',
  'trip_ended',
  'pending_balance',
  'completed'
);

-- 4. 驗證修改
SELECT 
  id,
  booking_number,
  status,
  deposit_paid,
  deposit_amount,
  created_at
FROM bookings
ORDER BY created_at DESC
LIMIT 10;

-- 5. 顯示統計信息
SELECT 
  status,
  COUNT(*) as count,
  SUM(CASE WHEN deposit_paid = true THEN 1 ELSE 0 END) as paid_count,
  SUM(CASE WHEN deposit_paid = false THEN 1 ELSE 0 END) as unpaid_count
FROM bookings
GROUP BY status
ORDER BY status;

