-- 手動觸發現有訂單的優惠碼和統編資訊同步到 Firestore
-- Date: 2026-01-10
-- Description: 為所有包含優惠碼或統編的訂單創建 outbox 事件，觸發同步到 Firestore

-- 查詢有優惠碼或統編的訂單
SELECT 
  id,
  booking_number,
  promo_code,
  tax_id,
  original_price,
  discount_amount,
  final_price,
  status
FROM bookings
WHERE promo_code IS NOT NULL OR tax_id IS NOT NULL
ORDER BY created_at DESC;

-- 為這些訂單創建 outbox 事件，觸發同步
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
    
    -- 客戶資訊
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
    
    -- 司機資訊
    'driverId', (SELECT firebase_uid FROM users WHERE id = b.driver_id),
    'driverName', (
      SELECT TRIM(CONCAT(up.first_name, ' ', up.last_name))
      FROM users u
      LEFT JOIN user_profiles up ON u.id = up.user_id
      WHERE u.id = b.driver_id
    ),
    'driverPhone', (
      SELECT up.phone
      FROM users u
      LEFT JOIN user_profiles up ON u.id = up.user_id
      WHERE u.id = b.driver_id
    ),
    'driverVehiclePlate', (
      SELECT vehicle_plate
      FROM driver_vehicles
      WHERE driver_id = b.driver_id AND is_primary = true
      LIMIT 1
    ),
    'driverVehicleModel', (
      SELECT vehicle_model
      FROM driver_vehicles
      WHERE driver_id = b.driver_id AND is_primary = true
      LIMIT 1
    ),
    'driverRating', (
      SELECT rating
      FROM driver_profiles
      WHERE user_id = b.driver_id
    ),
    
    -- 訂單基本資訊
    'status', b.status,
    'pickupAddress', b.pickup_location,
    'destination', b.destination,
    'startDate', b.start_date,
    'startTime', b.start_time,
    'durationHours', b.duration_hours,
    'vehicleType', b.vehicle_type,
    'passengerCount', b.passenger_count,
    'luggageCount', b.luggage_count,
    'specialRequirements', b.special_requirements,
    'requiresForeignLanguage', b.requires_foreign_language,
    
    -- 費用資訊
    'basePrice', b.base_price,
    'foreignLanguageSurcharge', b.foreign_language_surcharge,
    'overtimeFee', b.overtime_fee,
    'tipAmount', b.tip_amount,
    'totalAmount', b.total_amount,
    'depositAmount', b.deposit_amount,
    'depositPaid', COALESCE(b.deposit_paid, false),
    
    -- ✅ 優惠碼相關欄位
    'promoCode', b.promo_code,
    'influencerId', b.influencer_id,
    'influencerCommission', b.influencer_commission,
    'originalPrice', b.original_price,
    'discountAmount', b.discount_amount,
    'finalPrice', b.final_price,
    
    -- ✅ 統一編號
    'taxId', b.tax_id,
    
    -- ✅ 旅遊方案資訊
    'tourPackageId', b.tour_package_id,
    'tourPackageName', b.tour_package_name,
    
    -- 時間資訊
    'createdAt', b.created_at,
    'updatedAt', b.updated_at,
    'actualStartTime', b.actual_start_time,
    'actualEndTime', b.actual_end_time,
    'completedAt', b.completed_at,
    
    -- 位置資訊
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
WHERE b.promo_code IS NOT NULL OR b.tax_id IS NOT NULL;

-- 查詢剛創建的 outbox 事件
SELECT 
  o.id,
  o.aggregate_id,
  o.event_type,
  o.payload->>'bookingNumber' as booking_number,
  o.payload->>'promoCode' as promo_code,
  o.payload->>'taxId' as tax_id,
  o.created_at,
  o.processed_at
FROM outbox o
WHERE o.aggregate_type = 'booking'
  AND (o.payload->>'promoCode' IS NOT NULL OR o.payload->>'taxId' IS NOT NULL)
ORDER BY o.created_at DESC
LIMIT 10;

