-- 修復 Outbox Trigger：添加 deposit_paid 欄位
-- 問題：Outbox trigger 沒有包含 deposit_paid 欄位，導致 Firestore 中的 depositPaid 一直是 false

-- 重新創建 trigger function，添加 deposit_paid 欄位
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

  -- 獲取司機資訊（如果已配對）
  IF NEW.driver_id IS NOT NULL THEN
    SELECT 
      u.firebase_uid,
      up.first_name,
      up.last_name,
      up.phone,
      d.vehicle_plate,
      d.vehicle_model,
      d.rating
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
      'specialRequirements', NEW.special_requirements,
      'requiresForeignLanguage', NEW.requires_foreign_language,
      'basePrice', NEW.base_price,
      'foreignLanguageSurcharge', NEW.foreign_language_surcharge,
      'overtimeFee', NEW.overtime_fee,
      'tipAmount', NEW.tip_amount,
      'totalAmount', NEW.total_amount,
      'depositAmount', NEW.deposit_amount,
      
      -- ✅ 新增：訂金支付狀態
      'depositPaid', COALESCE(NEW.deposit_paid, false),
      
      'createdAt', NEW.created_at,
      'updatedAt', NEW.updated_at,
      'actualStartTime', NEW.actual_start_time,
      'actualEndTime', NEW.actual_end_time,
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
  'Trigger function 已更新' as message,
  proname as function_name,
  pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname = 'bookings_to_outbox';

-- 手動觸發一次同步，更新現有訂單的 depositPaid 狀態
-- 找出所有 deposit_paid = true 但 Firestore 中 depositPaid = false 的訂單
INSERT INTO outbox (
  aggregate_type,
  aggregate_id,
  event_type,
  payload
)
SELECT 
  'booking',
  b.id::TEXT,
  'updated',
  jsonb_build_object(
    'id', b.id,
    'bookingNumber', b.booking_number,
    'customerId', (SELECT firebase_uid FROM users WHERE id = b.customer_id),
    'customerName', (
      SELECT TRIM(CONCAT(up.first_name, ' ', up.last_name))
      FROM users u
      LEFT JOIN user_profiles up ON u.id = up.user_id
      WHERE u.id = b.customer_id
    ),
    'customerPhone', (
      SELECT up.phone
      FROM users u
      LEFT JOIN user_profiles up ON u.id = up.user_id
      WHERE u.id = b.customer_id
    ),
    'driverId', CASE 
      WHEN b.driver_id IS NOT NULL 
      THEN (SELECT firebase_uid FROM users WHERE id = b.driver_id)
      ELSE NULL
    END,
    'driverName', CASE 
      WHEN b.driver_id IS NOT NULL 
      THEN (
        SELECT TRIM(CONCAT(up.first_name, ' ', up.last_name))
        FROM users u
        LEFT JOIN user_profiles up ON u.id = up.user_id
        WHERE u.id = b.driver_id
      )
      ELSE NULL
    END,
    'driverPhone', CASE 
      WHEN b.driver_id IS NOT NULL 
      THEN (
        SELECT up.phone
        FROM users u
        LEFT JOIN user_profiles up ON u.id = up.user_id
        WHERE u.id = b.driver_id
      )
      ELSE NULL
    END,
    'driverVehiclePlate', CASE 
      WHEN b.driver_id IS NOT NULL 
      THEN (SELECT vehicle_plate FROM drivers WHERE user_id = b.driver_id)
      ELSE NULL
    END,
    'driverVehicleModel', CASE 
      WHEN b.driver_id IS NOT NULL 
      THEN (SELECT vehicle_model FROM drivers WHERE user_id = b.driver_id)
      ELSE NULL
    END,
    'driverRating', CASE 
      WHEN b.driver_id IS NOT NULL 
      THEN (SELECT rating FROM drivers WHERE user_id = b.driver_id)
      ELSE NULL
    END,
    'status', b.status,
    'pickupAddress', b.pickup_location,
    'destination', b.destination,
    'startDate', b.start_date,
    'startTime', b.start_time,
    'durationHours', b.duration_hours,
    'vehicleType', b.vehicle_type,
    'specialRequirements', b.special_requirements,
    'requiresForeignLanguage', b.requires_foreign_language,
    'basePrice', b.base_price,
    'foreignLanguageSurcharge', b.foreign_language_surcharge,
    'overtimeFee', b.overtime_fee,
    'tipAmount', b.tip_amount,
    'totalAmount', b.total_amount,
    'depositAmount', b.deposit_amount,
    'depositPaid', COALESCE(b.deposit_paid, false),
    'createdAt', b.created_at,
    'updatedAt', b.updated_at,
    'actualStartTime', b.actual_start_time,
    'actualEndTime', b.actual_end_time,
    'pickupLocation', CASE 
      WHEN b.pickup_latitude IS NOT NULL AND b.pickup_longitude IS NOT NULL 
      THEN jsonb_build_object(
        'latitude', b.pickup_latitude,
        'longitude', b.pickup_longitude
      )
      ELSE NULL
    END
  )
FROM bookings b
WHERE b.deposit_paid = true
  AND b.status IN ('paid_deposit', 'assigned', 'matched', 'driver_confirmed', 
                   'driver_departed', 'driver_arrived', 'trip_started', 
                   'trip_ended', 'pending_balance', 'completed');

-- 顯示結果
SELECT 
  '✅ Trigger function 已更新，已添加 depositPaid 欄位' as message,
  COUNT(*) as affected_bookings
FROM bookings
WHERE deposit_paid = true;

