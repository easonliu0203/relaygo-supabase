-- 測試 Firebase 同步：檢查 outbox 事件的 payload 是否包含優惠碼和統編欄位
-- Date: 2026-01-10

-- 1. 查詢最近的 outbox 事件，檢查 payload 結構
SELECT 
  id,
  aggregate_id,
  event_type,
  payload->>'bookingNumber' as booking_number,
  payload->>'promoCode' as promo_code,
  payload->>'taxId' as tax_id,
  payload->>'originalPrice' as original_price,
  payload->>'discountAmount' as discount_amount,
  payload->>'finalPrice' as final_price,
  payload->>'influencerId' as influencer_id,
  payload->>'influencerCommission' as influencer_commission,
  created_at,
  processed_at
FROM outbox
WHERE aggregate_type = 'booking'
  AND aggregate_id = '51270a90-d3fd-4716-b4a5-ed1333378844'
ORDER BY created_at DESC
LIMIT 1;

-- 2. 手動觸發一次同步（創建新的 outbox 事件）
-- 這會觸發 Edge Function 重新同步到 Firebase
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
    'promoCode', b.promo_code,
    'influencerId', b.influencer_id,
    'influencerCommission', b.influencer_commission,
    'originalPrice', b.original_price,
    'discountAmount', b.discount_amount,
    'finalPrice', b.final_price,
    'taxId', b.tax_id,
    'tourPackageId', b.tour_package_id,
    'tourPackageName', b.tour_package_name,
    'createdAt', b.created_at,
    'updatedAt', b.updated_at
  )
FROM bookings b
WHERE b.id = '51270a90-d3fd-4716-b4a5-ed1333378844'
RETURNING 
  id,
  aggregate_id,
  payload->>'promoCode' as promo_code,
  payload->>'taxId' as tax_id,
  payload->>'originalPrice' as original_price,
  payload->>'finalPrice' as final_price;

