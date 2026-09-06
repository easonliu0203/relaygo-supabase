-- ============================================
-- 修復分潤觸發器：支持 trip_ended 狀態
-- ============================================
-- 創建日期: 2026-01-20
-- 問題: 
--   1. 觸發器只在訂單狀態變為 'completed' 時執行
--   2. 但實際流程中，GoMyPay 回調可能失敗，訂單停留在 'trip_ended'
--   3. 導致分潤記錄沒有被創建或更新
-- 修復:
--   1. 修改觸發器條件，同時支持 'trip_ended' 和 'completed' 狀態
--   2. 在 trip_ended 時創建 pending 狀態的分潤記錄
--   3. 在 completed 時更新為 completed 狀態並計算最終金額
-- ============================================

-- 1. 先更新 commission_status 約束（如果還沒執行過）
DO $$
BEGIN
  -- 刪除舊的 CHECK 約束
  ALTER TABLE promo_code_usage 
  DROP CONSTRAINT IF EXISTS promo_code_usage_commission_status_check;
  
  -- 添加新的 CHECK 約束，包含 'completed' 狀態
  ALTER TABLE promo_code_usage 
  ADD CONSTRAINT promo_code_usage_commission_status_check 
  CHECK (commission_status IN ('pending', 'paid', 'cancelled', 'completed'));
  
  RAISE NOTICE '✅ commission_status 約束已更新';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '⚠️  更新約束時發生錯誤: %', SQLERRM;
END $$;

-- 2. 修改分潤計算函數
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
  v_new_status TEXT;
BEGIN
  -- ✅ 修改：支持 trip_ended 和 completed 兩種狀態
  IF (NEW.status = 'trip_ended' AND (OLD.status IS NULL OR OLD.status NOT IN ('trip_ended', 'completed')))
     OR (NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed')) THEN
    
    RAISE NOTICE '[Commission Trigger] 訂單狀態變更: % -> %, 開始處理分潤', OLD.status, NEW.status;
    
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
          RAISE NOTICE '[Commission Trigger] 使用百分比分潤: rate=%, amount=%', v_commission_rate, v_commission_amount;
        ELSE
          RAISE NOTICE '[Commission Trigger] 未啟用任何分潤方式，跳過';
          RETURN NEW;
        END IF;
        
        -- ✅ 修改：根據訂單狀態決定分潤狀態
        IF NEW.status = 'trip_ended' THEN
          v_new_status := 'pending';  -- 行程結束但未完成支付，設為 pending
          RAISE NOTICE '[Commission Trigger] 訂單狀態為 trip_ended，分潤狀態設為 pending';
        ELSIF NEW.status = 'completed' THEN
          v_new_status := 'completed';  -- 訂單完成，設為 completed
          RAISE NOTICE '[Commission Trigger] 訂單狀態為 completed，分潤狀態設為 completed';
        END IF;
        
        -- 檢查是否已經有分潤記錄
        SELECT * INTO v_existing_record
        FROM promo_code_usage
        WHERE booking_id = NEW.id;
        
        IF v_existing_record IS NOT NULL THEN
          RAISE NOTICE '[Commission Trigger] 已有分潤記錄，更新狀態和金額';
          
          -- 更新現有記錄
          UPDATE promo_code_usage
          SET 
            commission_status = v_new_status,
            commission_type = v_commission_type,
            commission_rate = v_commission_rate,
            commission_amount = v_commission_amount,
            order_amount = v_order_amount,
            referee_id = NEW.customer_id
          WHERE booking_id = NEW.id;
          
          -- ✅ 只在狀態變為 completed 時更新累積收益
          IF v_new_status = 'completed' AND v_existing_record.commission_status != 'completed' THEN
            RAISE NOTICE '[Commission Trigger] 分潤狀態從 % 變為 completed，更新累積收益', v_existing_record.commission_status;
            
            -- 如果之前已經累加過，先減去舊金額
            IF v_existing_record.commission_amount IS NOT NULL AND v_existing_record.commission_amount > 0 THEN
              UPDATE influencers
              SET total_earnings = total_earnings - v_existing_record.commission_amount + v_commission_amount
              WHERE id = v_influencer.id;
            ELSE
              UPDATE influencers
              SET total_earnings = total_earnings + v_commission_amount
              WHERE id = v_influencer.id;
            END IF;
          END IF;
          
        ELSE
          RAISE NOTICE '[Commission Trigger] 新增分潤記錄';
          
          -- 新增分潤記錄
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
            v_new_status,
            v_commission_type,
            v_commission_rate,
            v_order_amount,
            NEW.customer_id
          );
          
          -- ✅ 只在狀態為 completed 時累加收益
          IF v_new_status = 'completed' THEN
            RAISE NOTICE '[Commission Trigger] 新記錄且狀態為 completed，累加收益';
            UPDATE influencers
            SET total_earnings = total_earnings + v_commission_amount
            WHERE id = v_influencer.id;
          END IF;
        END IF;
        
        RAISE NOTICE '[Commission Trigger] ✅ 分潤處理完成: amount=%, status=%', v_commission_amount, v_new_status;
        
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

-- 3. 輸出完成訊息
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ 分潤觸發器修復完成！';
  RAISE NOTICE '========================================';
  RAISE NOTICE '修改內容：';
  RAISE NOTICE '1. 支持 trip_ended 和 completed 兩種狀態';
  RAISE NOTICE '2. trip_ended 時創建 pending 狀態的分潤記錄';
  RAISE NOTICE '3. completed 時更新為 completed 狀態並累加收益';
  RAISE NOTICE '4. 防止重複累加累積收益';
  RAISE NOTICE '========================================';
END $$;

