-- 設置直接從 Bookings 表觸發 Webhook（即時同步）
-- 
-- 原理：當 Bookings 表更新時，立即觸發 Edge Function
-- 優點：延遲從 1-2 分鐘降低到 1-2 秒
-- 
-- ============================================
-- 步驟 1：啟用 pg_net 擴展（用於發送 HTTP 請求）
-- ============================================
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ============================================
-- 步驟 2：創建直接觸發函數（在 Bookings 表上）
-- ============================================
CREATE OR REPLACE FUNCTION trigger_booking_sync_to_firestore()
RETURNS TRIGGER AS $$
DECLARE
  edge_function_url TEXT;
  service_role_key TEXT;
  request_id BIGINT;
BEGIN
  -- Edge Function URL
  edge_function_url := 'https://vlyhwegpvpnjyocqmfqc.supabase.co/functions/v1/sync-to-firestore';
  
  -- Service Role Key
  service_role_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZseWh3ZWdwdnBuanlvY3FtZnFjIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODk3Nzk5NiwiZXhwIjoyMDc0NTUzOTk2fQ.nQPynfQcSIZ1QPVSjDcgscugQcEgfRPUauW0psSRTQo';
  
  -- 發送異步 HTTP POST 請求到 Edge Function
  -- 注意：這個請求會在 Bookings Trigger 之後立即執行
  BEGIN
    SELECT net.http_post(
      url := edge_function_url,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || service_role_key,
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'trigger', 'direct_booking_webhook',
        'booking_id', NEW.id,
        'event_type', CASE
          WHEN TG_OP = 'INSERT' THEN 'created'
          WHEN TG_OP = 'UPDATE' THEN 'updated'
          ELSE 'unknown'
        END
      )
    ) INTO request_id;
    
    RAISE NOTICE '✅ Direct Booking Webhook 已觸發: booking_id=%, request_id=%', NEW.id, request_id;
    
  EXCEPTION
    WHEN OTHERS THEN
      -- 如果 HTTP 請求失敗，記錄錯誤但不阻止 Trigger 執行
      -- Outbox Pattern 會作為補償機制處理這個事件
      RAISE WARNING '❌ Direct Booking Webhook 觸發失敗: booking_id=%, error=%', NEW.id, SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 步驟 3：創建 Trigger（在 Bookings 表更新後觸發）
-- ============================================
-- 注意：這個 Trigger 會在 bookings_outbox_trigger 之後執行
-- 因為我們使用 AFTER INSERT OR UPDATE，並且按字母順序執行

DROP TRIGGER IF EXISTS direct_booking_webhook_trigger ON bookings;

CREATE TRIGGER direct_booking_webhook_trigger
  AFTER INSERT OR UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION trigger_booking_sync_to_firestore();

-- ============================================
-- 步驟 4：驗證 Trigger 已創建
-- ============================================
SELECT 
  '✅ Direct Booking Webhook Trigger 已創建' as status,
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  tgenabled as enabled,
  pg_get_triggerdef(oid) as definition
FROM pg_trigger
WHERE tgname = 'direct_booking_webhook_trigger';

-- ============================================
-- 步驟 5：顯示所有 Bookings 表的 Trigger（按執行順序）
-- ============================================
SELECT 
  '步驟 5：Bookings 表的所有 Trigger' as step,
  tgname as trigger_name,
  CASE tgenabled
    WHEN 'O' THEN '✅ 已啟用'
    WHEN 'D' THEN '❌ 已禁用'
    ELSE '⚠️  未知'
  END as status,
  CASE 
    WHEN tgname = 'bookings_outbox_trigger' THEN '1. 寫入 Outbox 表'
    WHEN tgname = 'direct_booking_webhook_trigger' THEN '2. 觸發 Webhook（即時同步）'
    ELSE '其他'
  END as execution_order
FROM pg_trigger
WHERE tgrelid::regclass = 'bookings'::regclass
ORDER BY tgname;

-- ============================================
-- 步驟 6：測試 Webhook（可選）
-- ============================================
-- 更新一個測試訂單，應該會立即觸發 Edge Function
-- UPDATE bookings 
-- SET updated_at = NOW() 
-- WHERE id = 'dfbfb144-4e7a-4902-be7a-954ebbe58888';

-- ============================================
-- 完成
-- ============================================
SELECT 
  '=== 設置完成 ===' as step,
  '✅ Direct Booking Webhook Trigger 已啟用' as webhook_status,
  '✅ 訂單更新將在 1-2 秒內同步到 Firestore' as expected_result,
  '⚠️  Outbox Pattern 仍然保留作為補償機制' as note,
  '⚠️  Cron Job 仍然保留作為補償機制' as note2;

