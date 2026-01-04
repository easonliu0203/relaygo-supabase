-- 擴展 driver_documents 表以支持所有 6 種文件類型
-- 日期：2025-01-26
-- 目的：支持司機端 App 上傳身分證、駕照、行照、保險單、良民證、無肇事紀錄

-- ============================================
-- 第一部分: 修改 driver_documents 表
-- ============================================

-- 1. 如果表不存在，創建表
CREATE TABLE IF NOT EXISTS driver_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(50) NOT NULL,
  url TEXT NOT NULL,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  reviewed_at TIMESTAMP WITH TIME ZONE,
  reviewed_by UUID REFERENCES users(id),
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. 刪除舊的 CHECK 約束（如果存在）
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'driver_documents_type_check'
  ) THEN
    ALTER TABLE driver_documents DROP CONSTRAINT driver_documents_type_check;
  END IF;
END $$;

-- 3. 添加新的 CHECK 約束，支持所有 7 種文件類型（身分證拆分為正反面）
ALTER TABLE driver_documents
ADD CONSTRAINT driver_documents_type_check
CHECK (type IN (
  'id_card_front',        -- 身分證（正面）
  'id_card_back',         -- 身分證（背面）
  'drivers_license',      -- 駕照
  'vehicle_registration', -- 行照
  'insurance_policy',     -- 保險單
  'police_clearance',     -- 良民證
  'no_accident_record',   -- 無肇事紀錄
  -- 保留舊的類型名稱以兼容現有數據
  'id_card',              -- 舊：身分證（未拆分）
  'license',              -- 舊：駕照
  'insurance'             -- 舊：保險單
));

-- 4. 創建索引以提高查詢性能
CREATE INDEX IF NOT EXISTS idx_driver_documents_driver_id ON driver_documents(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_documents_type ON driver_documents(type);
CREATE INDEX IF NOT EXISTS idx_driver_documents_status ON driver_documents(status);

-- 5. 添加唯一約束：每個司機的每種文件類型只能有一個有效記錄
-- 注意：這裡使用部分唯一索引，只對 status != 'rejected' 的記錄生效
CREATE UNIQUE INDEX IF NOT EXISTS idx_driver_documents_unique_type 
ON driver_documents(driver_id, type) 
WHERE status != 'rejected';

-- ============================================
-- 第二部分: 創建 RLS 策略
-- ============================================

-- 啟用 RLS
ALTER TABLE driver_documents ENABLE ROW LEVEL SECURITY;

-- 刪除舊策略（如果存在）
DROP POLICY IF EXISTS "司機可以查看自己的文件" ON driver_documents;
DROP POLICY IF EXISTS "司機可以上傳自己的文件" ON driver_documents;
DROP POLICY IF EXISTS "司機可以更新自己的文件" ON driver_documents;
DROP POLICY IF EXISTS "管理員可以查看所有文件" ON driver_documents;
DROP POLICY IF EXISTS "管理員可以審核文件" ON driver_documents;

-- 1. 司機可以查看自己的文件
CREATE POLICY "司機可以查看自己的文件"
ON driver_documents
FOR SELECT
USING (
  auth.uid() = driver_id
);

-- 2. 司機可以上傳自己的文件
CREATE POLICY "司機可以上傳自己的文件"
ON driver_documents
FOR INSERT
WITH CHECK (
  auth.uid() = driver_id
);

-- 3. 司機可以更新自己的文件（僅限 pending 狀態）
CREATE POLICY "司機可以更新自己的文件"
ON driver_documents
FOR UPDATE
USING (
  auth.uid() = driver_id AND status = 'pending'
)
WITH CHECK (
  auth.uid() = driver_id AND status = 'pending'
);

-- 4. 管理員可以查看所有文件
CREATE POLICY "管理員可以查看所有文件"
ON driver_documents
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND users.role = 'admin'
  )
);

-- 5. 管理員可以審核文件（更新狀態和備註）
CREATE POLICY "管理員可以審核文件"
ON driver_documents
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND users.role = 'admin'
  )
);

-- ============================================
-- 第三部分: 創建觸發器（自動更新 updated_at）
-- ============================================

-- 創建更新時間戳函數（如果不存在）
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 創建觸發器
DROP TRIGGER IF EXISTS update_driver_documents_updated_at ON driver_documents;
CREATE TRIGGER update_driver_documents_updated_at
BEFORE UPDATE ON driver_documents
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 第四部分: 添加註釋
-- ============================================

COMMENT ON TABLE driver_documents IS '司機文件表 - 存儲司機上傳的各種證件和文件';
COMMENT ON COLUMN driver_documents.id IS '文件 ID';
COMMENT ON COLUMN driver_documents.driver_id IS '司機 ID（關聯 users 表）';
COMMENT ON COLUMN driver_documents.type IS '文件類型：id_card_front（身分證正面）、id_card_back（身分證背面）、drivers_license（駕照）、vehicle_registration（行照）、insurance_policy（保險單）、police_clearance（良民證）、no_accident_record（無肇事紀錄）';
COMMENT ON COLUMN driver_documents.url IS '文件 URL（Firebase Storage）';
COMMENT ON COLUMN driver_documents.status IS '審核狀態：pending（待審核）、approved（已通過）、rejected（已拒絕）';
COMMENT ON COLUMN driver_documents.uploaded_at IS '上傳時間';
COMMENT ON COLUMN driver_documents.reviewed_at IS '審核時間';
COMMENT ON COLUMN driver_documents.reviewed_by IS '審核人 ID（關聯 users 表）';
COMMENT ON COLUMN driver_documents.notes IS '審核備註';

-- ============================================
-- 完成
-- ============================================

-- 顯示成功訊息
DO $$
BEGIN
  RAISE NOTICE '✅ driver_documents 表已成功擴展，支持 7 種文件類型（身分證拆分為正反面）';
  RAISE NOTICE '✅ RLS 策略已創建';
  RAISE NOTICE '✅ 索引和觸發器已創建';
END $$;

