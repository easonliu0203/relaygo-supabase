-- ============================================================================
-- 小費：3% 硬編碼改為設定值，並統一由資料庫計算
-- 日期：2026-09-05
--
-- 問題
--   「小費扣 3% 金流費、平台不賺小費」這條規則沒有任何設定來源，
--   而是以 magic number 0.97 / 0.03 硬編碼在 7 個地方、跨 3 個 codebase：
--     web-admin/src/app/api/admin/drivers/[id]/route.ts（2 處）
--     mobile driver_earnings_page / driver_order_detail_page（2 處）
--     mobile driver_statistics_provider / earnings_service
--   而且 4 支司機收入 RPC（get_driver_earnings 等）完全不含小費，
--   司機詳情頁卻會加，造成同一位司機在不同畫面看到不同收入。
--   mobile earnings_service.dart 更是自己算一套（硬編碼平台 25%
--   + 訂單促成費 NT$500 + 小費 3%），完全繞過 revenue_share_configs，
--   且那筆 NT$500 促成費資料庫從未記錄（acquisition_fee_snapshot 一直是 0）。
--
-- 作法
--   費率存進 system_settings.tip_payment_fee，記錄小費當下鎖進訂單快照
--   （tip_fee_percentage），之後調整設定不影響已成立的訂單。
--   trigger 計算 tip_after_fee 並「併入 driver_earning」，
--   讓 driver_earning 成為司機收入的唯一數字：
--     - 4 支 RPC 不必修改即自動包含小費
--     - 顯示端一律不得再自行加小費或乘 0.97
--   平台完全不抽小費：platform_fee 不含小費，3% 是金流商手續費。
--   現金小費不經公司金流，由後端寫入費率 0。
-- ============================================================================

-- 1. 小費金流手續費率設定（原本硬編碼在 7 處的 3%）
INSERT INTO system_settings (key, value)
VALUES ('tip_payment_fee', jsonb_build_object(
  'percent', 3,
  'description', '小費金流手續費率％。平台不從小費抽成，此比例是金流商手續費。現金小費不經金流，費率為 0。',
  'updated_at', now()
))
ON CONFLICT (key) DO NOTHING;

-- 2. 訂單端快照
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS tip_fee_percentage NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS tip_after_fee      NUMERIC(10,2) DEFAULT 0;

COMMENT ON COLUMN bookings.tip_fee_percentage IS '這筆小費適用的金流手續費率％快照。記錄小費當下鎖定，現金為 0。';
COMMENT ON COLUMN bookings.tip_after_fee      IS '司機實得小費 = tip_amount × (1 - tip_fee_percentage/100)，已包含在 driver_earning 內';

SELECT key, value FROM system_settings WHERE key = 'tip_payment_fee';

CREATE OR REPLACE FUNCTION calculate_booking_financials()
RETURNS TRIGGER AS $fn$
DECLARE
  v_revenue_share_settings JSONB;
  v_revenue_config RECORD;
  v_company_percentage DECIMAL(5,2);
  v_driver_percentage DECIMAL(5,2);
  v_has_promo_code BOOLEAN;
  v_lookup_has_promo BOOLEAN;
  v_influencer_commission DECIMAL(10,2);
  v_influencer_record RECORD;
  v_commission_type TEXT;
  v_commission_rate DECIMAL(5,2);
  v_commission_fixed DECIMAL(10,2);
  v_service_type TEXT;
  v_payout_mode TEXT;
  v_discounted_base DECIMAL(10,2);
  v_surcharge DECIMAL(10,2);
  v_tip_fee_pct DECIMAL(5,2);
  v_tip_after_fee DECIMAL(10,2);
