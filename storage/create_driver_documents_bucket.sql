-- 創建司機文件 Storage Bucket
-- 用於儲存司機的各種證件照片

-- 創建 Bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('driver-documents', 'driver-documents', true)
ON CONFLICT (id) DO NOTHING;

-- 創建 Storage 策略：司機可以上傳自己的文件
CREATE POLICY "Drivers can upload their own documents"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'driver-documents' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 創建 Storage 策略：司機可以查看自己的文件
CREATE POLICY "Drivers can view their own documents"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'driver-documents' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 創建 Storage 策略：司機可以更新自己的文件
CREATE POLICY "Drivers can update their own documents"
ON storage.objects FOR UPDATE TO authenticated
USING (
    bucket_id = 'driver-documents' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
)
WITH CHECK (
    bucket_id = 'driver-documents' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 創建 Storage 策略：司機可以刪除自己的文件
CREATE POLICY "Drivers can delete their own documents"
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id = 'driver-documents' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 創建 Storage 策略：管理員可以查看所有文件
CREATE POLICY "Admins can view all driver documents"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'driver-documents' AND
    EXISTS (
        SELECT 1 FROM users
        WHERE users.firebase_uid = auth.jwt() ->> 'sub'
        AND users.role = 'admin'
    )
);

