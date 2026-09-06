-- ============================================================
-- Phase 0：機場接送服務類型 — 資料庫準備
-- ============================================================
-- 日期: 2026-02-16
-- 用途:
--   1. bookings.service_type CHECK 約束加入 'airport_transfer'
--   2. influencers 表新增 airport_transfer 折扣/分潤欄位
--   3. revenue_share_configs 插入 airport_transfer 分潤配置
--   4. airport_transfer_pricing 補齊 M/L/XL 車型種子資料
-- ============================================================

-- ============================================================
-- 1. 修改 bookings.service_type CHECK 約束
-- ============================================================
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS check_service_type;
ALTER TABLE bookings ADD CONSTRAINT check_service_type
  CHECK (service_type IN ('charter', 'instant_ride', 'airport_transfer'));

COMMENT ON COLUMN bookings.service_type IS '服務類型: charter (包車旅遊), instant_ride (即時派車), airport_transfer (機場接送)';

-- ============================================================
-- 2. influencers 表新增 airport_transfer 折扣/分潤欄位
-- ============================================================
ALTER TABLE influencers
ADD COLUMN IF NOT EXISTS discount_percent_airport_transfer NUMERIC(5,2) DEFAULT 0;

ALTER TABLE influencers
ADD COLUMN IF NOT EXISTS commission_percent_airport_transfer DOUBLE PRECISION DEFAULT NULL;

COMMENT ON COLUMN influencers.discount_percent_airport_transfer IS '機場接送折扣百分比（例如：5 代表 95 折）';
COMMENT ON COLUMN influencers.commission_percent_airport_transfer IS '機場接送服務的分潤百分比（僅當 commission_type = by_service_type 時使用）';

-- 將現有統一折扣/分潤值同步到新欄位（避免空值）
UPDATE influencers
SET discount_percent_airport_transfer = COALESCE(discount_percentage, 0)
WHERE discount_percent_airport_transfer = 0
  AND discount_percentage IS NOT NULL
  AND discount_percentage > 0;

UPDATE influencers
SET commission_percent_airport_transfer = commission_percent
WHERE commission_percent_airport_transfer IS NULL
  AND commission_percent IS NOT NULL;

-- ============================================================
-- 3. revenue_share_configs 插入 airport_transfer 分潤配置
--    （複製 charter 配置作為初始值，可日後調整）
-- ============================================================
INSERT INTO revenue_share_configs
  (country, region, service_type, has_promo_code,
   company_percentage, driver_percentage, company_base_percentage,
   is_active, priority, description)
SELECT
  country,
  region,
  'airport_transfer',
  has_promo_code,
  company_percentage,
  driver_percentage,
  company_base_percentage,
  true,
  priority,
  REPLACE(COALESCE(description, ''), '包車旅遊', '機場接送')
FROM revenue_share_configs
WHERE service_type = 'charter'
  AND is_active = true
ON CONFLICT DO NOTHING;

-- ============================================================
-- 4. airport_transfer_pricing 補齊 M/L/XL 車型
--    地區使用實際 DB 值（台北/新北 分開，非雙北）
-- ============================================================

-- 車型 S（五人座轎車）
INSERT INTO airport_transfer_pricing
  (country, price_list_name, vehicle_type, region, tsa_price, tpe_price, rmq_price, khh_price)
VALUES
  ('TW', '機場接送五人座轎車', 'S', '台北', 1100, 1300, 3400, 6500),
  ('TW', '機場接送五人座轎車', 'S', '新北', 1100, 1300, 3400, 6500),
  ('TW', '機場接送五人座轎車', 'S', '桃園', 1300, 1100, 3000, 6000),
  ('TW', '機場接送五人座轎車', 'S', '新竹', 2400, 1900, 2600, 5500),
  ('TW', '機場接送五人座轎車', 'S', '苗栗', 2900, 2600, 2400, 5100),
  ('TW', '機場接送五人座轎車', 'S', '台中', 3400, 3000, 1700, 4500),
  ('TW', '機場接送五人座轎車', 'S', '彰化', 3800, 3400, 2200, 4200),
  ('TW', '機場接送五人座轎車', 'S', '南投', 4200, 3800, 2500, 4600),
  ('TW', '機場接送五人座轎車', 'S', '雲林', 4400, 4000, 2700, 3700),
  ('TW', '機場接送五人座轎車', 'S', '嘉義', 5200, 4600, 3200, 3000),
  ('TW', '機場接送五人座轎車', 'S', '台南', 5900, 5400, 4000, 1900),
  ('TW', '機場接送五人座轎車', 'S', '高雄', 6500, 6000, 4500, 1100),
  ('TW', '機場接送五人座轎車', 'S', '屏東', 7200, 6800, 5000, 1600),
  ('TW', '機場接送五人座轎車', 'S', '墾丁', 8200, 7700, 5700, 3000),
  ('TW', '機場接送五人座轎車', 'S', '基隆', 1900, 2400, 3900, 7200),
  ('TW', '機場接送五人座轎車', 'S', '宜蘭', 2700, 3400, 5100, 8000),
  ('TW', '機場接送五人座轎車', 'S', '花蓮', 5600, 6200, 7800, 8600),
  ('TW', '機場接送五人座轎車', 'S', '台東', 8000, 8600, 7600, 4600)
