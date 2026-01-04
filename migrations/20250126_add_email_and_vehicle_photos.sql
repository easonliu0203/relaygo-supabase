-- =====================================================
-- 遷移腳本：添加 email 欄位、車輛照片表和靠行公司資訊
-- 創建日期：2025-01-26
-- 描述：
--   1. 在 user_profiles 表中添加 email 欄位
--   2. 創建 driver_vehicle_photos 表存儲車輛照片
--   3. 在 drivers 表中添加靠行公司資訊欄位
-- =====================================================

-- =====================================================
-- 1. 在 user_profiles 表中添加 email 欄位
-- =====================================================

-- 添加 email 欄位
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS email VARCHAR(255);

-- 添加欄位註釋
COMMENT ON COLUMN user_profiles.email IS '用戶電子信箱';

-- 創建索引以提高查詢效率
CREATE INDEX IF NOT EXISTS idx_user_profiles_email 
ON user_profiles(email);

-- =====================================================
-- 2. 創建 driver_vehicle_photos 表
-- =====================================================

-- 創建車輛照片表
CREATE TABLE IF NOT EXISTS driver_vehicle_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  photo_type VARCHAR(50) NOT NULL CHECK (photo_type IN (
    'front_left',      -- 左前方
    'front_right',     -- 右前方
    'rear_left',       -- 左後方
    'rear_right',      -- 右後方
    'front_seat',      -- 前座區
    'rear_seat_1',     -- 後座區 1
    'rear_seat_2',     -- 後座區 2
    'rear_seat_3',     -- 後座區 3
    'trunk'            -- 後車箱
  )),
  url TEXT NOT NULL,
  file_size INTEGER,  -- 文件大小（bytes）
  width INTEGER,      -- 圖片寬度
  height INTEGER,     -- 圖片高度
  uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(driver_id, photo_type)
);

-- 添加表註釋
COMMENT ON TABLE driver_vehicle_photos IS '司機車輛照片表';
COMMENT ON COLUMN driver_vehicle_photos.id IS '主鍵';
COMMENT ON COLUMN driver_vehicle_photos.driver_id IS '司機 ID（關聯 users 表）';
COMMENT ON COLUMN driver_vehicle_photos.photo_type IS '照片類型';
COMMENT ON COLUMN driver_vehicle_photos.url IS '照片 URL';
COMMENT ON COLUMN driver_vehicle_photos.file_size IS '文件大小（bytes）';
COMMENT ON COLUMN driver_vehicle_photos.width IS '圖片寬度';
COMMENT ON COLUMN driver_vehicle_photos.height IS '圖片高度';
COMMENT ON COLUMN driver_vehicle_photos.uploaded_at IS '上傳時間';
COMMENT ON COLUMN driver_vehicle_photos.created_at IS '創建時間';
COMMENT ON COLUMN driver_vehicle_photos.updated_at IS '更新時間';

-- 創建索引
CREATE INDEX IF NOT EXISTS idx_driver_vehicle_photos_driver_id 
ON driver_vehicle_photos(driver_id);

CREATE INDEX IF NOT EXISTS idx_driver_vehicle_photos_photo_type 
ON driver_vehicle_photos(photo_type);

CREATE INDEX IF NOT EXISTS idx_driver_vehicle_photos_uploaded_at 
ON driver_vehicle_photos(uploaded_at DESC);

-- 創建觸發器自動更新 updated_at
CREATE OR REPLACE FUNCTION update_driver_vehicle_photos_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_driver_vehicle_photos_updated_at
BEFORE UPDATE ON driver_vehicle_photos
FOR EACH ROW
EXECUTE FUNCTION update_driver_vehicle_photos_updated_at();

-- =====================================================
-- 3. 在 drivers 表中添加靠行公司資訊欄位
-- =====================================================

-- 檢查 drivers 表是否存在，如果不存在則創建
CREATE TABLE IF NOT EXISTS drivers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  license_number VARCHAR(50),
  license_expiry_date DATE,
  vehicle_number VARCHAR(20),
  vehicle_model VARCHAR(100),
  vehicle_year INTEGER,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id)
);

