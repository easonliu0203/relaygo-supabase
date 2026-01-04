-- 創建司機銀行帳戶表
-- 用於存儲司機的收款帳戶資訊

CREATE TABLE IF NOT EXISTS driver_bank_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id VARCHAR(128) NOT NULL REFERENCES users(firebase_uid) ON DELETE CASCADE,
    bank_name VARCHAR(100) NOT NULL,
    bank_code VARCHAR(6) NOT NULL,
    branch_name VARCHAR(100) NOT NULL,
    account_holder_name VARCHAR(100) NOT NULL,
    account_number VARCHAR(50) NOT NULL,
    cover_photo_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- 確保每個司機只有一個銀行帳戶
    UNIQUE(driver_id)
);

-- 創建索引
CREATE INDEX IF NOT EXISTS idx_driver_bank_accounts_driver_id ON driver_bank_accounts(driver_id);

-- 添加註釋
COMMENT ON TABLE driver_bank_accounts IS '司機銀行帳戶資訊表';
COMMENT ON COLUMN driver_bank_accounts.driver_id IS '司機的 Firebase UID';
COMMENT ON COLUMN driver_bank_accounts.bank_name IS '銀行名稱';
COMMENT ON COLUMN driver_bank_accounts.bank_code IS '銀行代碼（3-6位數字）';
COMMENT ON COLUMN driver_bank_accounts.branch_name IS '分行名稱';
COMMENT ON COLUMN driver_bank_accounts.account_holder_name IS '帳戶持有人姓名';
COMMENT ON COLUMN driver_bank_accounts.account_number IS '帳戶號碼';
COMMENT ON COLUMN driver_bank_accounts.cover_photo_url IS '存摺封面或帳戶證明照片 URL（Supabase Storage）';

-- 啟用 RLS
ALTER TABLE driver_bank_accounts ENABLE ROW LEVEL SECURITY;

-- RLS 策略：司機只能查看自己的銀行帳戶
CREATE POLICY "Drivers can view their own bank account"
    ON driver_bank_accounts
    FOR SELECT
    USING (driver_id = auth.jwt() ->> 'sub');

-- RLS 策略：司機可以插入自己的銀行帳戶
CREATE POLICY "Drivers can insert their own bank account"
    ON driver_bank_accounts
    FOR INSERT
    WITH CHECK (driver_id = auth.jwt() ->> 'sub');

-- RLS 策略：司機可以更新自己的銀行帳戶
CREATE POLICY "Drivers can update their own bank account"
    ON driver_bank_accounts
    FOR UPDATE
    USING (driver_id = auth.jwt() ->> 'sub')
    WITH CHECK (driver_id = auth.jwt() ->> 'sub');

-- RLS 策略：司機可以刪除自己的銀行帳戶
CREATE POLICY "Drivers can delete their own bank account"
    ON driver_bank_accounts
    FOR DELETE
    USING (driver_id = auth.jwt() ->> 'sub');

-- RLS 策略：管理員可以查看所有銀行帳戶
CREATE POLICY "Admins can view all bank accounts"
    ON driver_bank_accounts
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE users.firebase_uid = auth.jwt() ->> 'sub'
            AND users.role = 'admin'
        )
    );

