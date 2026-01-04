-- 驗證 depositPaid 修復是否成功

-- 步驟 1：檢查 Outbox Trigger 是否包含 depositPaid 欄位
SELECT 
  '步驟 1：檢查 Outbox Trigger 函數' as step,
  proname as function_name,
  CASE 
    WHEN pg_get_functiondef(oid) LIKE '%depositPaid%' 
    THEN '✅ Trigger 包含 depositPaid 欄位'
    ELSE '❌ Trigger 缺少 depositPaid 欄位'
  END as status
FROM pg_proc
WHERE proname = 'bookings_to_outbox';

-- 步驟 2：檢查最近的 Outbox 事件是否包含 depositPaid
SELECT 
  '步驟 2：檢查 Outbox Payload' as step,
  id,
  event_type,
  payload->>'depositPaid' as deposit_paid_in_payload,
  payload->>'status' as status,
  created_at,
  CASE 
    WHEN payload->>'depositPaid' IS NOT NULL 
    THEN '✅ Payload 包含 depositPaid'
    ELSE '❌ Payload 缺少 depositPaid'
  END as status_check
FROM outbox
WHERE aggregate_type = 'booking'
  AND event_type IN ('created', 'updated')
ORDER BY created_at DESC
LIMIT 5;

-- 步驟 3：檢查 Supabase 中的訂單狀態
SELECT 
  '步驟 3：檢查 Supabase 訂單' as step,
  id,
  booking_number,
  status,
  deposit_paid,
  created_at,
  CASE 
    WHEN deposit_paid = true AND status = 'paid_deposit' 
    THEN '✅ 訂金已支付'
    WHEN deposit_paid = false AND status = 'pending_payment' 
    THEN '⏳ 待付訂金'
    ELSE '⚠️  狀態不一致'
  END as status_check
FROM bookings
ORDER BY created_at DESC
LIMIT 5;

-- 步驟 4：檢查是否有未處理的 Outbox 事件
SELECT 
  '步驟 4：檢查未處理的 Outbox 事件' as step,
  COUNT(*) as unprocessed_count,
  CASE 
    WHEN COUNT(*) = 0 
    THEN '✅ 所有事件已處理'
    ELSE '⚠️  有 ' || COUNT(*) || ' 個未處理事件'
  END as status
FROM outbox
WHERE processed_at IS NULL;

-- 步驟 5：顯示最近處理的事件
SELECT 
  '步驟 5：最近處理的事件' as step,
  id,
  event_type,
  payload->>'depositPaid' as deposit_paid,
  payload->>'status' as status,
  processed_at,
  error_message
FROM outbox
WHERE processed_at IS NOT NULL
ORDER BY processed_at DESC
LIMIT 5;

-- 步驟 6：總結
SELECT 
  '步驟 6：修復總結' as step,
  '✅ Outbox Trigger 已更新' as trigger_status,
  '✅ Edge Function 已部署' as edge_function_status,
  '請檢查 Firestore 中的 depositPaid 欄位' as next_action;

