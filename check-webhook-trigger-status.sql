-- 檢查 Webhook Trigger 是否正確設置

-- 步驟 1：檢查 pg_net 擴展是否啟用
SELECT 
  '步驟 1：檢查 pg_net 擴展' as step,
  CASE 
    WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') 
    THEN '✅ pg_net 已啟用'
    ELSE '❌ pg_net 未啟用（需要啟用才能發送 HTTP 請求）'
  END as status;

-- 步驟 2：檢查 Webhook Trigger 是否存在
SELECT 
  '步驟 2：檢查 Webhook Trigger' as step,
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  CASE tgenabled
    WHEN 'O' THEN '✅ Trigger 已啟用'
    WHEN 'D' THEN '❌ Trigger 已禁用'
    ELSE '⚠️  Trigger 狀態未知'
  END as status,
  pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgname = 'outbox_webhook_trigger';

-- 步驟 3：檢查 Trigger Function 是否存在
SELECT 
  '步驟 3：檢查 Trigger Function' as step,
  proname as function_name,
  CASE 
    WHEN proname = 'trigger_sync_to_firestore' THEN '✅ Function 已創建'
    ELSE '❌ Function 不存在'
  END as status
FROM pg_proc
WHERE proname = 'trigger_sync_to_firestore';

-- 步驟 4：檢查訂單 dfbfb144-4e7a-4902-be7a-954ebbe58888 的 Outbox 事件
SELECT 
  '步驟 4：最新訂單 Outbox 事件' as step,
  id,
  event_type,
  created_at,
  processed_at,
  CASE 
    WHEN processed_at IS NULL THEN '❌ 未處理'
    ELSE '✅ 已處理 (' || EXTRACT(EPOCH FROM (processed_at - created_at)) || ' 秒)'
  END as status,
  retry_count,
  error_message
FROM outbox
WHERE aggregate_id = 'dfbfb144-4e7a-4902-be7a-954ebbe58888'
ORDER BY created_at DESC;

-- 步驟 5：檢查 pg_net 請求日誌（如果有）
-- 注意：這個表可能不存在，取決於 Supabase 配置
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'net' AND table_name = 'http_request_queue') THEN
    RAISE NOTICE '步驟 5：檢查 pg_net 請求日誌';
    PERFORM * FROM net.http_request_queue ORDER BY id DESC LIMIT 10;
  ELSE
    RAISE NOTICE '步驟 5：pg_net 請求日誌表不存在';
  END IF;
END $$;

-- 步驟 6：手動測試 Trigger Function
-- 這會創建一個測試事件並觸發 Webhook
DO $$
DECLARE
  test_event_id UUID;
BEGIN
  -- 插入測試事件
  INSERT INTO outbox (
    aggregate_type,
    aggregate_id,
    event_type,
    payload
  ) VALUES (
    'booking',
    'test-webhook-' || gen_random_uuid()::TEXT,
    'updated',
    '{"test": true, "timestamp": "' || NOW()::TEXT || '"}'::jsonb
  ) RETURNING id INTO test_event_id;
  
  RAISE NOTICE '步驟 6：已創建測試事件 ID: %', test_event_id;
  RAISE NOTICE '請檢查 Edge Function 日誌，看是否收到 Webhook 請求';
END $$;

-- 步驟 7：總結診斷結果
SELECT 
  '步驟 7：診斷總結' as step,
  CASE 
    WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net')
    THEN '✅ pg_net 已啟用'
    ELSE '❌ pg_net 未啟用'
  END as pg_net_status,
  CASE 
    WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'outbox_webhook_trigger' AND tgenabled = 'O')
    THEN '✅ Webhook Trigger 已啟用'
    ELSE '❌ Webhook Trigger 未啟用或不存在'
  END as webhook_status,
  (SELECT COUNT(*) FROM outbox WHERE processed_at IS NULL) as unprocessed_events;