-- 添加靠行公司資訊欄位
ALTER TABLE drivers 
ADD COLUMN IF NOT EXISTS company_name VARCHAR(255),
ADD COLUMN IF NOT EXISTS company_tax_id VARCHAR(8);

-- 添加欄位註釋
COMMENT ON COLUMN drivers.company_name IS '靠行公司名稱';
COMMENT ON COLUMN drivers.company_tax_id IS '靠行公司統一編號（8 位數字）';

-- 創建索引
CREATE INDEX IF NOT EXISTS idx_drivers_company_tax_id 
ON drivers(company_tax_id);

-- 添加統一編號格式驗證約束
ALTER TABLE drivers 
DROP CONSTRAINT IF EXISTS check_company_tax_id_format;

ALTER TABLE drivers 
ADD CONSTRAINT check_company_tax_id_format 
CHECK (company_tax_id IS NULL OR company_tax_id ~ '^\d{8}$');

-- =====================================================
-- 4. Row Level Security (RLS) 策略
-- =====================================================

-- 啟用 RLS
ALTER TABLE driver_vehicle_photos ENABLE ROW LEVEL SECURITY;

-- 刪除舊策略（如果存在）
DROP POLICY IF EXISTS "司機可以查看自己的車輛照片" ON driver_vehicle_photos;
DROP POLICY IF EXISTS "司機可以插入自己的車輛照片" ON driver_vehicle_photos;
DROP POLICY IF EXISTS "司機可以更新自己的車輛照片" ON driver_vehicle_photos;
DROP POLICY IF EXISTS "司機可以刪除自己的車輛照片" ON driver_vehicle_photos;
DROP POLICY IF EXISTS "管理員可以查看所有車輛照片" ON driver_vehicle_photos;

-- 創建新策略
CREATE POLICY "司機可以查看自己的車輛照片"
ON driver_vehicle_photos
FOR SELECT
USING (auth.uid() = driver_id);

CREATE POLICY "司機可以插入自己的車輛照片"
ON driver_vehicle_photos
FOR INSERT
WITH CHECK (auth.uid() = driver_id);

CREATE POLICY "司機可以更新自己的車輛照片"
ON driver_vehicle_photos
FOR UPDATE
USING (auth.uid() = driver_id)
WITH CHECK (auth.uid() = driver_id);

CREATE POLICY "司機可以刪除自己的車輛照片"
ON driver_vehicle_photos
FOR DELETE
USING (auth.uid() = driver_id);

CREATE POLICY "管理員可以查看所有車輛照片"
ON driver_vehicle_photos
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM user_profiles
    WHERE user_profiles.user_id = auth.uid()
    AND user_profiles.role = 'admin'
  )
);

-- =====================================================
-- 5. 測試數據（可選，僅用於開發環境）
-- =====================================================

-- 取消註釋以下代碼以插入測試數據
/*
-- 插入測試車輛照片
INSERT INTO driver_vehicle_photos (driver_id, photo_type, url, file_size, width, height)
VALUES 
  ('test-driver-uuid', 'front_left', 'https://example.com/front_left.jpg', 512000, 1600, 1200),
  ('test-driver-uuid', 'front_right', 'https://example.com/front_right.jpg', 498000, 1600, 1200)
ON CONFLICT (driver_id, photo_type) DO NOTHING;

-- 更新測試司機的靠行公司資訊
UPDATE drivers 
SET company_name = '測試靠行公司', company_tax_id = '12345678'
WHERE user_id = 'test-driver-uuid';
*/

-- =====================================================
-- 遷移完成
-- =====================================================

-- 顯示成功訊息
DO $$
BEGIN
  RAISE NOTICE '✅ 遷移成功完成！';
  RAISE NOTICE '✅ user_profiles 表已添加 email 欄位';
  RAISE NOTICE '✅ driver_vehicle_photos 表已創建';
  RAISE NOTICE '✅ drivers 表已添加靠行公司資訊欄位';
  RAISE NOTICE '✅ RLS 策略已創建';
  RAISE NOTICE '✅ 索引和觸發器已創建';
END $$;