ON CONFLICT (country, price_list_name, vehicle_type, region) DO UPDATE SET
  tsa_price  = EXCLUDED.tsa_price,
  tpe_price  = EXCLUDED.tpe_price,
  rmq_price  = EXCLUDED.rmq_price,
  khh_price  = EXCLUDED.khh_price,
  updated_at = now();

-- 車型 M（五人座休旅車）— 價格 = S 車型 × 1.15（四捨五入到百位）
INSERT INTO airport_transfer_pricing
  (country, price_list_name, vehicle_type, region, tsa_price, tpe_price, rmq_price, khh_price)
VALUES
  ('TW', '機場接送五人座休旅車', 'M', '台北', 1200, 1400, 3600, 6700),
  ('TW', '機場接送五人座休旅車', 'M', '新北', 1200, 1400, 3600, 6700),
  ('TW', '機場接送五人座休旅車', 'M', '桃園', 1400, 1200, 3200, 6400),
  ('TW', '機場接送五人座休旅車', 'M', '新竹', 2500, 2000, 2800, 5800),
  ('TW', '機場接送五人座休旅車', 'M', '苗栗', 3100, 2700, 2600, 5400),
  ('TW', '機場接送五人座休旅車', 'M', '台中', 3600, 3200, 1900, 4700),
  ('TW', '機場接送五人座休旅車', 'M', '彰化', 4000, 3600, 2400, 4400),
  ('TW', '機場接送五人座休旅車', 'M', '南投', 4400, 4000, 2700, 4800),
  ('TW', '機場接送五人座休旅車', 'M', '雲林', 4600, 4200, 2900, 3900),
  ('TW', '機場接送五人座休旅車', 'M', '嘉義', 5400, 5000, 3500, 3200),
  ('TW', '機場接送五人座休旅車', 'M', '台南', 6200, 5700, 4200, 2100),
  ('TW', '機場接送五人座休旅車', 'M', '高雄', 6700, 6400, 4700, 1200),
  ('TW', '機場接送五人座休旅車', 'M', '屏東', 7500, 7000, 5200, 1700),
  ('TW', '機場接送五人座休旅車', 'M', '墾丁', 8500, 8000, 6000, 3200),
  ('TW', '機場接送五人座休旅車', 'M', '基隆', 2000, 2600, 4200, 7500),
  ('TW', '機場接送五人座休旅車', 'M', '宜蘭', 2900, 3600, 5400, 8200),
  ('TW', '機場接送五人座休旅車', 'M', '花蓮', 5800, 6400, 8000, 9000),
  ('TW', '機場接送五人座休旅車', 'M', '台東', 8200, 8800, 7900, 4800)
ON CONFLICT (country, price_list_name, vehicle_type, region) DO UPDATE SET
  tsa_price  = EXCLUDED.tsa_price,
  tpe_price  = EXCLUDED.tpe_price,
  rmq_price  = EXCLUDED.rmq_price,
  khh_price  = EXCLUDED.khh_price,
  updated_at = now();

-- 車型 L（九人座）— 價格 = S 車型 × 1.35（四捨五入到百位）
INSERT INTO airport_transfer_pricing
  (country, price_list_name, vehicle_type, region, tsa_price, tpe_price, rmq_price, khh_price)
VALUES
  ('TW', '機場接送九人座', 'L', '台北', 1800, 2000, 4200, 7600),
  ('TW', '機場接送九人座', 'L', '新北', 1800, 2000, 4200, 7600),
  ('TW', '機場接送九人座', 'L', '桃園', 2000, 1800, 3800, 7100),
  ('TW', '機場接送九人座', 'L', '新竹', 3100, 2700, 3400, 6600),
  ('TW', '機場接送九人座', 'L', '苗栗', 3900, 3400, 3200, 6200),
  ('TW', '機場接送九人座', 'L', '台中', 4200, 3800, 2600, 5600),
  ('TW', '機場接送九人座', 'L', '彰化', 4800, 4200, 3100, 5100),
  ('TW', '機場接送九人座', 'L', '南投', 5200, 4600, 3300, 5600),
  ('TW', '機場接送九人座', 'L', '雲林', 5400, 4900, 3600, 4600),
  ('TW', '機場接送九人座', 'L', '嘉義', 6200, 5600, 4200, 3900),
  ('TW', '機場接送九人座', 'L', '台南', 7000, 6400, 5000, 3000),
  ('TW', '機場接送九人座', 'L', '高雄', 7600, 7100, 5600, 2000),
  ('TW', '機場接送九人座', 'L', '屏東', 8400, 7800, 6100, 2400),
  ('TW', '機場接送九人座', 'L', '墾丁', 9400, 9000, 6800, 3900),
  ('TW', '機場接送九人座', 'L', '基隆', 2700, 3200, 4900, 8400),
  ('TW', '機場接送九人座', 'L', '宜蘭', 3600, 4200, 6100, 9100),
  ('TW', '機場接送九人座', 'L', '花蓮', 6600, 7100, 8900, 9800),
  ('TW', '機場接送九人座', 'L', '台東', 9100, 9600, 8800, 5600)
