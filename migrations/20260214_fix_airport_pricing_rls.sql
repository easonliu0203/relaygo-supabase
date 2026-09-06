-- ============================================================
-- 修復：更新 airport_transfer_pricing RLS 政策
-- 原因：web-admin 使用 anon key，但原 RLS 只給 anon SELECT 權限
-- 修改：讓 anon 也有完整 CRUD 權限（web-admin 已有 Firebase Auth 保護）
-- ============================================================

-- 移除舊的 anon 唯讀政策
DROP POLICY IF EXISTS "anon_read_active" ON airport_transfer_pricing;

-- 新增 anon 完整存取政策
CREATE POLICY "anon_full_access" ON airport_transfer_pricing
  FOR ALL
  TO anon
  USING (true)
  WITH CHECK (true);