BEGIN
  v_has_promo_code := (NEW.promo_code IS NOT NULL AND NEW.promo_code != '');
  v_service_type := COALESCE(NEW.service_type, 'charter');

  -- ==========================================================================
  -- A. 司機給付模式快照（活動單固定給付 / 一般單照比例）
  -- ==========================================================================
  IF TG_OP = 'UPDATE' AND OLD.revenue_share_driver_percentage IS NOT NULL THEN
    NEW.driver_payout_mode  := OLD.driver_payout_mode;
    NEW.driver_fixed_amount := OLD.driver_fixed_amount;
  END IF;
  v_payout_mode := COALESCE(NEW.driver_payout_mode, 'percent');

  -- ==========================================================================
  -- B. 分潤比例
  --    唯一真實來源 = revenue_share_configs（後台「系統設定 → 分成設定」頁）
  --    建單當下寫快照，之後永遠沿用，改設定不會竄改歷史訂單
  -- ==========================================================================
  IF TG_OP = 'UPDATE' AND OLD.revenue_share_driver_percentage IS NOT NULL THEN
    NEW.revenue_share_company_percentage := OLD.revenue_share_company_percentage;
    NEW.revenue_share_driver_percentage  := OLD.revenue_share_driver_percentage;
    NEW.revenue_share_config_id          := OLD.revenue_share_config_id;
    NEW.revenue_share_locked_at          := OLD.revenue_share_locked_at;

    v_company_percentage := OLD.revenue_share_company_percentage;
    v_driver_percentage  := OLD.revenue_share_driver_percentage;
  ELSE
    -- 活動單（固定給付）沒有推廣人抽佣，附加費一律用「未使用優惠碼」的比例，
    -- 否則司機會平白少 5%，而那 5% 沒有任何人領走。
    v_lookup_has_promo := (v_has_promo_code AND v_payout_mode <> 'fixed');

    SELECT * INTO v_revenue_config
    FROM get_revenue_share_config(
      COALESCE(NEW.country, 'TW'), NULL, v_service_type, v_lookup_has_promo
    );

    IF v_revenue_config.driver_percentage IS NOT NULL THEN
      v_company_percentage := v_revenue_config.company_percentage;
      v_driver_percentage  := v_revenue_config.driver_percentage;
      NEW.revenue_share_config_id := v_revenue_config.id;
    ELSE
      NEW.revenue_share_config_id := NULL;
      RAISE WARNING '[Revenue Share] 設定表查無資料，改用 system_settings: country=%, service=%, promo=%',
        NEW.country, v_service_type, v_lookup_has_promo;

      IF v_lookup_has_promo THEN
        SELECT value INTO v_revenue_share_settings FROM system_settings WHERE key = 'revenue_share_with_promo' LIMIT 1;
        v_company_percentage := COALESCE((v_revenue_share_settings->>'company_base_percentage')::DECIMAL, 30);
        v_driver_percentage  := COALESCE((v_revenue_share_settings->>'driver_percentage')::DECIMAL, 70);
      ELSE
        SELECT value INTO v_revenue_share_settings FROM system_settings WHERE key = 'revenue_share_no_promo' LIMIT 1;
        v_company_percentage := COALESCE((v_revenue_share_settings->>'company_percentage')::DECIMAL, 25);
        v_driver_percentage  := COALESCE((v_revenue_share_settings->>'driver_percentage')::DECIMAL, 75);
      END IF;
    END IF;

    NEW.revenue_share_company_percentage := v_company_percentage;
    NEW.revenue_share_driver_percentage  := v_driver_percentage;
    NEW.revenue_share_locked_at          := now();
  END IF;

  -- ==========================================================================
  -- C. 推廣佣金：費率鎖快照，金額隨 total_amount 連動
  -- ==========================================================================
  IF NEW.influencer_id IS NOT NULL THEN
    IF TG_OP = 'UPDATE' AND OLD.influencer_commission_type IS NOT NULL THEN
      v_commission_type  := OLD.influencer_commission_type;
      v_commission_rate  := COALESCE(OLD.influencer_commission_rate, 0);
      v_commission_fixed := COALESCE(OLD.influencer_commission_fixed, 0);
    ELSE
      SELECT commission_fixed, commission_percent, commission_type,
             commission_percent_charter, commission_percent_instant_ride,
             commission_percent_airport_transfer,
             is_commission_fixed_active, is_commission_percent_active
      INTO v_influencer_record
      FROM influencers WHERE id = NEW.influencer_id LIMIT 1;

      IF v_influencer_record.is_commission_fixed_active = true THEN
        v_commission_type  := 'fixed';
        v_commission_fixed := COALESCE(v_influencer_record.commission_fixed, 0);
        v_commission_rate  := 0;
      ELSIF v_influencer_record.is_commission_percent_active = true THEN
        v_commission_type := 'percent';
        IF v_influencer_record.commission_type = 'by_service_type' THEN
          v_commission_rate := CASE v_service_type
            WHEN 'charter'          THEN COALESCE(v_influencer_record.commission_percent_charter,          v_influencer_record.commission_percent, 0)
            WHEN 'instant_ride'     THEN COALESCE(v_influencer_record.commission_percent_instant_ride,     v_influencer_record.commission_percent, 0)
            WHEN 'airport_transfer' THEN COALESCE(v_influencer_record.commission_percent_airport_transfer, v_influencer_record.commission_percent, 0)
            ELSE COALESCE(v_influencer_record.commission_percent, 0)
          END;
        ELSE
          v_commission_rate := COALESCE(v_influencer_record.commission_percent, 0);
        END IF;
        v_commission_fixed := 0;
      ELSE
        v_commission_type  := 'none';
        v_commission_rate  := 0;
        v_commission_fixed := 0;
      END IF;
    END IF;

    v_influencer_commission := CASE v_commission_type
      WHEN 'fixed'   THEN v_commission_fixed
      WHEN 'percent' THEN ROUND((COALESCE(NEW.total_amount, 0) * v_commission_rate / 100)::numeric, 2)
      ELSE 0
    END;

    NEW.influencer_commission_type  := v_commission_type;
    NEW.influencer_commission_rate  := v_commission_rate;
    NEW.influencer_commission_fixed := v_commission_fixed;
    NEW.influencer_commission       := v_influencer_commission;
  ELSE
    NEW.influencer_commission_type  := NULL;
    NEW.influencer_commission_rate  := 0;
    NEW.influencer_commission_fixed := 0;
    NEW.influencer_commission       := 0;
    v_influencer_commission := 0;
  END IF;

  -- ==========================================================================
  -- D. 小費
  --    平台完全不抽小費；司機拿扣除金流手續費後的淨額。
  --    費率來自 system_settings.tip_payment_fee，記錄小費當下鎖進訂單快照，
  --    之後調整設定不影響已成立的訂單。
  --    現金小費不經金流，由後端寫入費率 0。
  -- ==========================================================================
  IF TG_OP = 'UPDATE' AND OLD.tip_fee_percentage IS NOT NULL THEN
    -- 已鎖定，永不變動
    NEW.tip_fee_percentage := OLD.tip_fee_percentage;
  ELSIF NEW.tip_fee_percentage IS NULL AND COALESCE(NEW.tip_amount, 0) > 0 THEN
    -- 後端未指定費率時，取當下設定值並鎖定
    SELECT COALESCE((value->>'percent')::DECIMAL, 3)
    INTO v_tip_fee_pct
    FROM system_settings WHERE key = 'tip_payment_fee' LIMIT 1;
    NEW.tip_fee_percentage := COALESCE(v_tip_fee_pct, 3);
  END IF;

  v_tip_after_fee := ROUND((COALESCE(NEW.tip_amount, 0)
                            * (1 - COALESCE(NEW.tip_fee_percentage, 0) / 100))::numeric, 2);
  NEW.tip_after_fee := v_tip_after_fee;

  -- ==========================================================================
  -- E. 金額結算
  -- ==========================================================================
  IF v_payout_mode = 'fixed' THEN
    -- 活動單：基本車資給固定額，其餘（跨區費、超時費等附加費）照比例
    -- 折後基本車資 = base_price - discount_amount
    --   活動碼的折扣只作用在基本車資，故 discount_amount 即基本車資的折讓
    v_discounted_base := GREATEST(COALESCE(NEW.base_price, 0) - COALESCE(NEW.discount_amount, 0), 0);
    v_surcharge       := GREATEST(COALESCE(NEW.total_amount, 0) - v_discounted_base, 0);

    NEW.driver_earning := ROUND((COALESCE(NEW.driver_fixed_amount, 0)
                                 + v_surcharge * v_driver_percentage / 100)::numeric, 2);
    NEW.platform_fee   := ROUND((COALESCE(NEW.total_amount, 0) - NEW.driver_earning)::numeric, 2);
    NEW.driver_earning := NEW.driver_earning + v_tip_after_fee;
  ELSE
    NEW.driver_earning := ROUND((COALESCE(NEW.total_amount, 0) * v_driver_percentage  / 100)::numeric, 2)
                          + v_tip_after_fee;
    NEW.platform_fee   := ROUND((COALESCE(NEW.total_amount, 0) * v_company_percentage / 100)::numeric, 2);
  END IF;

  -- 推廣佣金從公司那一份內扣，司機不受影響
  IF v_influencer_commission > 0 AND v_has_promo_code THEN
    NEW.platform_fee := NEW.platform_fee - v_influencer_commission;
  END IF;

  -- 保險絲：固定給付設得太高會讓平台倒貼，直接擋下而不是默默虧錢
  IF v_payout_mode = 'fixed' AND NEW.platform_fee < 0 THEN
    RAISE EXCEPTION '[分潤] 活動單平台留存為負數（總額 %, 司機 %, 平台 %），請調低司機固定給付額',
      NEW.total_amount, NEW.driver_earning, NEW.platform_fee;
  END IF;

  IF NEW.status = 'completed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'completed') THEN
    NEW.completed_at := NOW();
  END IF;

  IF NEW.actual_end_time IS NOT NULL AND NEW.completed_at IS NULL THEN
    NEW.completed_at := NEW.actual_end_time;
  END IF;

  RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bookings_to_outbox()
