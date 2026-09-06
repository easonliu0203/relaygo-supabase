-- ============================================
-- 更新 commission_status 約束，添加 'completed' 狀態
-- ============================================
-- 創建日期: 2026-01-19
-- 問題: commission_status 的 CHECK 約束只允許 'pending', 'paid', 'cancelled'
-- 修復: 添加 'completed' 狀態到允許的值列表中
-- ============================================

-- 1. 刪除舊的 CHECK 約束
DO $$
BEGIN
  -- 查找並刪除 commission_status 的 CHECK 約束
  ALTER TABLE promo_code_usage 
  DROP CONSTRAINT IF EXISTS promo_code_usage_commission_status_check;
  
  RAISE NOTICE '✅ 已刪除舊的 commission_status CHECK 約束';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '⚠️  刪除約束時發生錯誤（可能不存在）: %', SQLERRM;
END $$;

-- 2. 添加新的 CHECK 約束，包含 'completed' 狀態
ALTER TABLE promo_code_usage 
ADD CONSTRAINT promo_code_usage_commission_status_check 
CHECK (commission_status IN ('pending', 'paid', 'cancelled', 'completed'));

-- 3. 更新註解
COMMENT ON COLUMN promo_code_usage.commission_status IS '分潤狀態：pending（待發放）、completed（已完成）、paid（已支付）、cancelled（已取消）';

-- 4. 輸出完成訊息
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ commission_status 約束更新完成！';
  RAISE NOTICE '========================================';
  RAISE NOTICE '允許的狀態值：';
  RAISE NOTICE '  - pending: 待發放';
  RAISE NOTICE '  - completed: 已完成（訂單完成時自動設置）';
  RAISE NOTICE '  - paid: 已支付（手動發放後設置）';
  RAISE NOTICE '  - cancelled: 已取消';
  RAISE NOTICE '========================================';
END $$;

