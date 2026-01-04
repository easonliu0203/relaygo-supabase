-- ============================================
-- 24/7 全自動派單功能 - 資料庫配置
-- ============================================
-- 日期: 2025-11-09
-- 說明: 在 system_settings 表中添加 auto_dispatch_24_7 配置
-- ============================================

-- 1. 檢查是否已存在配置
SELECT 
    key,
    value,
    description,
    created_at,
    updated_at
FROM system_settings
WHERE key = 'auto_dispatch_24_7';

-- 2. 如果不存在，則插入配置
INSERT INTO system_settings (key, value, description)
VALUES (
    'auto_dispatch_24_7',
    '{
        "enabled": false,
        "interval_seconds": 30,
        "batch_size": 10,
        "last_run_at": null,
        "total_processed": 0,
        "total_assigned": 0,
        "total_failed": 0
    }'::jsonb,
    '24/7 全自動派單設定 - enabled: 是否啟用, interval_seconds: 輪詢間隔(秒), batch_size: 每次最多處理訂單數, last_run_at: 上次執行時間, total_processed: 總處理訂單數, total_assigned: 總成功分配數, total_failed: 總失敗數'
)
ON CONFLICT (key) DO NOTHING;

-- 3. 驗證配置
SELECT 
    key,
    value,
    value->>'enabled' AS enabled,
    value->>'interval_seconds' AS interval_seconds,
    value->>'batch_size' AS batch_size,
    description,
    created_at,
    updated_at
FROM system_settings
WHERE key = 'auto_dispatch_24_7';

-- 4. 查看所有系統配置
SELECT 
    key,
    value,
    description,
    created_at,
    updated_at
FROM system_settings
ORDER BY created_at DESC;

