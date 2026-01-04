-- ========================================
-- 診斷司機端「確認接單」按鈕不顯示問題
-- ========================================

-- 步驟 1：檢查最近的訂單（最近 10 筆）
SELECT 
    '步驟 1：檢查最近的訂單' AS "診斷步驟";

SELECT 
    id AS "訂單 ID",
    booking_number AS "訂單編號",
    status AS "Supabase 狀態",
    customer_id AS "客戶 ID",
    driver_id AS "司機 ID",
    created_at AS "創建時間",
    updated_at AS "更新時間",
    CASE 
        WHEN driver_id IS NULL THEN '❌ 未分配司機'
        WHEN status = 'matched' THEN '⚠️ 已派單（matched），需要司機確認'
        WHEN status = 'driver_confirmed' THEN '✅ 司機已確認'
        ELSE '📋 其他狀態'
    END AS "分析"
FROM bookings
ORDER BY created_at DESC
LIMIT 10;

-- 步驟 2：檢查已派單但司機尚未確認的訂單
SELECT 
    '步驟 2：檢查已派單但司機尚未確認的訂單' AS "診斷步驟";

SELECT 
    id AS "訂單 ID",
    booking_number AS "訂單編號",
    status AS "Supabase 狀態",
    driver_id AS "司機 ID",
    created_at AS "創建時間",
    updated_at AS "更新時間",
    '⚠️ 此訂單應該顯示「確認接單」按鈕' AS "說明"
FROM bookings
WHERE status = 'matched' 
  AND driver_id IS NOT NULL
ORDER BY created_at DESC;

-- 步驟 3：檢查 Outbox 記錄（確認是否已同步到 Firestore）
SELECT 
    '步驟 3：檢查 Outbox 記錄（確認是否已同步到 Firestore）' AS "診斷步驟";

SELECT 
    o.id AS "Outbox ID",
    o.booking_id AS "訂單 ID",
    b.booking_number AS "訂單編號",
    o.event_type AS "事件類型",
    o.processed AS "是否已處理",
    o.created_at AS "創建時間",
    o.processed_at AS "處理時間",
    CASE 
        WHEN o.processed = true THEN '✅ 已同步到 Firestore'
        ELSE '⚠️ 尚未同步到 Firestore'
    END AS "同步狀態"
FROM outbox o
LEFT JOIN bookings b ON o.booking_id = b.id
WHERE b.status = 'matched' 
  AND b.driver_id IS NOT NULL
ORDER BY o.created_at DESC
LIMIT 10;

-- 步驟 4：檢查狀態映射邏輯
SELECT 
    '步驟 4：檢查狀態映射邏輯' AS "診斷步驟";

SELECT 
    status AS "Supabase 狀態",
    CASE status
        WHEN 'pending_payment' THEN 'pending'
        WHEN 'paid_deposit' THEN 'pending'
        WHEN 'assigned' THEN 'awaitingDriver'
        WHEN 'matched' THEN 'awaitingDriver'
        WHEN 'driver_confirmed' THEN 'matched'
        WHEN 'driver_departed' THEN 'inProgress'
        WHEN 'driver_arrived' THEN 'inProgress'
        WHEN 'trip_started' THEN 'inProgress'
        WHEN 'trip_ended' THEN 'awaitingBalance'
        WHEN 'pending_balance' THEN 'awaitingBalance'
        WHEN 'in_progress' THEN 'inProgress'
        WHEN 'completed' THEN 'completed'
        WHEN 'cancelled' THEN 'cancelled'
        ELSE 'pending'
    END AS "預期 Firestore 狀態",
    COUNT(*) AS "訂單數量"
FROM bookings
GROUP BY status
ORDER BY COUNT(*) DESC;

-- 步驟 5：診斷結論
SELECT 
    '步驟 5：診斷結論' AS "診斷步驟";

SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM bookings 
            WHERE status = 'matched' AND driver_id IS NOT NULL
        ) THEN '⚠️ 發現已派單但司機尚未確認的訂單'
        ELSE '✅ 沒有發現已派單但司機尚未確認的訂單'
    END AS "結論",
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM bookings 
            WHERE status = 'matched' AND driver_id IS NOT NULL
        ) THEN '請檢查 Firestore 中的訂單狀態是否為 awaitingDriver'
        ELSE '所有訂單狀態正常'
    END AS "建議";

-- 步驟 6：修復建議
SELECT 
    '步驟 6：修復建議' AS "診斷步驟";

SELECT 
    '如果發現 Firestore 中的訂單狀態不是 awaitingDriver，請執行以下操作：' AS "修復步驟",
    '1. 檢查 Edge Function 是否已部署最新版本' AS "步驟 1",
    '2. 手動觸發 Firestore 同步（更新訂單的 updated_at 欄位）' AS "步驟 2",
    '3. 或者直接在 Firestore 中手動更新訂單狀態為 awaitingDriver' AS "步驟 3";

-- 步驟 7：手動觸發同步的 SQL 命令
SELECT 
    '步驟 7：手動觸發同步的 SQL 命令' AS "診斷步驟";

SELECT 
    'UPDATE bookings SET updated_at = NOW() WHERE status = ''matched'' AND driver_id IS NOT NULL;' AS "SQL 命令",
    '執行此命令將觸發 Supabase Trigger，重新創建 Outbox 記錄，並同步到 Firestore' AS "說明";

