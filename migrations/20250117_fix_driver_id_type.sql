-- 修復 driver_id 欄位類型問題
-- 將 driver_id 從 UUID 改為 VARCHAR(128) 以存儲 Firebase UID

-- ========================================
-- 1. 修復 driver_documents 表
-- ========================================

-- 刪除所有 RLS 策略
DROP POLICY IF EXISTS "Drivers can view their own documents" ON driver_documents;
DROP POLICY IF EXISTS "Drivers can insert their own documents" ON driver_documents;
DROP POLICY IF EXISTS "Drivers can update their own documents" ON driver_documents;
DROP POLICY IF EXISTS "司機可以查看自己的文件" ON driver_documents;
DROP POLICY IF EXISTS "司機可以插入自己的文件" ON driver_documents;
DROP POLICY IF EXISTS "司機可以更新自己的文件" ON driver_documents;

-- 修改欄位類型
ALTER TABLE driver_documents ALTER COLUMN driver_id TYPE VARCHAR(128);

-- 重新創建 RLS 策略
CREATE POLICY "Drivers can view their own documents"
    ON driver_documents FOR SELECT
    USING (driver_id = (auth.jwt() ->> 'sub'));

CREATE POLICY "Drivers can insert their own documents"
    ON driver_documents FOR INSERT
    WITH CHECK (driver_id = (auth.jwt() ->> 'sub'));

CREATE POLICY "Drivers can update their own documents"
    ON driver_documents FOR UPDATE
    USING (driver_id = (auth.jwt() ->> 'sub'));

-- ========================================
-- 2. 修復 driver_vehicle_photos 表
-- ========================================

-- 刪除所有 RLS 策略
DROP POLICY IF EXISTS "Drivers can view their own vehicle photos" ON driver_vehicle_photos;
DROP POLICY IF EXISTS "Drivers can insert their own vehicle photos" ON driver_vehicle_photos;
DROP POLICY IF EXISTS "Drivers can update their own vehicle photos" ON driver_vehicle_photos;
DROP POLICY IF EXISTS "司機可以查看自己的車輛照片" ON driver_vehicle_photos;
DROP POLICY IF EXISTS "司機可以插入自己的車輛照片" ON driver_vehicle_photos;
DROP POLICY IF EXISTS "司機可以更新自己的車輛照片" ON driver_vehicle_photos;

-- 修改欄位類型
ALTER TABLE driver_vehicle_photos ALTER COLUMN driver_id TYPE VARCHAR(128);

-- 重新創建 RLS 策略
CREATE POLICY "Drivers can view their own vehicle photos"
    ON driver_vehicle_photos FOR SELECT
    USING (driver_id = (auth.jwt() ->> 'sub'));

CREATE POLICY "Drivers can insert their own vehicle photos"
    ON driver_vehicle_photos FOR INSERT
    WITH CHECK (driver_id = (auth.jwt() ->> 'sub'));

CREATE POLICY "Drivers can update their own vehicle photos"
    ON driver_vehicle_photos FOR UPDATE
    USING (driver_id = (auth.jwt() ->> 'sub'));

-- ========================================
-- 3. 修復 driver_company_info 表
-- ========================================

-- 刪除所有 RLS 策略
DROP POLICY IF EXISTS "Drivers can view their own company info" ON driver_company_info;
DROP POLICY IF EXISTS "Drivers can insert their own company info" ON driver_company_info;
DROP POLICY IF EXISTS "Drivers can update their own company info" ON driver_company_info;
DROP POLICY IF EXISTS "司機可以查看自己的靠行公司資訊" ON driver_company_info;
DROP POLICY IF EXISTS "司機可以插入自己的靠行公司資訊" ON driver_company_info;
DROP POLICY IF EXISTS "司機可以更新自己的靠行公司資訊" ON driver_company_info;

-- 修改欄位類型
ALTER TABLE driver_company_info ALTER COLUMN driver_id TYPE VARCHAR(128);

-- 重新創建 RLS 策略
CREATE POLICY "Drivers can view their own company info"
    ON driver_company_info FOR SELECT
    USING (driver_id = (auth.jwt() ->> 'sub'));

CREATE POLICY "Drivers can insert their own company info"
    ON driver_company_info FOR INSERT
    WITH CHECK (driver_id = (auth.jwt() ->> 'sub'));

CREATE POLICY "Drivers can update their own company info"
    ON driver_company_info FOR UPDATE
    USING (driver_id = (auth.jwt() ->> 'sub'));

-- ========================================
-- 4. 修復 driver_bank_accounts 表
-- ========================================

-- 刪除所有 RLS 策略
DROP POLICY IF EXISTS "Drivers can view their own bank account" ON driver_bank_accounts;
DROP POLICY IF EXISTS "Drivers can insert their own bank account" ON driver_bank_accounts;
DROP POLICY IF EXISTS "Drivers can update their own bank account" ON driver_bank_accounts;
DROP POLICY IF EXISTS "司機可以查看自己的銀行帳戶" ON driver_bank_accounts;
DROP POLICY IF EXISTS "司機可以插入自己的銀行帳戶" ON driver_bank_accounts;
DROP POLICY IF EXISTS "司機可以更新自己的銀行帳戶" ON driver_bank_accounts;

-- 修改欄位類型
ALTER TABLE driver_bank_accounts ALTER COLUMN driver_id TYPE VARCHAR(128);

-- 重新創建 RLS 策略
CREATE POLICY "Drivers can view their own bank account"
    ON driver_bank_accounts FOR SELECT
    USING (driver_id = (auth.jwt() ->> 'sub'));

CREATE POLICY "Drivers can insert their own bank account"
    ON driver_bank_accounts FOR INSERT
    WITH CHECK (driver_id = (auth.jwt() ->> 'sub'));

CREATE POLICY "Drivers can update their own bank account"
    ON driver_bank_accounts FOR UPDATE
    USING (driver_id = (auth.jwt() ->> 'sub'));

