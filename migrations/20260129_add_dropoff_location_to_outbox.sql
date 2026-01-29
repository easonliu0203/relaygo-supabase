-- Migration: Add dropoff location to outbox trigger payload
-- Created: 2026-01-29
-- Purpose: Include dropoff coordinates in Firebase sync for navigation functionality
-- Issue: Firebase dropoffLocation was using hardcoded default coordinates

-- 更新 bookings_to_outbox 函數，添加 dropoffLocation 到 payload
CREATE OR REPLACE FUNCTION public.bookings_to_outbox()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
      v.plate_number,
      v.model,
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
    LEFT JOIN vehicles v ON d.id = v.driver_id AND v.is_primary = true
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
      
      -- 訂單狀態
      'status', NEW.status,
      
      -- 地點資訊
      'pickupAddress', NEW.pickup_location,
      'destination', NEW.destination,
      
      -- 時間資訊
      'startDate', NEW.start_date,
      'startTime', NEW.start_time,
      'durationHours', NEW.duration_hours,
      
      -- 車輛資訊
      'vehicleType', NEW.vehicle_type,
      'specialRequirements', NEW.special_requirements,
      'requiresForeignLanguage', NEW.requires_foreign_language,
      
      -- 乘客資訊
      'passengerCount', NEW.passenger_count,
      'luggageCount', NEW.luggage_count,
      
      -- 費用資訊
      'basePrice', NEW.base_price,
      'foreignLanguageSurcharge', NEW.foreign_language_surcharge,
      'overtimeFee', NEW.overtime_fee,
      'tipAmount', NEW.tip_amount,
      'totalAmount', NEW.total_amount,
      'depositAmount', NEW.deposit_amount,
      'depositPaid', NEW.deposit_paid,
      'platformFee', NEW.platform_fee,
      'driverEarning', NEW.driver_earning,
      
      -- 旅遊方案
      'tourPackageId', NEW.tour_package_id,
      'tourPackageName', NEW.tour_package_name,
      
      -- 優惠碼相關
      'promoCode', NEW.promo_code,
      'influencerId', NEW.influencer_id,
      'influencerCommission', NEW.influencer_commission,
      'originalPrice', NEW.original_price,
      'discountAmount', NEW.discount_amount,
      'finalPrice', NEW.final_price,
      'taxId', NEW.tax_id,
      
      -- 維度欄位
      'country', COALESCE(NEW.country, 'TW'),
      'serviceType', COALESCE(NEW.service_type, 'charter'),
      
      -- 時間戳記
      'createdAt', NEW.created_at,
      'updatedAt', NEW.updated_at,
      'actualStartTime', NEW.actual_start_time,
      'actualEndTime', NEW.actual_end_time,
      'completedAt', NEW.completed_at,

      -- ✅ 位置座標（用於導航功能）
      'pickupLocation', CASE
        WHEN NEW.pickup_latitude IS NOT NULL AND NEW.pickup_longitude IS NOT NULL
        THEN jsonb_build_object(
          'latitude', NEW.pickup_latitude,
          'longitude', NEW.pickup_longitude
        )
        ELSE NULL
      END,
      -- ✅ 新增：下車地點座標
      'dropoffLocation', CASE
        WHEN NEW.dropoff_latitude IS NOT NULL AND NEW.dropoff_longitude IS NOT NULL
        THEN jsonb_build_object(
          'latitude', NEW.dropoff_latitude,
          'longitude', NEW.dropoff_longitude
        )
        ELSE NULL
      END
    )
  );

  RETURN NEW;
END;
$function$;

-- 添加註釋
COMMENT ON FUNCTION public.bookings_to_outbox() IS
'訂單變更時將事件寫入 outbox 表，包含 pickupLocation 和 dropoffLocation 座標用於導航功能';

-- 驗證 trigger function 已更新
SELECT
  '✅ Trigger function 已更新，包含 dropoffLocation 座標' as message,
  proname as function_name
FROM pg_proc
WHERE proname = 'bookings_to_outbox';

