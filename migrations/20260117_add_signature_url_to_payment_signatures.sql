-- ============================================
-- 添加 signature_url 欄位到 payment_signatures 表
-- ============================================
-- 創建日期: 2026-01-17
-- 用途: 支援將簽名圖片儲存到 Supabase Storage，並在郵件中使用公開 URL
-- 原因: Gmail 等郵件客戶端不支援長 Base64 字串作為圖片
-- ============================================

-- 1. 確保 payment_signatures 表存在
CREATE TABLE IF NOT EXISTS payment_signatures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL REFERENCES bookings(id),
    payment_id UUID REFERENCES payments(id),
    signature_base64 TEXT,  -- 保留以向後兼容
    signature_url TEXT,     -- 新增：Supabase Storage 公開 URL
    signed_at TIMESTAMP WITH TIME ZONE NOT NULL,
    client_ip VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. 添加 signature_url 欄位（如果不存在）
ALTER TABLE payment_signatures 
ADD COLUMN IF NOT EXISTS signature_url TEXT;

-- 3. 添加索引以提高查詢性能
CREATE INDEX IF NOT EXISTS idx_payment_signatures_booking_id 
    ON payment_signatures(booking_id);

CREATE INDEX IF NOT EXISTS idx_payment_signatures_created_at 
    ON payment_signatures(created_at DESC);

-- 4. 添加註釋
COMMENT ON TABLE payment_signatures IS '支付簽名記錄表 - 儲存客戶支付尾款時的數位簽名';
COMMENT ON COLUMN payment_signatures.signature_base64 IS '簽名的 Base64 編碼（向後兼容，建議使用 signature_url）';
COMMENT ON COLUMN payment_signatures.signature_url IS '簽名圖片在 Supabase Storage 的公開 URL';
COMMENT ON COLUMN payment_signatures.signed_at IS '簽名時間';
COMMENT ON COLUMN payment_signatures.client_ip IS '客戶端 IP 地址';
COMMENT ON COLUMN payment_signatures.user_agent IS '客戶端 User Agent';

-- 5. 創建 Storage bucket（需要在 Supabase Dashboard 或使用 Storage API）
-- 注意：此 SQL 僅作為文檔，實際創建需要使用 Supabase Storage API 或 Dashboard
-- Bucket 名稱: payment-signatures
-- 公開訪問: true
-- 文件大小限制: 5MB
-- 允許的文件類型: image/png, image/jpeg

