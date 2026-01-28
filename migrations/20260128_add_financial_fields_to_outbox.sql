-- =====================================================
-- Migration: 添加分潤欄位到 bookings_to_outbox 觸發器
-- 日期: 2026-01-28
-- 描述: 修改 bookings_to_outbox 觸發器，在 payload 中添加
--       platformFee、driverEarning、country、serviceType 欄位
--       確保這些值在訂單創建時就被同步到 Firestore
-- =====================================================

-- 重新創建 bookings_to_outbox 函數，添加分潤相關欄位
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
      'luggageCount', NEW.luggage_count,
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
      'updatedAt', NEW.updated_at,
      'actualStartTime', NEW.actual_start_time,
      'actualEndTime', NEW.actual_end_time,
      'completedAt', NEW.completed_at,
      -- ✅ 新增：分潤相關欄位（訂單創建時的快照，不會隨配置修改而變化）
      'platformFee', COALESCE(NEW.platform_fee, 0),
      'driverEarning', COALESCE(NEW.driver_earning, 0),
      -- ✅ 新增：訂單維度欄位（用於多維度分潤配置）
      'country', COALESCE(NEW.country, 'TW'),
      'serviceType', COALESCE(NEW.service_type, 'charter'),
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
$function$;

-- 添加註釋
COMMENT ON FUNCTION public.bookings_to_outbox() IS 
'訂單變更時將事件寫入 outbox 表，包含分潤欄位（platformFee, driverEarning）和維度欄位（country, serviceType）';

