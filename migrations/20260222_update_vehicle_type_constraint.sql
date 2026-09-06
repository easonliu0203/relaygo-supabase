-- ============================================================
-- 更新 bookings 和 drivers 的 vehicle_type CHECK 約束
-- 新增標準車型代碼：XS / S / M / L / XL
-- 保留舊值 (A/B/C/D/small/large) 相容既有資料
-- ============================================================

-- 1. 更新 bookings 表
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_vehicle_type_check;
ALTER TABLE bookings ADD CONSTRAINT bookings_vehicle_type_check
  CHECK (vehicle_type IN ('A', 'B', 'C', 'D', 'small', 'large', 'XS', 'S', 'M', 'L', 'XL'));

-- 2. 更新 drivers 表
ALTER TABLE drivers DROP CONSTRAINT IF EXISTS drivers_vehicle_type_check;
ALTER TABLE drivers ADD CONSTRAINT drivers_vehicle_type_check
  CHECK (vehicle_type IN ('A', 'B', 'C', 'D', 'small', 'large', 'XS', 'S', 'M', 'L', 'XL'));

-- 3. 驗證
SELECT
    'bookings' AS table_name,
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_def
FROM pg_constraint
WHERE conrelid = 'bookings'::regclass
  AND conname = 'bookings_vehicle_type_check'
UNION ALL
SELECT
    'drivers',
    conname,
    pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'drivers'::regclass
  AND conname = 'drivers_vehicle_type_check';
