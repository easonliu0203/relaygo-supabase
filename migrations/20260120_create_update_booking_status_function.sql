-- ============================================
-- 創建更新訂單狀態的 RPC 函數
-- ============================================
-- 目的：確保通過 Supabase SDK 更新訂單時也能觸發 PostgreSQL 觸發器
-- 問題：Supabase SDK 的 .update() 方法可能不會觸發觸發器
-- 解決：使用 RPC 函數執行原生 SQL UPDATE
-- ============================================

-- 創建更新訂單狀態的函數
CREATE OR REPLACE FUNCTION update_booking_status(
  p_booking_id UUID,
  p_status TEXT,
  p_completed_at TIMESTAMPTZ DEFAULT NULL,
  p_deposit_paid BOOLEAN DEFAULT NULL,
  p_tip_amount DECIMAL(10,2) DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  status VARCHAR(20),
  completed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  RAISE NOTICE '[Update Booking Status] 開始更新訂單: %', p_booking_id;
  RAISE NOTICE '[Update Booking Status] 新狀態: %', p_status;
  
  -- 執行 UPDATE（會觸發觸發器）
  UPDATE bookings
  SET
    status = p_status,
    completed_at = COALESCE(p_completed_at, bookings.completed_at),
    deposit_paid = COALESCE(p_deposit_paid, bookings.deposit_paid),
    tip_amount = COALESCE(p_tip_amount, bookings.tip_amount),
    updated_at = NOW()
  WHERE bookings.id = p_booking_id;
  
  RAISE NOTICE '[Update Booking Status] ✅ 訂單狀態已更新';
  
  -- 返回更新後的訂單資料
  RETURN QUERY
  SELECT 
    bookings.id,
    bookings.status,
    bookings.completed_at,
    bookings.updated_at
  FROM bookings
  WHERE bookings.id = p_booking_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 授予執行權限
GRANT EXECUTE ON FUNCTION update_booking_status TO authenticated;
GRANT EXECUTE ON FUNCTION update_booking_status TO service_role;

RAISE NOTICE '✅ update_booking_status 函數已創建';

