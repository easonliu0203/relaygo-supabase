-- ============================================
-- 測試分潤觸發器
-- ============================================
-- 用途：驗證觸發器是否正確執行
-- 使用方法：在 Supabase SQL Editor 中執行
-- ============================================

-- 1. 檢查觸發器狀態
SELECT 
  tgname as trigger_name,
  CASE tgenabled
    WHEN 'O' THEN 'Enabled'
    WHEN 'D' THEN 'Disabled'
    ELSE 'Unknown'
  END as status,
  pg_get_triggerdef(oid) as definition
FROM pg_trigger
WHERE tgrelid = 'bookings'::regclass
  AND tgname LIKE '%commission%';

-- 2. 檢查推廣人設定
SELECT 
  id,
  name,
  commission_fixed,
  commission_percent,
  is_commission_fixed_active,
  is_commission_percent_active,
  is_active
FROM influencers
WHERE id = '61d72f11-0b75-4eb1-8dd9-c25893b84e09';

-- 3. 檢查推薦關係
SELECT 
  r.id,
  r.influencer_id,
  r.referee_id,
  r.promo_code,
  i.name as influencer_name
FROM referrals r
JOIN influencers i ON r.influencer_id = i.id
WHERE r.referee_id = 'aa5cf574-2394-4258-aceb-471fcf80f49c';

-- 4. 創建測試訂單（模擬）
-- 注意：這只是示例，實際測試應該通過 App 創建訂單

/*
DO $$
DECLARE
  v_test_booking_id UUID;
  v_test_customer_id UUID := 'aa5cf574-2394-4258-aceb-471fcf80f49c';
  v_test_influencer_id UUID := '61d72f11-0b75-4eb1-8dd9-c25893b84e09';
BEGIN
  -- 創建測試訂單
  INSERT INTO bookings (
    customer_id,
    influencer_id,
    promo_code,
    status,
    total_amount,
    booking_number,
    start_date,
    start_time,
    vehicle_type,
    pickup_location,
    base_price,
    deposit_amount
  ) VALUES (
    v_test_customer_id,
    v_test_influencer_id,
    'QQQ111',
    'pending_payment',
    2000.00,
    'TEST' || to_char(NOW(), 'YYYYMMDDHH24MISS'),
    CURRENT_DATE + INTERVAL '1 day',
    '09:00:00',
    'small',
    '測試地點',
    2000.00,
    600.00
  ) RETURNING id INTO v_test_booking_id;
  
  RAISE NOTICE '✅ 測試訂單已創建: %', v_test_booking_id;
  
  -- 創建分潤記錄（模擬訂單創建時的行為）
  INSERT INTO promo_code_usage (
    influencer_id,
    booking_id,
    promo_code,
    original_price,
    discount_amount_applied,
    final_price,
    commission_amount
  ) VALUES (
    v_test_influencer_id,
    v_test_booking_id,
    'QQQ111',
    3000.00,
    1000.00,
    2000.00,
    0.00
  );
  
  RAISE NOTICE '✅ 分潤記錄已創建';
  
  -- 等待一下
  PERFORM pg_sleep(1);
  
  -- 更新訂單狀態為 completed（觸發分潤計算）
  UPDATE bookings
  SET 
    status = 'completed',
    completed_at = NOW(),
    updated_at = NOW()
  WHERE id = v_test_booking_id;
  
  RAISE NOTICE '✅ 訂單狀態已更新為 completed';
  
  -- 檢查分潤記錄是否更新
  PERFORM pg_sleep(1);
  
  SELECT 
    commission_amount,
    commission_status,
    commission_type,
    commission_rate,
    order_amount
  FROM promo_code_usage
  WHERE booking_id = v_test_booking_id;
  
  RAISE NOTICE '✅ 測試完成，請檢查分潤記錄';
  
END $$;
*/

-- 5. 手動測試現有訂單
-- 將現有訂單狀態改為 trip_ended，然後再改回 completed

-- 步驟 1: 改為 trip_ended
/*
UPDATE bookings
SET status = 'trip_ended', updated_at = NOW()
WHERE id = '03a069a8-8869-481a-88a7-256af036a54b';
*/

-- 步驟 2: 改回 completed（觸發器應該執行）
/*
UPDATE bookings
SET status = 'completed', completed_at = NOW(), updated_at = NOW()
WHERE id = '03a069a8-8869-481a-88a7-256af036a54b';
*/

-- 步驟 3: 檢查分潤記錄
/*
SELECT 
  id,
  booking_id,
  commission_amount,
  commission_status,
  commission_type,
  commission_rate,
  order_amount,
  referee_id
FROM promo_code_usage
WHERE booking_id = '03a069a8-8869-481a-88a7-256af036a54b';
*/

-- 6. 檢查推廣人累積收益
SELECT 
  id,
  name,
  total_earnings,
  total_referrals
FROM influencers
WHERE id = '61d72f11-0b75-4eb1-8dd9-c25893b84e09';

-- 7. 檢查所有分潤記錄
SELECT 
  pcu.id,
  pcu.booking_id,
  b.booking_number,
  b.status as order_status,
  pcu.commission_amount,
  pcu.commission_status,
  pcu.order_amount,
  pcu.used_at
FROM promo_code_usage pcu
JOIN bookings b ON pcu.booking_id = b.id
WHERE pcu.influencer_id = '61d72f11-0b75-4eb1-8dd9-c25893b84e09'
ORDER BY pcu.used_at DESC;

