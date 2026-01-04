-- 創建司機靠行公司資訊資料表
-- 用於儲存司機的靠行公司資訊

CREATE TABLE IF NOT EXISTS driver_company_info (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id VARCHAR(128) NOT NULL,
    company_name VARCHAR(200),
    tax_id VARCHAR(20),
    contact_phone VARCHAR(20),
    address TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(driver_id)
);

-- 創建索引
CREATE INDEX IF NOT EXISTS idx_driver_company_info_driver_id ON driver_company_info(driver_id);

-- 啟用 Row Level Security
ALTER TABLE driver_company_info ENABLE ROW LEVEL SECURITY;

-- 創建 RLS 策略：司機只能查看自己的靠行公司資訊
CREATE POLICY "Drivers can view their own company info"
    ON driver_company_info FOR SELECT
    USING (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：司機可以插入自己的靠行公司資訊
CREATE POLICY "Drivers can insert their own company info"
    ON driver_company_info FOR INSERT
    WITH CHECK (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：司機可以更新自己的靠行公司資訊
CREATE POLICY "Drivers can update their own company info"
    ON driver_company_info FOR UPDATE
    USING (driver_id = auth.jwt() ->> 'sub')
    WITH CHECK (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：司機可以刪除自己的靠行公司資訊
CREATE POLICY "Drivers can delete their own company info"
    ON driver_company_info FOR DELETE
    USING (driver_id = auth.jwt() ->> 'sub');

-- 創建 RLS 策略：管理員可以查看所有靠行公司資訊
CREATE POLICY "Admins can view all company info"
    ON driver_company_info FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE users.firebase_uid = auth.jwt() ->> 'sub'
            AND users.role = 'admin'
        )
    );

-- 添加註釋
COMMENT ON TABLE driver_company_info IS '司機靠行公司資訊資料表';
COMMENT ON COLUMN driver_company_info.driver_id IS '司機的 Firebase UID';
COMMENT ON COLUMN driver_company_info.company_name IS '靠行公司名稱';
COMMENT ON COLUMN driver_company_info.tax_id IS '統一編號';
COMMENT ON COLUMN driver_company_info.contact_phone IS '聯絡電話';
COMMENT ON COLUMN driver_company_info.address IS '公司地址';

