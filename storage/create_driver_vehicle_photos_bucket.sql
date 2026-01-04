-- 創建司機車輛照片 Storage Bucket
-- 用於儲存司機的車輛外觀和內裝照片

-- 創建 Bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('driver-vehicle-photos', 'driver-vehicle-photos', true)
ON CONFLICT (id) DO NOTHING;

-- 創建 Storage 策略：司機可以上傳自己的車輛照片
CREATE POLICY "Drivers can upload their own vehicle photos"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'driver-vehicle-photos' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 創建 Storage 策略：司機可以查看自己的車輛照片
CREATE POLICY "Drivers can view their own vehicle photos"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'driver-vehicle-photos' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 創建 Storage 策略：司機可以更新自己的車輛照片
CREATE POLICY "Drivers can update their own vehicle photos"
ON storage.objects FOR UPDATE TO authenticated
USING (
    bucket_id = 'driver-vehicle-photos' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
)
WITH CHECK (
    bucket_id = 'driver-vehicle-photos' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 創建 Storage 策略：司機可以刪除自己的車輛照片
CREATE POLICY "Drivers can delete their own vehicle photos"
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id = 'driver-vehicle-photos' AND
    (storage.foldername(name))[1] = auth.jwt() ->> 'sub'
);

-- 創建 Storage 策略：管理員可以查看所有車輛照片
CREATE POLICY "Admins can view all driver vehicle photos"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'driver-vehicle-photos' AND
    EXISTS (
        SELECT 1 FROM users
        WHERE users.firebase_uid = auth.jwt() ->> 'sub'
        AND users.role = 'admin'
    )
);

