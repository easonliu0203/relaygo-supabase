-- ============================================
-- 部署分潤觸發器到生產環境
-- ============================================
-- 創建日期: 2026-01-20
-- 目的: 修復分潤系統，確保訂單完成時自動計算分潤
-- ============================================

-- 1. 更新 commission_status 約束
DO $$
BEGIN
  ALTER TABLE promo_code_usage 
  DROP CONSTRAINT IF EXISTS promo_code_usage_commission_status_check;
  
  ALTER TABLE promo_code_usage 
  ADD CONSTRAINT promo_code_usage_commission_status_check 
  CHECK (commission_status IN ('pending', 'paid', 'cancelled', 'completed'));
  
  RAISE NOTICE '✅ commission_status 約束已更新';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '⚠️  約束更新失敗: %', SQLERRM;
END $$;

-- 2. 創建或替換分潤計算函數
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
      RAISE NOTICE '[Commission Trigger] 找到推薦關係: influencer_id=%', v_referral.influencer_id;
      
      -- 獲取推廣人的分潤設定
      SELECT * INTO v_influencer
      FROM influencers
      WHERE id = v_referral.influencer_id
      AND is_active = true
      LIMIT 1;
      
      IF v_influencer IS NOT NULL THEN
        RAISE NOTICE '[Commission Trigger] 推廣人: %, 分潤比率: %', v_influencer.name, v_influencer.commission_percent;
        
        -- 計算分潤金額（優先級：固定金額 > 百分比）
        IF v_influencer.is_commission_fixed_active = true THEN
          v_commission_amount := v_influencer.commission_fixed;
          v_commission_type := 'fixed';
          v_commission_rate := NULL;
        ELSIF v_influencer.is_commission_percent_active = true THEN
          v_commission_rate := v_influencer.commission_percent;
          v_commission_amount := ROUND((v_order_amount * v_commission_rate / 100)::numeric, 2);
          v_commission_type := 'percent';
        ELSE
          RAISE NOTICE '[Commission Trigger] 未啟用任何分潤方式';
          RETURN NEW;
        END IF;
        
        RAISE NOTICE '[Commission Trigger] 計算分潤: 訂單金額=%, 分潤金額=%', v_order_amount, v_commission_amount;
        
        -- 檢查是否已經有分潤記錄
        SELECT * INTO v_existing_record
        FROM promo_code_usage
        WHERE booking_id = NEW.id;
        
        IF v_existing_record IS NOT NULL THEN
          RAISE NOTICE '[Commission Trigger] 更新現有分潤記錄';
          
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
          
          -- 只在狀態從非 completed 變為 completed 時更新累積收益
          IF v_existing_record.commission_status IS NULL OR v_existing_record.commission_status != 'completed' THEN
            -- 如果之前已經有金額，先減去再加上新金額
            IF v_existing_record.commission_amount IS NOT NULL AND v_existing_record.commission_amount > 0 THEN
              UPDATE influencers
              SET total_earnings = total_earnings - v_existing_record.commission_amount + v_commission_amount
              WHERE id = v_influencer.id;
              RAISE NOTICE '[Commission Trigger] 更新累積收益: 舊金額=%, 新金額=%', v_existing_record.commission_amount, v_commission_amount;
            ELSE
              UPDATE influencers
              SET total_earnings = total_earnings + v_commission_amount
              WHERE id = v_influencer.id;
              RAISE NOTICE '[Commission Trigger] 累加收益: +%', v_commission_amount;
            END IF;
          ELSE
            RAISE NOTICE '[Commission Trigger] 分潤狀態已是 completed，不重複累加';
          END IF;
          
        ELSE
          RAISE NOTICE '[Commission Trigger] 創建新分潤記錄';
          
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
          
          -- 累加收益
          UPDATE influencers
          SET total_earnings = total_earnings + v_commission_amount
          WHERE id = v_influencer.id;
          
          RAISE NOTICE '[Commission Trigger] 累加收益: +%', v_commission_amount;
        END IF;
        
        RAISE NOTICE '[Commission Trigger] ✅ 分潤處理完成';
        
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. 創建觸發器（如果不存在）
DROP TRIGGER IF EXISTS trigger_calculate_affiliate_commission ON bookings;

CREATE TRIGGER trigger_calculate_affiliate_commission
  AFTER UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION calculate_affiliate_commission();

-- 4. 輸出觸發器部署完成訊息
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ 分潤觸發器部署完成！';
  RAISE NOTICE '========================================';
END $$;

-- 5. 修復所有未處理的分潤記錄
DO $$
DECLARE
  v_record RECORD;
  v_commission_amount DECIMAL(10,2);
  v_count INTEGER := 0;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '修復未處理的分潤記錄...';
  RAISE NOTICE '========================================';

  FOR v_record IN
    SELECT
      pcu.id as usage_id,
      pcu.booking_id,
      pcu.influencer_id,
      pcu.commission_amount as old_amount,
      pcu.commission_status as old_status,
      b.total_amount,
      b.status as booking_status,
      i.commission_percent,
      i.commission_fixed,
      i.is_commission_percent_active,
      i.is_commission_fixed_active
    FROM promo_code_usage pcu
    JOIN bookings b ON pcu.booking_id = b.id
    JOIN influencers i ON pcu.influencer_id = i.id
    WHERE b.status = 'completed'
      AND (pcu.commission_status = 'pending' OR pcu.commission_status IS NULL OR pcu.commission_amount = 0)
  LOOP
    -- 計算分潤金額
    IF v_record.is_commission_fixed_active = true THEN
      v_commission_amount := v_record.commission_fixed;
    ELSIF v_record.is_commission_percent_active = true THEN
      v_commission_amount := ROUND((v_record.total_amount * v_record.commission_percent / 100)::numeric, 2);
    ELSE
      CONTINUE;
    END IF;

    RAISE NOTICE '修復訂單 %: 金額 % -> %', v_record.booking_id, v_record.old_amount, v_commission_amount;

    -- 更新分潤記錄
    UPDATE promo_code_usage
    SET commission_status = 'completed',
        commission_amount = v_commission_amount,
        commission_type = CASE WHEN v_record.is_commission_fixed_active THEN 'fixed' ELSE 'percent' END,
        commission_rate = v_record.commission_percent,
        order_amount = v_record.total_amount
    WHERE id = v_record.usage_id;

    -- 更新推廣人累積收益
    UPDATE influencers
    SET total_earnings = total_earnings + v_commission_amount - COALESCE(v_record.old_amount, 0)
    WHERE id = v_record.influencer_id;

    v_count := v_count + 1;
  END LOOP;

  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ 共修復 % 筆分潤記錄', v_count;
  RAISE NOTICE '========================================';
END $$;

-- 6. 驗證結果
SELECT
  '驗證結果' as 類型,
  pcu.booking_id,
  pcu.commission_status as 狀態,
  pcu.commission_amount as 分潤金額,
  pcu.order_amount as 訂單金額,
  i.total_earnings as 累積收益
FROM promo_code_usage pcu
JOIN influencers i ON pcu.influencer_id = i.id
ORDER BY pcu.used_at DESC
LIMIT 10;