RETURNS TRIGGER AS $fn$
DECLARE
  customer_firebase_uid VARCHAR(128);
  customer_first_name VARCHAR(100);
  customer_last_name VARCHAR(100);
  customer_phone VARCHAR(20);
  driver_firebase_uid VARCHAR(128);
  driver_first_name VARCHAR(100);
  driver_last_name VARCHAR(100);
  driver_phone VARCHAR(20);
  driver_vehicle_plate VARCHAR(20);
  driver_vehicle_model VARCHAR(100);
  driver_rating DECIMAL(3,2);
  payload_part1 JSONB;
  payload_part2 JSONB;
  payload_part3 JSONB;
  final_payload JSONB;
BEGIN
  -- 獲取客戶資訊
  SELECT 
    u.firebase_uid,
    up.first_name,
    up.last_name,
    up.phone
  INTO 
    customer_firebase_uid,
    customer_first_name,
    customer_last_name,
    customer_phone
  FROM users u
  LEFT JOIN user_profiles up ON u.id = up.user_id
  WHERE u.id = NEW.customer_id;

  -- 獲取司機資訊（如果已分配）
  IF NEW.driver_id IS NOT NULL THEN
    SELECT 
      u.firebase_uid,
      up.first_name,
      up.last_name,
      up.phone,
      d.vehicle_plate,
      d.vehicle_model,
      COALESCE(d.average_rating, d.rating)
    INTO 
      driver_firebase_uid,
      driver_first_name,
      driver_last_name,
      driver_phone,
      driver_vehicle_plate,
      driver_vehicle_model,
      driver_rating
    FROM users u
    LEFT JOIN user_profiles up ON u.id = up.user_id
    LEFT JOIN drivers d ON u.id = d.user_id
    WHERE u.id = NEW.driver_id;
  END IF;

  -- 第一部分：基本資訊和客戶/司機資訊（20 pairs）
  payload_part1 := jsonb_build_object(
    'id', NEW.id,
    'bookingNumber', NEW.booking_number,
    'customerId', customer_firebase_uid,
    'customerName', CASE 
      WHEN customer_first_name IS NOT NULL OR customer_last_name IS NOT NULL 
      THEN TRIM(CONCAT(customer_first_name, ' ', customer_last_name))
      ELSE NULL
    END,
    'customerPhone', customer_phone,
    'driverId', driver_firebase_uid,
    'driverName', CASE 
      WHEN driver_first_name IS NOT NULL OR driver_last_name IS NOT NULL 
      THEN TRIM(CONCAT(driver_first_name, ' ', driver_last_name))
      ELSE NULL
    END,
    'driverPhone', driver_phone,
    'driverVehiclePlate', driver_vehicle_plate,
    'driverVehicleModel', driver_vehicle_model,
    'driverRating', driver_rating,
    'status', NEW.status,
    'pickupAddress', NEW.pickup_location,
    'destination', NEW.destination,
    'startDate', NEW.start_date,
    'startTime', NEW.start_time,
    'durationHours', NEW.duration_hours,
    'vehicleType', NEW.vehicle_type,
    'passengerCount', NEW.passenger_count,
    'luggageCount', NEW.luggage_count
  );

  -- 第二部分：價格和費用資訊（20 pairs）
  payload_part2 := jsonb_build_object(
    'specialRequirements', NEW.special_requirements,
    'requiresForeignLanguage', NEW.requires_foreign_language,
    'basePrice', NEW.base_price,
    'foreignLanguageSurcharge', NEW.foreign_language_surcharge,
    'overtimeFee', NEW.overtime_fee,
    'tipAmount', NEW.tip_amount,
    'tipAfterFee', COALESCE(NEW.tip_after_fee, 0),
    'tipFeePercentage', COALESCE(NEW.tip_fee_percentage, 0),
    'totalAmount', NEW.total_amount,
    'depositAmount', NEW.deposit_amount,
    'depositPaid', COALESCE(NEW.deposit_paid, false),
    'promoCode', NEW.promo_code,
    'influencerId', NEW.influencer_id,
    'influencerCommission', NEW.influencer_commission,
    'originalPrice', NEW.original_price,
    'discountAmount', NEW.discount_amount,
    'finalPrice', NEW.final_price,
    'taxId', NEW.tax_id,
    'tourPackageId', NEW.tour_package_id,
    'tourPackageName', NEW.tour_package_name,
    'createdAt', NEW.created_at,
    'updatedAt', NEW.updated_at
  );

  -- 第三部分：時間戳、佣金和位置資訊（11 pairs）
  payload_part3 := jsonb_build_object(
    'actualStartTime', NEW.actual_start_time,
    'actualEndTime', NEW.actual_end_time,
    'completedAt', NEW.completed_at,
    'platformFee', COALESCE(NEW.platform_fee, 0),
    'driverEarning', COALESCE(NEW.driver_earning, 0),
    'driverPayoutMode', COALESCE(NEW.driver_payout_mode, 'percent'),
    'driverFixedAmount', COALESCE(NEW.driver_fixed_amount, 0),
    'driverSharePercentage', COALESCE(NEW.revenue_share_driver_percentage, 0),
    'driverReferralCommission', COALESCE(NEW.driver_referral_commission, 0),
    'driverReferrerId', NEW.driver_referrer_id,
    'country', COALESCE(NEW.country, 'TW'),
    'serviceType', COALESCE(NEW.service_type, 'charter'),
    'pickupLocation', CASE 
      WHEN NEW.pickup_latitude IS NOT NULL AND NEW.pickup_longitude IS NOT NULL 
      THEN jsonb_build_object(
        'latitude', NEW.pickup_latitude,
        'longitude', NEW.pickup_longitude
      )
      ELSE NULL
    END,
    'dropoffLocation', CASE 
      WHEN NEW.dropoff_latitude IS NOT NULL AND NEW.dropoff_longitude IS NOT NULL 
      THEN jsonb_build_object(
        'latitude', NEW.dropoff_latitude,
        'longitude', NEW.dropoff_longitude
      )
      ELSE NULL
    END
  );

  -- 合併三個部分
  final_payload := payload_part1 || payload_part2 || payload_part3;

  -- 插入 outbox 事件
  INSERT INTO outbox (
    aggregate_type,
    aggregate_id,
    event_type,
    payload
  ) VALUES (
    'booking',
    NEW.id::TEXT,
    CASE
      WHEN TG_OP = 'INSERT' THEN 'created'
      WHEN TG_OP = 'UPDATE' THEN 'updated'
      WHEN TG_OP = 'DELETE' THEN 'deleted'
    END,
    final_payload
  );
  
  RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;