ON CONFLICT (country, price_list_name, vehicle_type, region) DO UPDATE SET
  tsa_price  = EXCLUDED.tsa_price,
  tpe_price  = EXCLUDED.tpe_price,
  rmq_price  = EXCLUDED.rmq_price,
  khh_price  = EXCLUDED.khh_price,
  updated_at = now();

-- 車型 XL（阿法 Alphard）— 價格 = S 車型 × 1.60（四捨五入到百位）
INSERT INTO airport_transfer_pricing
  (country, price_list_name, vehicle_type, region, tsa_price, tpe_price, rmq_price, khh_price)
VALUES
  ('TW', '機場接送Alphard', 'XL', '台北', 2200, 2200, 7900, 12900),
  ('TW', '機場接送Alphard', 'XL', '新北', 2200, 2200, 7900, 12900),
  ('TW', '機場接送Alphard', 'XL', '桃園', 2400, 2400, 7200, 11900),
  ('TW', '機場接送Alphard', 'XL', '新竹', 4900, 4400, 6900, 11400),
  ('TW', '機場接送Alphard', 'XL', '苗栗', 6900, 6400, 5200, 10400),
  ('TW', '機場接送Alphard', 'XL', '台中', 7900, 7200, 3200, 8200),
  ('TW', '機場接送Alphard', 'XL', '彰化', 8400, 7600, 4200, 8000),
  ('TW', '機場接送Alphard', 'XL', '南投', 9400, 8600, 5200, 8000),
  ('TW', '機場接送Alphard', 'XL', '雲林', 10000, 9200, 5900, 7600),
  ('TW', '機場接送Alphard', 'XL', '嘉義', 11200, 10400, 6800, 6600),
  ('TW', '機場接送Alphard', 'XL', '台南', 11900, 11200, 7600, 4900),
  ('TW', '機場接送Alphard', 'XL', '高雄', 12900, 11900, 8200, 2900),
  ('TW', '機場接送Alphard', 'XL', '屏東', 13900, 12900, 9200, 3900),
  ('TW', '機場接送Alphard', 'XL', '墾丁', 16200, 15400, 10900, 6400),
  ('TW', '機場接送Alphard', 'XL', '基隆', 3400, 4200, 8900, 13900),
  ('TW', '機場接送Alphard', 'XL', '宜蘭', 4900, 6600, 9400, 14900),
  ('TW', '機場接送Alphard', 'XL', '花蓮', 14000, 14900, 16400, 17200),
  ('TW', '機場接送Alphard', 'XL', '台東', 16900, 17400, 15400, 11400)
ON CONFLICT (country, price_list_name, vehicle_type, region) DO UPDATE SET
  tsa_price  = EXCLUDED.tsa_price,
  tpe_price  = EXCLUDED.tpe_price,
  rmq_price  = EXCLUDED.rmq_price,
  khh_price  = EXCLUDED.khh_price,
  updated_at = now();

-- ============================================================
-- 5. 同步 S 車型種子資料：將舊 '雙北' 拆分為 '台北'/'新北'
--    （若 DB 中已有 '台北'/'新北' 則 ON CONFLICT 更新即可）
-- ============================================================
INSERT INTO airport_transfer_pricing
  (country, price_list_name, vehicle_type, region, tsa_price, tpe_price, rmq_price, khh_price)
VALUES
  ('TW', '機場接送五人座轎車', 'S', '台北', 900,  1100, 3200, 6300),
  ('TW', '機場接送五人座轎車', 'S', '新北', 900,  1100, 3200, 6300)
ON CONFLICT (country, price_list_name, vehicle_type, region) DO UPDATE SET
  tsa_price  = EXCLUDED.tsa_price,
  tpe_price  = EXCLUDED.tpe_price,
  rmq_price  = EXCLUDED.rmq_price,
  khh_price  = EXCLUDED.khh_price,
  updated_at = now();

-- ============================================================
-- 驗證
-- ============================================================
DO $$
DECLARE
  v_vehicle_types INTEGER;
  v_total_rows INTEGER;
  v_revenue_configs INTEGER;
BEGIN
  SELECT COUNT(DISTINCT vehicle_type) INTO v_vehicle_types
  FROM airport_transfer_pricing WHERE is_active = true AND country = 'TW';

  SELECT COUNT(*) INTO v_total_rows
  FROM airport_transfer_pricing WHERE is_active = true AND country = 'TW';

  SELECT COUNT(*) INTO v_revenue_configs
  FROM revenue_share_configs WHERE service_type = 'airport_transfer' AND is_active = true;

  RAISE NOTICE '=== Phase 0 資料庫準備完成 ===';
  RAISE NOTICE '機場接送價目表車型數: %', v_vehicle_types;
  RAISE NOTICE '機場接送價目表總列數: %', v_total_rows;
  RAISE NOTICE 'airport_transfer 分潤配置數: %', v_revenue_configs;
END $$;
