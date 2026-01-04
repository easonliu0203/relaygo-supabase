-- 設置即時 Webhook 同步（替代 Cron Job）
-- 
-- 原理：當 Outbox 表有新事件時，立即觸發 Edge Function
-- 優點：延遲從 1-2 分鐘降低到 1-2 秒
-- 
-- ============================================
-- 步驟 1：啟用 pg_net 擴展（用於發送 HTTP 請求）
-- ============================================
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ============================================
-- 步驟 2：創建即時觸發函數
-- ============================================
CREATE OR REPLACE FUNCTION trigger_sync_to_firestore()
RETURNS TRIGGER AS $$
DECLARE
  edge_function_url TEXT;
  service_role_key TEXT;
  request_id BIGINT;
BEGIN
  -- Edge Function URL
  edge_function_url := 'https://vlyhwegpvpnjyocqmfqc.supabase.co/functions/v1/sync-to-firestore';
  
  -- Service Role Key（請替換為實際的 key）
  -- ⚠️ 重要：請在 Supabase Dashboard → Settings → API 中找到 service_role_key
  service_role_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZseWh3ZWdwdnBuanlvY3FtZnFjIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODk3Nzk5NiwiZXhwIjoyMDc0NTUzOTk2fQ.nQPynfQcSIZ1QPVSjDcgscugQcEgfRPUauW0psSRTQo';
  
  -- 發送異步 HTTP POST 請求到 Edge Function
  BEGIN
    SELECT net.http_post(
      url := edge_function_url,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || service_role_key,
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'trigger', 'webhook',
        'event_id', NEW.id,
        'aggregate_id', NEW.aggregate_id,
        'event_type', NEW.event_type
      )
    ) INTO request_id;
    
    RAISE NOTICE '✅ Webhook 已觸發: event_id=%, request_id=%', NEW.id, request_id;
    
  EXCEPTION
    WHEN OTHERS THEN
      -- 如果 HTTP 請求失敗，記錄錯誤但不阻止 Trigger 執行
      -- Cron Job 會作為補償機制處理這個事件
      RAISE WARNING '❌ Webhook 觸發失敗: event_id=%, error=%', NEW.id, SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 步驟 3：創建 Trigger（在 Outbox 表插入時觸發）
-- ============================================
DROP TRIGGER IF EXISTS outbox_webhook_trigger ON outbox;

CREATE TRIGGER outbox_webhook_trigger
  AFTER INSERT ON outbox
  FOR EACH ROW
  EXECUTE FUNCTION trigger_sync_to_firestore();

-- ============================================
-- 步驟 4：驗證 Trigger 已創建
-- ============================================
SELECT 
  '✅ Webhook Trigger 已創建' as status,
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  tgenabled as enabled
FROM pg_trigger
WHERE tgname = 'outbox_webhook_trigger';

-- ============================================
-- 步驟 5：測試 Webhook（可選）
-- ============================================
-- 插入一個測試事件，應該會立即觸發 Edge Function
-- INSERT INTO outbox (
--   aggregate_type,
--   aggregate_id,
--   event_type,
--   payload
-- ) VALUES (
--   'booking',
--   'test-booking-id',
--   'updated',
--   '{"test": true}'::jsonb
-- );

-- ============================================
-- 完成
-- ============================================
SELECT 
  '=== 設置完成 ===' as step,
  '✅ Webhook Trigger 已啟用' as webhook_status,
  '✅ 新事件將在 1-2 秒內同步到 Firestore' as expected_result,
  '⚠️  Cron Job 仍然保留作為補償機制' as note;