-- ----------------------------------------------------------------------------
-- driver_earning 現在包含小費淨額，但 total_revenue 用的是 total_amount（不含小費），
-- 有小費時會出現「司機 + 平台 > 總營收」。
--
-- 改為以「客人實付」為總營收，並列出金流手續費，讓三者可以對帳：
--   total_revenue = driver_earnings + platform_fee + payment_fee
CREATE OR REPLACE FUNCTION get_daily_earnings_summary(
  p_start_date DATE,
  p_end_date DATE
)
RETURNS JSON AS $fn$
DECLARE
  v_result JSON;
BEGIN
  SELECT json_agg(daily_data ORDER BY date)
  INTO v_result
  FROM (
    SELECT
      DATE(completed_at) as date,
      -- 客人實付 = 車資總額 + 小費
      SUM(COALESCE(total_amount, 0) + COALESCE(tip_amount, 0)) as total_revenue,
      -- 車資部分的營收（不含小費），供需要區分時使用
      SUM(COALESCE(total_amount, 0)) as fare_revenue,
      -- 已含小費淨額
      SUM(COALESCE(driver_earning, 0)) as driver_earnings,
      -- 不含小費，平台不從小費抽成
      SUM(COALESCE(platform_fee, 0)) as platform_fee,
      -- 金流商收走的小費手續費
      SUM(COALESCE(tip_amount, 0) - COALESCE(tip_after_fee, 0)) as payment_fee,
      SUM(COALESCE(tip_amount, 0)) as tip_amount,
      COUNT(*) as orders,
      COUNT(DISTINCT driver_id) as drivers_count
    FROM bookings
    WHERE status = 'completed'
      AND completed_at IS NOT NULL
      AND DATE(completed_at) BETWEEN p_start_date AND p_end_date
    GROUP BY DATE(completed_at)
    ORDER BY DATE(completed_at)
  ) daily_data;

  RETURN COALESCE(v_result, '[]'::json);
END;
$fn$ LANGUAGE plpgsql;
