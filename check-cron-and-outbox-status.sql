-- 檢查 Cron Job 和 Outbox 狀態

-- 步驟 1：檢查 pg_cron 擴展是否啟用
SELECT 
  '步驟 1：檢查 pg_cron 擴展' as step,
  CASE 
    WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') 
    THEN '✅ pg_cron 已啟用'
    ELSE '❌ pg_cron 未啟用'
  END as status;

-- 步驟 2：檢查 Cron Job 是否存在且啟用
SELECT 
  '步驟 2：檢查 Cron Job' as step,
  jobid,
  jobname,
  schedule,
  active,
  CASE 
    WHEN active = true THEN '✅ Cron Job 已啟用'
    ELSE '❌ Cron Job 未啟用'
  END as status
FROM cron.job
WHERE jobname = 'sync-orders-to-firestore';

-- 步驟 3：檢查最近的 Cron Job 執行記錄
SELECT 
  '步驟 3：最近的 Cron Job 執行記錄' as step,
  jobid,
  runid,
  job_pid,
  database,
  username,
  command,
  status,
  return_message,
  start_time,
  end_time,
  EXTRACT(EPOCH FROM (end_time - start_time)) as duration_seconds
FROM cron.job_run_details
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'sync-orders-to-firestore')
ORDER BY start_time DESC
LIMIT 10;

-- 步驟 4：檢查訂單 096a8989-ea95-4b76-82c5-4f2b50154682 的 Outbox 事件
SELECT 
  '步驟 4：訂單 Outbox 事件' as step,
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
WHERE aggregate_id = '096a8989-ea95-4b76-82c5-4f2b50154682'
ORDER BY created_at DESC;

-- 步驟 5：檢查所有未處理的 Outbox 事件
SELECT 
  '步驟 5：未處理的 Outbox 事件' as step,
  COUNT(*) as unprocessed_count,
  MIN(created_at) as oldest_event,
  MAX(created_at) as newest_event,
  EXTRACT(EPOCH FROM (NOW() - MIN(created_at))) as oldest_event_age_seconds
FROM outbox
WHERE processed_at IS NULL;

-- 步驟 6：檢查最近處理的事件（看看 Cron Job 是否在工作）
SELECT 
  '步驟 6：最近處理的事件' as step,
  id,
  aggregate_id,
  event_type,
  created_at,
  processed_at,
  EXTRACT(EPOCH FROM (processed_at - created_at)) as delay_seconds
FROM outbox
WHERE processed_at IS NOT NULL
ORDER BY processed_at DESC
LIMIT 10;

-- 步驟 7：總結診斷結果
SELECT 
  '步驟 7：診斷總結' as step,
  CASE 
    WHEN EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'sync-orders-to-firestore' AND active = true)
    THEN '✅ Cron Job 已啟用'
    ELSE '❌ Cron Job 未啟用或不存在'
  END as cron_status,
  (SELECT COUNT(*) FROM outbox WHERE processed_at IS NULL) as unprocessed_events,
  CASE 
    WHEN (SELECT COUNT(*) FROM outbox WHERE processed_at IS NULL) > 0
    THEN '⚠️  有未處理事件，Cron Job 可能未正常工作'
    ELSE '✅ 所有事件已處理'
  END as recommendation;

