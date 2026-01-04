-- 創建司機銀行帳戶照片 Storage Bucket
-- 執行此腳本在 Supabase Dashboard > SQL Editor

-- 1. 創建 bucket（如果不存在）
INSERT INTO storage.buckets (id, name, public)
VALUES ('driver-bank-accounts', 'driver-bank-accounts', true)
ON CONFLICT (id) DO NOTHING;

-- 2. 設置 Storage 策略

-- 策略：允許司機上傳自己的銀行帳戶照片
CREATE POLICY "Drivers can upload their own bank account photos"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'driver-bank-accounts' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 策略：允許司機更新自己的銀行帳戶照片
CREATE POLICY "Drivers can update their own bank account photos"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id = 'driver-bank-accounts' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
)
WITH CHECK (
    bucket_id = 'driver-bank-accounts' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 策略：允許司機刪除自己的銀行帳戶照片
CREATE POLICY "Drivers can delete their own bank account photos"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'driver-bank-accounts' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 策略：允許司機查看自己的銀行帳戶照片
CREATE POLICY "Drivers can view their own bank account photos"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'driver-bank-accounts' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 策略：允許管理員查看所有銀行帳戶照片
CREATE POLICY "Admins can view all bank account photos"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'driver-bank-accounts' AND
    EXISTS (
        SELECT 1 FROM public.users
        WHERE users.firebase_uid = auth.jwt() ->> 'sub'
        AND users.role = 'admin'
    )
);

-- 3. 驗證 bucket 創建成功
SELECT * FROM storage.buckets WHERE id = 'driver-bank-accounts';

