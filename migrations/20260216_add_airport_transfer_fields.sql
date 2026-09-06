-- 為 bookings 表新增機場接送相關欄位
-- 支援「加購接機」「加購送機」模式的資料存儲

-- 加購接機欄位
ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS add_airport_pickup BOOLEAN DEFAULT false;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS pickup_flight_number TEXT;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS pickup_airport_code TEXT;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS pickup_scheduled_time TEXT;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS pickup_terminal TEXT;

-- 加購送機欄位
ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS add_airport_dropoff BOOLEAN DEFAULT false;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS dropoff_flight_number TEXT;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS dropoff_airport_code TEXT;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS dropoff_scheduled_time TEXT;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS dropoff_terminal TEXT;

-- 加購接機成交價快照（鎖定金額，不受價目表變動影響）
ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS pickup_transfer_price INTEGER;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS pickup_transfer_region TEXT;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS pickup_transfer_vehicle_type TEXT;

-- 加購送機成交價快照
ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS dropoff_transfer_price INTEGER;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS dropoff_transfer_region TEXT;

ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS dropoff_transfer_vehicle_type TEXT;

-- 添加註解
COMMENT ON COLUMN bookings.add_airport_pickup IS '是否加購接機服務';
COMMENT ON COLUMN bookings.pickup_flight_number IS '接機航班編號（如 IT203）';
COMMENT ON COLUMN bookings.pickup_airport_code IS '接機機場代碼（TSA/TPE/RMQ/KHH）';
COMMENT ON COLUMN bookings.pickup_scheduled_time IS '接機航班表訂時間';
COMMENT ON COLUMN bookings.pickup_terminal IS '接機航廈（T1, T2）— 目前僅 TPE 提供';
COMMENT ON COLUMN bookings.add_airport_dropoff IS '是否加購送機服務';
COMMENT ON COLUMN bookings.dropoff_flight_number IS '送機航班編號';
COMMENT ON COLUMN bookings.dropoff_airport_code IS '送機機場代碼（TSA/TPE/RMQ/KHH）';
COMMENT ON COLUMN bookings.dropoff_scheduled_time IS '送機航班表訂時間';
COMMENT ON COLUMN bookings.dropoff_terminal IS '送機航廈（T1, T2）— 目前僅 TPE 提供';
COMMENT ON COLUMN bookings.pickup_transfer_price IS '接機成交價快照 (NTD)，下單時鎖定';
COMMENT ON COLUMN bookings.pickup_transfer_region IS '接機地區快照（雙北/桃園/台中/...）';
COMMENT ON COLUMN bookings.pickup_transfer_vehicle_type IS '接機車型快照（XS/S/M/L/XL）';
COMMENT ON COLUMN bookings.dropoff_transfer_price IS '送機成交價快照 (NTD)，下單時鎖定';
COMMENT ON COLUMN bookings.dropoff_transfer_region IS '送機地區快照（雙北/桃園/台中/...）';
COMMENT ON COLUMN bookings.dropoff_transfer_vehicle_type IS '送機車型快照（XS/S/M/L/XL）';
