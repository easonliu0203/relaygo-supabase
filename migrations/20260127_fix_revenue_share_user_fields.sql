-- 修復 revenue_share_configs 表的 created_by 和 updated_by 欄位類型
-- 問題: 這些欄位原本是 UUID 類型，但前端傳遞的是字串 'admin'
-- 解決: 將欄位類型改為 VARCHAR(255) 以支援用戶名稱或 ID

-- 修改 created_by 欄位類型
ALTER TABLE revenue_share_configs 
ALTER COLUMN created_by TYPE VARCHAR(255) USING created_by::VARCHAR;

-- 修改 updated_by 欄位類型
ALTER TABLE revenue_share_configs 
ALTER COLUMN updated_by TYPE VARCHAR(255) USING updated_by::VARCHAR;

-- 驗證修改
COMMENT ON COLUMN revenue_share_configs.created_by IS '創建者 (用戶名稱或 ID)';
COMMENT ON COLUMN revenue_share_configs.updated_by IS '更新者 (用戶名稱或 ID)';

