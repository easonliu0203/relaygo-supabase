-- 創建司機文件資料表
-- 用於儲存司機的各種證件照片 URL

CREATE TABLE IF NOT EXISTS driver_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id VARCHAR(128) NOT NULL,
    id_card_front_url TEXT,
    id_card_back_url TEXT,
    driver_license_url TEXT,
    vehicle_registration_url TEXT,
    insurance_url TEXT,
    police_clearance_url TEXT,
    no_accident_record_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(driver_id)
);

-- 創建索引
CREATE INDEX IF NOT EXISTS idx_driver_documents_driver_id ON driver_documents(driver_id);

-- 啟用 Row Level Security
ALTER TABLE driver_documents ENABLE ROW LEVEL SECURITY;

-- 創建 RLS 策略：司機只能查看自己的文件
CREATE POLICY "Drivers can view their own documents"
    ON driver_documents FOR SELECT
    USING (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：司機可以插入自己的文件
CREATE POLICY "Drivers can insert their own documents"
    ON driver_documents FOR INSERT
    WITH CHECK (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：司機可以更新自己的文件
CREATE POLICY "Drivers can update their own documents"
    ON driver_documents FOR UPDATE
    USING (driver_id = auth.jwt() ->> 'sub')
    WITH CHECK (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：司機可以刪除自己的文件
CREATE POLICY "Drivers can delete their own documents"
    ON driver_documents FOR DELETE
    USING (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：管理員可以查看所有文件
CREATE POLICY "Admins can view all documents"
    ON driver_documents FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE users.firebase_uid = auth.jwt() ->> 'sub'
            AND users.role = 'admin'
        )
    );

-- 添加註釋
COMMENT ON TABLE driver_documents IS '司機證件文件資料表';
COMMENT ON COLUMN driver_documents.driver_id IS '司機的 Firebase UID';
COMMENT ON COLUMN driver_documents.id_card_front_url IS '身分證正面照片 URL';
COMMENT ON COLUMN driver_documents.id_card_back_url IS '身分證背面照片 URL';
COMMENT ON COLUMN driver_documents.driver_license_url IS '駕照照片 URL';
COMMENT ON COLUMN driver_documents.vehicle_registration_url IS '行照照片 URL';
COMMENT ON COLUMN driver_documents.insurance_url IS '保險單照片 URL';
COMMENT ON COLUMN driver_documents.police_clearance_url IS '良民證照片 URL';
COMMENT ON COLUMN driver_documents.no_accident_record_url IS '無肇事紀錄照片 URL';

