-- ============================================
-- 分潤計算觸發器
-- ============================================
-- 創建日期: 2026-01-18
-- 用途: 當訂單完成時自動計算並記錄推廣人分潤
-- ============================================

-- 創建分潤計算函數
CREATE OR REPLACE FUNCTION calculate_affiliate_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_referral RECORD;
  v_influencer RECORD;
  v_commission_amount DECIMAL(10,2);
  v_commission_type TEXT;
  v_commission_rate FLOAT;
  v_order_amount DECIMAL(10,2);
BEGIN
  -- 只在訂單狀態變更為 'completed' 時執行
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    
    RAISE NOTICE '[Commission Trigger] 訂單完成，開始計算分潤: booking_id=%', NEW.id;
    
    -- 獲取訂單金額
    v_order_amount := NEW.total_amount;
    
    -- 查詢該訂單客戶的推薦關係
    SELECT * INTO v_referral
    FROM referrals
    WHERE referee_id = NEW.customer_id
    LIMIT 1;
    
    IF v_referral IS NOT NULL THEN
      RAISE NOTICE '[Commission Trigger] 找到推薦關係: referrer_id=%, influencer_id=%', 
        v_referral.referrer_id, v_referral.influencer_id;
      
      -- 獲取推廣人的分潤設定
      SELECT * INTO v_influencer
      FROM influencers
      WHERE id = v_referral.influencer_id
      AND is_active = true
      LIMIT 1;
      
      IF v_influencer IS NOT NULL THEN
        RAISE NOTICE '[Commission Trigger] 推廣人資訊: name=%, commission_fixed=%, commission_percent=%', 
          v_influencer.name, v_influencer.commission_fixed, v_influencer.commission_percent;
        
        -- 計算分潤金額（優先級：固定金額 > 百分比）
        IF v_influencer.is_commission_fixed_active = true THEN
          v_commission_amount := v_influencer.commission_fixed;
          v_commission_type := 'fixed';
          v_commission_rate := NULL;
          RAISE NOTICE '[Commission Trigger] 使用固定金額分潤: %', v_commission_amount;
        ELSIF v_influencer.is_commission_percent_active = true THEN
          v_commission_rate := v_influencer.commission_percent;
          v_commission_amount := ROUND(v_order_amount * v_commission_rate / 100, 2);
          v_commission_type := 'percent';
          RAISE NOTICE '[Commission Trigger] 使用百分比分潤: %% = %', v_commission_rate, v_commission_amount;
        ELSE
          RAISE NOTICE '[Commission Trigger] 未啟用任何分潤方式，跳過';
          RETURN NEW;
        END IF;
        
        -- 檢查是否已經記錄過此訂單的分潤
        IF EXISTS (
          SELECT 1 FROM promo_code_usage
          WHERE booking_id = NEW.id
          AND commission_status IS NOT NULL
        ) THEN
          RAISE NOTICE '[Commission Trigger] 此訂單已記錄分潤，更新狀態';
          
          -- 更新現有記錄
          UPDATE promo_code_usage
          SET 
            commission_status = 'pending',
            commission_type = v_commission_type,
            commission_rate = v_commission_rate,
            commission_amount = v_commission_amount,
            order_amount = v_order_amount,
            referee_id = NEW.customer_id
          WHERE booking_id = NEW.id;
          
        ELSE
          RAISE NOTICE '[Commission Trigger] 新增分潤記錄';
          
          -- 新增分潤記錄到 promo_code_usage
          INSERT INTO promo_code_usage (
            influencer_id,
            booking_id,
            promo_code,
            original_price,
            discount_amount_applied,
            discount_percentage_applied,
            final_price,
            commission_amount,
            commission_status,
            commission_type,
            commission_rate,
            order_amount,
            referee_id
          ) VALUES (
            v_influencer.id,
            NEW.id,
            v_referral.promo_code,
            v_order_amount,
            0,
            0,
            v_order_amount,
            v_commission_amount,
            'pending',
            v_commission_type,
            v_commission_rate,
            v_order_amount,
            NEW.customer_id
          )
          ON CONFLICT (booking_id) DO UPDATE
          SET 
            commission_amount = v_commission_amount,
            commission_status = 'pending',
            commission_type = v_commission_type,
            commission_rate = v_commission_rate,
            order_amount = v_order_amount,
            referee_id = NEW.customer_id;
        END IF;
        
        -- 更新推廣人的累積收益
        UPDATE influencers
        SET total_earnings = total_earnings + v_commission_amount
        WHERE id = v_influencer.id;
        
        RAISE NOTICE '[Commission Trigger] ✅ 分潤計算完成: amount=%', v_commission_amount;
        
      ELSE
        RAISE NOTICE '[Commission Trigger] 推廣人不存在或未啟用';
      END IF;
      
    ELSE
      RAISE NOTICE '[Commission Trigger] 此訂單客戶無推薦關係';
    END IF;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 創建觸發器
DROP TRIGGER IF EXISTS trigger_calculate_commission ON bookings;
CREATE TRIGGER trigger_calculate_commission
AFTER UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION calculate_affiliate_commission();

-- 輸出完成訊息
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ 分潤計算觸發器創建完成！';
  RAISE NOTICE '========================================';
  RAISE NOTICE '觸發條件：訂單狀態更新為 completed';
  RAISE NOTICE '功能：自動計算並記錄推廣人分潤';
  RAISE NOTICE '========================================';
END $$;

