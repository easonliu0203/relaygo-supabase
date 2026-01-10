-- Migration: 添加優惠碼和統編欄位到 outbox trigger
-- Date: 2026-01-10
-- Description: 更新 bookings_to_outbox() trigger function，添加優惠碼相關欄位到 payload

-- 重新創建 trigger function，添加優惠碼和統編欄位
CREATE OR REPLACE FUNCTION bookings_to_outbox()
RETURNS TRIGGER AS $$
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
      dv.vehicle_plate,
      dv.vehicle_model,
      dp.rating
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
    LEFT JOIN driver_profiles dp ON u.id = dp.user_id
    LEFT JOIN driver_vehicles dv ON u.id = dv.driver_id AND dv.is_primary = true
    WHERE u.id = NEW.driver_id;
  END IF;

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
    jsonb_build_object(
      'id', NEW.id,
      'bookingNumber', NEW.booking_number,
      
      -- 客戶資訊
      'customerId', customer_firebase_uid,
      'customerName', CASE 
        WHEN customer_first_name IS NOT NULL OR customer_last_name IS NOT NULL 
        THEN TRIM(CONCAT(customer_first_name, ' ', customer_last_name))
        ELSE NULL
      END,
      'customerPhone', customer_phone,
      
      -- 司機資訊
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
      
      -- 訂單基本資訊
      'status', NEW.status,
      'pickupAddress', NEW.pickup_location,
      'destination', NEW.destination,
      'startDate', NEW.start_date,
      'startTime', NEW.start_time,
      'durationHours', NEW.duration_hours,
      'vehicleType', NEW.vehicle_type,
      'passengerCount', NEW.passenger_count,
      'luggageCount', NEW.luggage_count,
      'specialRequirements', NEW.special_requirements,
      'requiresForeignLanguage', NEW.requires_foreign_language,
      
      -- 費用資訊
      'basePrice', NEW.base_price,
      'foreignLanguageSurcharge', NEW.foreign_language_surcharge,
      'overtimeFee', NEW.overtime_fee,
      'tipAmount', NEW.tip_amount,
      'totalAmount', NEW.total_amount,
      'depositAmount', NEW.deposit_amount,
      'depositPaid', COALESCE(NEW.deposit_paid, false),
      
      -- ✅ 新增：優惠碼相關欄位
      'promoCode', NEW.promo_code,
      'influencerId', NEW.influencer_id,
      'influencerCommission', NEW.influencer_commission,
      'originalPrice', NEW.original_price,
      'discountAmount', NEW.discount_amount,
      'finalPrice', NEW.final_price,
      
      -- ✅ 新增：統一編號
      'taxId', NEW.tax_id,
      
      -- ✅ 新增：旅遊方案資訊
      'tourPackageId', NEW.tour_package_id,
      'tourPackageName', NEW.tour_package_name,
      
      -- 時間資訊
      'createdAt', NEW.created_at,
      'updatedAt', NEW.updated_at,
      'actualStartTime', NEW.actual_start_time,
      'actualEndTime', NEW.actual_end_time,
      'completedAt', NEW.completed_at,
      
      -- 位置資訊
      'pickupLocation', CASE 
        WHEN NEW.pickup_latitude IS NOT NULL AND NEW.pickup_longitude IS NOT NULL 
        THEN jsonb_build_object(
          'latitude', NEW.pickup_latitude,
          'longitude', NEW.pickup_longitude
        )
        ELSE NULL
      END
    )
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 驗證 trigger function 已更新
SELECT 
  'Trigger function 已更新，包含優惠碼和統編欄位' as message,
  proname as function_name
FROM pg_proc
WHERE proname = 'bookings_to_outbox';

