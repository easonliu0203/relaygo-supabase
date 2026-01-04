-- 修復 system_settings 表的 Row Level Security (RLS) 策略
-- 問題：PUT 請求返回 500 錯誤 "new row violates row-level security policy"
-- 原因：RLS 已啟用但沒有允許插入/更新的策略

-- 1. 檢查當前 RLS 狀態
SELECT 
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'system_settings';

-- 2. 檢查現有策略
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'system_settings';

-- 3. 刪除所有現有策略（如果有）
DROP POLICY IF EXISTS "Allow all operations for authenticated users" ON system_settings;
DROP POLICY IF EXISTS "Allow read for all" ON system_settings;
DROP POLICY IF EXISTS "Allow write for authenticated" ON system_settings;
DROP POLICY IF EXISTS "Allow insert for service role" ON system_settings;
DROP POLICY IF EXISTS "Allow update for service role" ON system_settings;

-- 4. 創建新的 RLS 策略

-- 策略 1：允許所有人讀取系統設定
CREATE POLICY "Allow read access to all users"
ON system_settings
FOR SELECT
USING (true);

-- 策略 2：允許服務角色（service_role）插入資料
CREATE POLICY "Allow insert for service role"
ON system_settings
FOR INSERT
WITH CHECK (true);

-- 策略 3：允許服務角色（service_role）更新資料
CREATE POLICY "Allow update for service role"
ON system_settings
FOR UPDATE
USING (true)
WITH CHECK (true);

-- 策略 4：允許服務角色（service_role）刪除資料
CREATE POLICY "Allow delete for service role"
ON system_settings
FOR DELETE
USING (true);

-- 5. 確保 RLS 已啟用
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;

-- 6. 驗證策略已創建
SELECT 
  policyname,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'system_settings'
ORDER BY policyname;

-- 7. 測試插入（應該成功）
-- 注意：這個測試需要使用 service_role 金鑰執行
-- INSERT INTO system_settings (key, value, created_at, updated_at)
-- VALUES ('test_key', '{"test": true}'::jsonb, NOW(), NOW())
-- ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- 8. 清理測試資料
-- DELETE FROM system_settings WHERE key = 'test_key';

COMMENT ON TABLE system_settings IS 'System-wide configuration settings with RLS enabled for security';
COMMENT ON POLICY "Allow read access to all users" ON system_settings IS 'Anyone can read system settings';
COMMENT ON POLICY "Allow insert for service role" ON system_settings IS 'Only service role can insert new settings';
COMMENT ON POLICY "Allow update for service role" ON system_settings IS 'Only service role can update existing settings';
COMMENT ON POLICY "Allow delete for service role" ON system_settings IS 'Only service role can delete settings';

