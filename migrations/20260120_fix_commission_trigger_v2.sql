-- ============================================
-- 修復分潤觸發器 V2 - 增強錯誤處理和日誌
-- ============================================
-- 創建日期: 2026-01-20
-- 目的: 修復觸發器不執行的問題，添加詳細日誌
-- ============================================

-- 1. 刪除重複的觸發器
DROP TRIGGER IF EXISTS trigger_calculate_commission ON bookings;

-- 2. 創建或替換分潤計算函數（增強版）
CREATE OR REPLACE FUNCTION calculate_affiliate_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_referral RECORD;
  v_influencer RECORD;
  v_commission_amount DECIMAL(10,2);
  v_commission_type TEXT;
  v_commission_rate FLOAT;
  v_order_amount DECIMAL(10,2);
  v_existing_record RECORD;
BEGIN
  -- 記錄觸發器被調用
  RAISE NOTICE '[Commission Trigger] ========== 觸發器被調用 ==========';
  RAISE NOTICE '[Commission Trigger] Booking ID: %', NEW.id;
  RAISE NOTICE '[Commission Trigger] OLD.status: %, NEW.status: %', OLD.status, NEW.status;
  
  -- 只在訂單狀態變更為 'completed' 時執行
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    
    RAISE NOTICE '[Commission Trigger] ✅ 條件滿足：訂單狀態變更為 completed';
    
    -- 獲取訂單金額
    v_order_amount := NEW.total_amount;
    RAISE NOTICE '[Commission Trigger] 訂單金額: %', v_order_amount;
    
    -- 查詢該訂單客戶的推薦關係
    SELECT * INTO v_referral
    FROM referrals
    WHERE referee_id = NEW.customer_id
    LIMIT 1;
    
    IF v_referral IS NULL THEN
      RAISE NOTICE '[Commission Trigger] ⚠️  未找到推薦關係，customer_id: %', NEW.customer_id;
      RETURN NEW;
    END IF;
    
    RAISE NOTICE '[Commission Trigger] ✅ 找到推薦關係: influencer_id=%', v_referral.influencer_id;
    
    -- 獲取推廣人的分潤設定
    SELECT * INTO v_influencer
    FROM influencers
    WHERE id = v_referral.influencer_id
    AND is_active = true
    LIMIT 1;
    
    IF v_influencer IS NULL THEN
      RAISE NOTICE '[Commission Trigger] ⚠️  推廣人不存在或未啟用';
      RETURN NEW;
    END IF;
    
    RAISE NOTICE '[Commission Trigger] ✅ 推廣人: %, 分潤比率: %', v_influencer.name, v_influencer.commission_percent;
    
    -- 計算分潤金額（優先級：固定金額 > 百分比）
    IF v_influencer.is_commission_fixed_active = true THEN
      v_commission_amount := v_influencer.commission_fixed;
      v_commission_type := 'fixed';
      v_commission_rate := NULL;
      RAISE NOTICE '[Commission Trigger] 使用固定金額: %', v_commission_amount;
    ELSIF v_influencer.is_commission_percent_active = true THEN
      v_commission_rate := v_influencer.commission_percent;
      v_commission_amount := ROUND((v_order_amount * v_commission_rate / 100)::numeric, 2);
      v_commission_type := 'percent';
      RAISE NOTICE '[Commission Trigger] 使用百分比: %%, 計算金額: %', v_commission_rate, v_commission_amount;
    ELSE
      RAISE NOTICE '[Commission Trigger] ⚠️  未啟用任何分潤方式';
      RETURN NEW;
    END IF;
    
    -- 檢查是否已經有分潤記錄
    SELECT * INTO v_existing_record
    FROM promo_code_usage
    WHERE booking_id = NEW.id;
    
    IF v_existing_record IS NOT NULL THEN
      RAISE NOTICE '[Commission Trigger] 找到現有分潤記錄，ID: %', v_existing_record.id;
      RAISE NOTICE '[Commission Trigger] 現有狀態: %, 現有金額: %', v_existing_record.commission_status, v_existing_record.commission_amount;
      
      -- 更新現有記錄
      UPDATE promo_code_usage
      SET 
        commission_status = 'completed',
        commission_type = v_commission_type,
        commission_rate = v_commission_rate,
        commission_amount = v_commission_amount,
        order_amount = v_order_amount,
        referee_id = NEW.customer_id
      WHERE booking_id = NEW.id;
      
      RAISE NOTICE '[Commission Trigger] ✅ 分潤記錄已更新';
      
      -- 只在狀態從非 completed 變為 completed 時更新累積收益
      IF v_existing_record.commission_status IS NULL OR v_existing_record.commission_status != 'completed' THEN
        -- 如果之前已經有金額，先減去再加上新金額
        IF v_existing_record.commission_amount IS NOT NULL AND v_existing_record.commission_amount > 0 THEN
          UPDATE influencers
          SET total_earnings = total_earnings - v_existing_record.commission_amount + v_commission_amount
          WHERE id = v_influencer.id;
          RAISE NOTICE '[Commission Trigger] 更新累積收益: % - % + % = %', 
            v_influencer.total_earnings, v_existing_record.commission_amount, v_commission_amount,
            (v_influencer.total_earnings - v_existing_record.commission_amount + v_commission_amount);
        ELSE
          UPDATE influencers
          SET total_earnings = total_earnings + v_commission_amount
          WHERE id = v_influencer.id;
          RAISE NOTICE '[Commission Trigger] 累加收益: % + % = %', 
            v_influencer.total_earnings, v_commission_amount, (v_influencer.total_earnings + v_commission_amount);
        END IF;
      ELSE
        RAISE NOTICE '[Commission Trigger] ⚠️  分潤狀態已是 completed，不重複累加';
      END IF;
      
    ELSE
      RAISE NOTICE '[Commission Trigger] 未找到現有分潤記錄，創建新記錄';
      
      -- 創建新分潤記錄
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
        'completed',
        v_commission_type,
        v_commission_rate,
        v_order_amount,
        NEW.customer_id
      );
      
      RAISE NOTICE '[Commission Trigger] ✅ 新分潤記錄已創建';
      
      -- 累加收益
      UPDATE influencers
      SET total_earnings = total_earnings + v_commission_amount
      WHERE id = v_influencer.id;
      
      RAISE NOTICE '[Commission Trigger] 累加收益: +%', v_commission_amount;
    END IF;
    
    RAISE NOTICE '[Commission Trigger] ========== ✅ 分潤處理完成 ==========';
    
  ELSE
    RAISE NOTICE '[Commission Trigger] ⚠️  條件不滿足，跳過處理';
  END IF;
  
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '[Commission Trigger] ❌ 錯誤: %', SQLERRM;
    RAISE NOTICE '[Commission Trigger] 錯誤詳情: %', SQLSTATE;
    RETURN NEW;  -- 即使出錯也返回 NEW，避免阻塞訂單更新
END;
$$ LANGUAGE plpgsql;

-- 3. 重新創建觸發器
DROP TRIGGER IF EXISTS trigger_calculate_affiliate_commission ON bookings;

CREATE TRIGGER trigger_calculate_affiliate_commission
  AFTER UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION calculate_affiliate_commission();

-- 4. 輸出完成訊息
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ 分潤觸發器 V2 部署完成！';
  RAISE NOTICE '========================================';
  RAISE NOTICE '改進：';
  RAISE NOTICE '1. 刪除重複觸發器 trigger_calculate_commission';
  RAISE NOTICE '2. 添加詳細的 RAISE NOTICE 日誌';
  RAISE NOTICE '3. 添加 EXCEPTION 錯誤處理';
  RAISE NOTICE '4. 改進條件判斷邏輯';
  RAISE NOTICE '========================================';
END $$;

