-- ============================================
-- 修復分潤觸發器 V4 - 添加日誌記錄
-- ============================================
-- 問題：RAISE NOTICE 在 Supabase API 中看不到
-- 解決：使用日誌表記錄觸發器執行過程
-- ============================================

-- 1. 確保日誌表存在
CREATE TABLE IF NOT EXISTS trigger_debug_log (
  id SERIAL PRIMARY KEY,
  trigger_name TEXT,
  booking_id UUID,
  old_status TEXT,
  new_status TEXT,
  message TEXT,
  data JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 重新創建觸發器函數（添加日誌記錄）
CREATE OR REPLACE FUNCTION calculate_affiliate_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_referral RECORD;
  v_influencer RECORD;
  v_commission_amount DECIMAL(10,2);
  v_commission_type TEXT;
  v_commission_rate FLOAT;
  v_order_amount DECIMAL(10,2);
  v_existing_commission_amount DECIMAL(10,2);
  v_existing_commission_status TEXT;
BEGIN
  -- 記錄觸發器被調用
  INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message)
  VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, '觸發器被調用');
  
  -- 檢查狀態變更條件
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message)
    VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, '✅ 訂單狀態變更為 completed，開始處理分潤');
    
    v_order_amount := NEW.total_amount;
    
    -- 查找推薦關係
    SELECT * INTO v_referral FROM referrals WHERE referee_id = NEW.customer_id LIMIT 1;
    
    IF v_referral IS NULL THEN
      INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message, data)
      VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, '⚠️ 未找到推薦關係', 
              jsonb_build_object('customer_id', NEW.customer_id));
      RETURN NEW;
    END IF;
    
    INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message, data)
    VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, '✅ 找到推薦關係',
            jsonb_build_object('influencer_id', v_referral.influencer_id));
    
    -- 查找推廣人
    SELECT * INTO v_influencer FROM influencers WHERE id = v_referral.influencer_id AND is_active = true LIMIT 1;
    
    IF v_influencer IS NULL THEN
      INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message)
      VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, '⚠️ 推廣人不存在或未啟用');
      RETURN NEW;
    END IF;
    
    -- 計算分潤
    IF v_influencer.is_commission_fixed_active = true THEN
      v_commission_amount := v_influencer.commission_fixed;
      v_commission_type := 'fixed';
      v_commission_rate := NULL;
    ELSIF v_influencer.is_commission_percent_active = true THEN
      v_commission_rate := v_influencer.commission_percent;
      v_commission_amount := ROUND((v_order_amount * v_commission_rate / 100)::numeric, 2);
      v_commission_type := 'percent';
    ELSE
      INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message)
      VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, '⚠️ 未啟用任何分潤方式');
      RETURN NEW;
    END IF;
    
    INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message, data)
    VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, '✅ 分潤計算完成',
            jsonb_build_object('commission_amount', v_commission_amount, 'commission_type', v_commission_type, 
                              'commission_rate', v_commission_rate, 'order_amount', v_order_amount));
    
    -- 檢查現有記錄
    SELECT commission_amount, commission_status INTO v_existing_commission_amount, v_existing_commission_status 
    FROM promo_code_usage WHERE booking_id = NEW.id;
    
    -- UPDATE 現有的分潤記錄（不使用 INSERT，因為記錄已由後端創建）
    UPDATE promo_code_usage
    SET
      commission_status = 'completed',
      commission_type = v_commission_type,
      commission_rate = v_commission_rate,
      commission_amount = v_commission_amount,
      order_amount = v_order_amount,
      referee_id = NEW.customer_id
    WHERE booking_id = NEW.id;
    
    INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message)
    VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, '✅ 分潤記錄已更新（UPSERT）');
    
    -- 更新推廣人累積收益
    IF v_existing_commission_status IS NULL OR v_existing_commission_status != 'completed' THEN
      UPDATE influencers SET total_earnings = total_earnings + v_commission_amount WHERE id = v_influencer.id;
      INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message, data)
      VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, '✅ 累加收益',
              jsonb_build_object('added_amount', v_commission_amount));
    ELSE
      INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message)
      VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, '⚠️ 分潤狀態已是 completed，不重複累加');
    END IF;
  ELSE
    INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message)
    VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, 'ℹ️ 訂單狀態未變更為 completed，跳過處理');
  END IF;
  
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    INSERT INTO trigger_debug_log (trigger_name, booking_id, old_status, new_status, message, data)
    VALUES ('calculate_affiliate_commission', NEW.id, OLD.status, NEW.status, '❌ 錯誤',
            jsonb_build_object('error', SQLERRM));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. 重新創建觸發器
DROP TRIGGER IF EXISTS trigger_calculate_affiliate_commission ON bookings;
CREATE TRIGGER trigger_calculate_affiliate_commission
AFTER UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION calculate_affiliate_commission();

RAISE NOTICE '✅ 分潤觸發器 V4 已部署（含日誌記錄）';

