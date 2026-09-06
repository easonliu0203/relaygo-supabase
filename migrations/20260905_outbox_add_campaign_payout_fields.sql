-- ============================================================================
-- Firestore 同步：補上活動單固定給付欄位
-- 日期：2026-09-05
--
-- 司機 App 的訂單來自 Firestore，而 outbox trigger 是明確白名單，
-- 新增的 driver_payout_mode / driver_fixed_amount 不會自動帶過去。
-- 司機端要顯示「活動單・基本車資固定 NT$X」就需要這兩個欄位，
-- 另外帶上 revenue_share_driver_percentage 讓司機知道附加費是照幾 % 計算。
--
-- 注意：Edge Function supabase/functions/sync-to-firestore/index.ts 也是白名單，
-- 已一併補上對應欄位，兩邊要同步部署才會生效。
-- ============================================================================

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
