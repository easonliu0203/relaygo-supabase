-- 創建司機車輛照片資料表
-- 用於儲存司機的車輛外觀和內裝照片 URL

CREATE TABLE IF NOT EXISTS driver_vehicle_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id VARCHAR(128) NOT NULL,
    front_left_url TEXT,
    front_right_url TEXT,
    rear_left_url TEXT,
    rear_right_url TEXT,
    interior_front_url TEXT,
    interior_rear1_url TEXT,
    interior_rear2_url TEXT,
    interior_rear3_url TEXT,
    trunk_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(driver_id)
);

-- 創建索引
CREATE INDEX IF NOT EXISTS idx_driver_vehicle_photos_driver_id ON driver_vehicle_photos(driver_id);

-- 啟用 Row Level Security
ALTER TABLE driver_vehicle_photos ENABLE ROW LEVEL SECURITY;

-- 創建 RLS 策略：司機只能查看自己的車輛照片
CREATE POLICY "Drivers can view their own vehicle photos"
    ON driver_vehicle_photos FOR SELECT
    USING (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：司機可以插入自己的車輛照片
CREATE POLICY "Drivers can insert their own vehicle photos"
    ON driver_vehicle_photos FOR INSERT
    WITH CHECK (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：司機可以更新自己的車輛照片
CREATE POLICY "Drivers can update their own vehicle photos"
    ON driver_vehicle_photos FOR UPDATE
    USING (driver_id = auth.jwt() ->> 'sub')
    WITH CHECK (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：司機可以刪除自己的車輛照片
CREATE POLICY "Drivers can delete their own vehicle photos"
    ON driver_vehicle_photos FOR DELETE
    USING (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：管理員可以查看所有車輛照片
CREATE POLICY "Admins can view all vehicle photos"
    ON driver_vehicle_photos FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE users.firebase_uid = auth.jwt() ->> 'sub'
            AND users.role = 'admin'
        )
    );

-- 添加註釋
COMMENT ON TABLE driver_vehicle_photos IS '司機車輛照片資料表';
COMMENT ON COLUMN driver_vehicle_photos.driver_id IS '司機的 Firebase UID';
COMMENT ON COLUMN driver_vehicle_photos.front_left_url IS '車輛左前方照片 URL';
COMMENT ON COLUMN driver_vehicle_photos.front_right_url IS '車輛右前方照片 URL';
COMMENT ON COLUMN driver_vehicle_photos.rear_left_url IS '車輛左後方照片 URL';
COMMENT ON COLUMN driver_vehicle_photos.rear_right_url IS '車輛右後方照片 URL';
COMMENT ON COLUMN driver_vehicle_photos.interior_front_url IS '前座區照片 URL';
COMMENT ON COLUMN driver_vehicle_photos.interior_rear1_url IS '後座區1照片 URL';
COMMENT ON COLUMN driver_vehicle_photos.interior_rear2_url IS '後座區2照片 URL';
COMMENT ON COLUMN driver_vehicle_photos.interior_rear3_url IS '後座區3照片 URL';
COMMENT ON COLUMN driver_vehicle_photos.trunk_url IS '後車箱照片 URL';

