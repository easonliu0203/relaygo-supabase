-- ============================================
-- 修復分潤觸發器 V3 - 解決重複創建記錄問題
-- ============================================
-- 問題：觸發器沒有找到現有的 promo_code_usage 記錄，導致創建重複記錄
-- 解決方案：
-- 1. 使用 UPSERT 邏輯（INSERT ... ON CONFLICT ... DO UPDATE）
-- 2. 添加 UNIQUE 約束確保 booking_id 唯一
-- 3. 改進日誌輸出
-- ============================================

-- 1. 先添加 UNIQUE 約束（如果不存在）
DO $$ 
BEGIN
  -- 檢查約束是否已存在
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'promo_code_usage_booking_id_unique'
  ) THEN
    -- 先刪除可能存在的重複記錄（保留最早的）
    DELETE FROM promo_code_usage a
    USING promo_code_usage b
    WHERE a.booking_id = b.booking_id 
      AND a.used_at > b.used_at;
    
    -- 添加唯一約束
    ALTER TABLE promo_code_usage 
    ADD CONSTRAINT promo_code_usage_booking_id_unique 
    UNIQUE (booking_id);
    
    RAISE NOTICE '✅ 已添加 booking_id 唯一約束';
  ELSE
    RAISE NOTICE 'ℹ️  booking_id 唯一約束已存在';
  END IF;
END $$;

-- 2. 刪除舊的觸發器函數並重新創建
DROP TRIGGER IF EXISTS trigger_calculate_affiliate_commission ON bookings;
DROP TRIGGER IF EXISTS trigger_calculate_commission ON bookings;
DROP FUNCTION IF EXISTS calculate_affiliate_commission();

-- 3. 創建新的觸發器函數（使用 UPSERT）
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
  RAISE NOTICE '[Commission Trigger V3] ========== 觸發器被調用 ==========';
  RAISE NOTICE '[Commission Trigger V3] Booking ID: %', NEW.id;
  RAISE NOTICE '[Commission Trigger V3] OLD.status: %, NEW.status: %', OLD.status, NEW.status;
  
  -- 只在訂單狀態變更為 completed 時執行
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    RAISE NOTICE '[Commission Trigger V3] ✅ 訂單狀態變更為 completed，開始處理分潤';
    
    -- 獲取訂單金額
    v_order_amount := NEW.total_amount;
    RAISE NOTICE '[Commission Trigger V3] 訂單金額: %', v_order_amount;
    
    -- 查找推薦關係
    SELECT * INTO v_referral
    FROM referrals
    WHERE referee_id = NEW.customer_id
    LIMIT 1;
    
    IF v_referral IS NULL THEN
      RAISE NOTICE '[Commission Trigger V3] ⚠️  未找到推薦關係，客戶 ID: %', NEW.customer_id;
      RETURN NEW;
    END IF;
    
    RAISE NOTICE '[Commission Trigger V3] ✅ 找到推薦關係，推廣人 ID: %', v_referral.influencer_id;
    
    -- 獲取推廣人設定
    SELECT * INTO v_influencer
    FROM influencers
    WHERE id = v_referral.influencer_id
      AND is_active = true
    LIMIT 1;
    
    IF v_influencer IS NULL THEN
      RAISE NOTICE '[Commission Trigger V3] ⚠️  推廣人不存在或未啟用';
      RETURN NEW;
    END IF;
    
    RAISE NOTICE '[Commission Trigger V3] ✅ 推廣人: %, 分潤比率: %', v_influencer.name, v_influencer.commission_percent;
    
    -- 計算分潤金額（優先級：固定金額 > 百分比）
    IF v_influencer.is_commission_fixed_active = true THEN
      v_commission_amount := v_influencer.commission_fixed;
      v_commission_type := 'fixed';
      v_commission_rate := NULL;
      RAISE NOTICE '[Commission Trigger V3] 使用固定金額: %', v_commission_amount;
    ELSIF v_influencer.is_commission_percent_active = true THEN
      v_commission_rate := v_influencer.commission_percent;
      v_commission_amount := ROUND((v_order_amount * v_commission_rate / 100)::numeric, 2);
      v_commission_type := 'percent';
      RAISE NOTICE '[Commission Trigger V3] 使用百分比: %, 計算金額: %', v_commission_rate, v_commission_amount;
    ELSE
      RAISE NOTICE '[Commission Trigger V3] ⚠️  未啟用任何分潤方式';
      RETURN NEW;
    END IF;
    
    -- 獲取現有記錄的分潤狀態和金額（用於判斷是否需要更新累積收益）
    SELECT commission_amount, commission_status 
    INTO v_existing_commission_amount, v_existing_commission_status
    FROM promo_code_usage
    WHERE booking_id = NEW.id;
    
    RAISE NOTICE '[Commission Trigger V3] 現有記錄狀態: %, 金額: %', v_existing_commission_status, v_existing_commission_amount;
    
    -- 使用 INSERT ... ON CONFLICT ... DO UPDATE（UPSERT）
    -- 這樣可以確保不會創建重複記錄
    INSERT INTO promo_code_usage (
      influencer_id,
      booking_id,
      promo_code,
      commission_status,
      commission_type,
      commission_rate,
      commission_amount,
      order_amount,
      referee_id,
      used_at
    ) VALUES (
      v_influencer.id,
      NEW.id,
      NEW.promo_code,
      'completed',
      v_commission_type,
      v_commission_rate,
      v_commission_amount,
      v_order_amount,
      NEW.customer_id,
      NOW()
    )
    ON CONFLICT (booking_id) 
    DO UPDATE SET
      commission_status = 'completed',
      commission_type = EXCLUDED.commission_type,
      commission_rate = EXCLUDED.commission_rate,
      commission_amount = EXCLUDED.commission_amount,
      order_amount = EXCLUDED.order_amount,
      referee_id = EXCLUDED.referee_id;
    
    RAISE NOTICE '[Commission Trigger V3] ✅ 分潤記錄已更新（UPSERT）';
    
    -- 只在狀態從非 completed 變為 completed 時更新累積收益
    IF v_existing_commission_status IS NULL OR v_existing_commission_status != 'completed' THEN
      UPDATE influencers
      SET total_earnings = total_earnings + v_commission_amount
      WHERE id = v_influencer.id;
      
      RAISE NOTICE '[Commission Trigger V3] ✅ 累加收益: % + % = %', 
        v_influencer.total_earnings, v_commission_amount, (v_influencer.total_earnings + v_commission_amount);
    ELSE
      RAISE NOTICE '[Commission Trigger V3] ⚠️  分潤狀態已是 completed，不重複累加';
    END IF;
  ELSE
    RAISE NOTICE '[Commission Trigger V3] ℹ️  訂單狀態未變更為 completed，跳過處理';
  END IF;
  
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '[Commission Trigger V3] ❌ 錯誤: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. 創建觸發器
CREATE TRIGGER trigger_calculate_affiliate_commission
AFTER UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION calculate_affiliate_commission();

RAISE NOTICE '✅ 分潤觸發器 V3 部署完成';
RAISE NOTICE 'ℹ️  改進項目：';
RAISE NOTICE '  1. 添加 booking_id 唯一約束防止重複記錄';
RAISE NOTICE '  2. 使用 UPSERT (INSERT ... ON CONFLICT) 確保更新現有記錄';
RAISE NOTICE '  3. 改進日誌輸出便於調試';


