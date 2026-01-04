-- 診斷 Webhook 問題

-- 步驟 1：檢查所有 Trigger
SELECT 
  '步驟 1：所有 Trigger' as step,
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  CASE tgenabled
    WHEN 'O' THEN '✅ 已啟用'
    WHEN 'D' THEN '❌ 已禁用'
    ELSE '⚠️  未知'
  END as status,
  pg_get_triggerdef(oid) as definition
FROM pg_trigger
WHERE tgrelid::regclass::text IN ('bookings', 'outbox')
ORDER BY tgrelid::regclass, tgname;

-- 步驟 2：檢查訂單 dfbfb144-4e7a-4902-be7a-954ebbe58888 的詳細資訊
SELECT 
  '步驟 2：訂單詳細資訊' as step,
  id,
  booking_number,
  status,
  deposit_paid,
  created_at,
  updated_at
FROM bookings
WHERE id = 'dfbfb144-4e7a-4902-be7a-954ebbe58888';

-- 步驟 3：檢查該訂單的所有 Outbox 事件
SELECT 
  '步驟 3：訂單 Outbox 事件' as step,
  id,
  event_type,
  payload->>'status' as status,
  payload->>'depositPaid' as deposit_paid,
  created_at,
  processed_at,
  CASE 
    WHEN processed_at IS NULL THEN '❌ 未處理'
    ELSE '✅ 已處理 (' || EXTRACT(EPOCH FROM (processed_at - created_at))::INTEGER || ' 秒)'
  END as processing_status,
  retry_count,
  error_message
FROM outbox
WHERE aggregate_id = 'dfbfb144-4e7a-4902-be7a-954ebbe58888'
ORDER BY created_at DESC;

-- 步驟 4：檢查最近 10 個 Outbox 事件的處理情況
SELECT 
  '步驟 4：最近 10 個 Outbox 事件' as step,
  id,
  aggregate_id,
  event_type,
  created_at,
  processed_at,
  CASE 
    WHEN processed_at IS NULL THEN '❌ 未處理'
    ELSE '✅ 已處理 (' || EXTRACT(EPOCH FROM (processed_at - created_at))::INTEGER || ' 秒)'
  END as processing_status
FROM outbox
ORDER BY created_at DESC
LIMIT 10;

-- 步驟 5：檢查 pg_net 請求（如果表存在）
SELECT
  '步驟 5：pg_net 請求隊列' as step,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM information_schema.tables
      WHERE table_schema = 'net'
      AND table_name = 'http_request_queue'
    ) THEN '✅ pg_net 表存在'
    ELSE '❌ pg_net 表不存在'
  END as status;

-- 如果 pg_net 表存在，顯示最近的請求
-- 注意：這個查詢可能會失敗，因為表結構可能不同
-- SELECT * FROM net.http_request_queue ORDER BY id DESC LIMIT 10;

-- 步驟 6：檢查 Webhook Trigger Function 的定義
SELECT 
  '步驟 6：Webhook Trigger Function' as step,
  proname as function_name,
  CASE 
    WHEN pg_get_functiondef(oid) LIKE '%net.http_post%' THEN '✅ 包含 HTTP 請求'
    ELSE '❌ 不包含 HTTP 請求'
  END as has_http_request,
  pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname = 'trigger_sync_to_firestore';

-- 步驟 7：總結診斷結果
SELECT 
  '步驟 7：診斷總結' as step,
  (SELECT COUNT(*) FROM pg_trigger WHERE tgname = 'outbox_webhook_trigger' AND tgenabled = 'O') as webhook_trigger_count,
  (SELECT COUNT(*) FROM pg_trigger WHERE tgname = 'bookings_outbox_trigger' AND tgenabled = 'O') as bookings_trigger_count,
  (SELECT COUNT(*) FROM outbox WHERE aggregate_id = 'dfbfb144-4e7a-4902-be7a-954ebbe58888') as outbox_events_count,
  (SELECT COUNT(*) FROM outbox WHERE aggregate_id = 'dfbfb144-4e7a-4902-be7a-954ebbe58888' AND processed_at IS NULL) as unprocessed_events_count;

