-- ============================================================
-- 新北市分區定價 Phase 1
-- 架構：國家 > 縣市 > 區（子區）
-- 本次：新增 3 個新北子區，只設定桃園機場（TPE）定價
-- 其他機場（TSA/RMQ/KHH）後續再補
-- ============================================================

-- ============================================================
-- 1. region_definitions 新增階層欄位
-- ============================================================
ALTER TABLE region_definitions
  ADD COLUMN IF NOT EXISTS parent_region_key TEXT,         -- NULL = 縣市層；有值 = 子區，指向父縣市的 region_key
  ADD COLUMN IF NOT EXISTS included_districts JSONB DEFAULT '[]'::jsonb; -- 子區包含的行政區名（不含「區」字）

COMMENT ON COLUMN region_definitions.parent_region_key IS '父縣市的 region_key（NULL 表示本身是縣市層）';
COMMENT ON COLUMN region_definitions.included_districts IS '此定價區包含的行政區名稱列表（不含「區」字），例如：["板橋","三重"]';

-- ============================================================
-- 2. 插入新北三個定價子區
--    bounding box 沿用新北市範圍（程式碼以 parent_region_key 過濾，
--    子區不參與座標 bounding box 判定，僅用於地址文字比對）
-- ============================================================
INSERT INTO region_definitions
  (country, region_key, parent_region_key, region_name_i18n, included_districts,
   min_lat, max_lat, min_lng, max_lng, priority, is_active)
VALUES

  -- 新北 Zone A：13 區（都會帶，含板橋/三重等核心區）
  ('TW', '新北A', '新北',
   '{"zh-TW":"新北（都會帶）","en":"New Taipei Zone A","ja":"新北（都市圏）","ko":"신베이 A구역","zh-CN":"新北（都会带）","vi":"Tân Bắc khu A","th":"นิวไทเป โซน A","id":"New Taipei Zona A"}',
   '["三重","新莊","八里","三峽","鶯歌","樹林","五股","蘆洲","中和","永和","板橋","泰山","土城"]',
   24.670000, 25.300000, 121.280000, 122.010000, -1, true),

  -- 新北 Zone B：汐止、深坑
  ('TW', '新北B', '新北',
   '{"zh-TW":"新北（汐止深坑）","en":"New Taipei Zone B","ja":"新北（汐止・深坑）","ko":"신베이 B구역","zh-CN":"新北（汐止深坑）","vi":"Tân Bắc khu B","th":"นิวไทเป โซน B","id":"New Taipei Zona B"}',
   '["汐止","深坑"]',
   24.670000, 25.300000, 121.280000, 122.010000, -1, true),

  -- 新北 Zone C：瑞芳、三芝、萬里
  ('TW', '新北C', '新北',
   '{"zh-TW":"新北（瑞芳三芝萬里）","en":"New Taipei Zone C","ja":"新北（瑞芳・三芝・万里）","ko":"신베이 C구역","zh-CN":"新北（瑞芳三芝万里）","vi":"Tân Bắc khu C","th":"นิวไทเป โซน C","id":"New Taipei Zona C"}',
   '["瑞芳","三芝","萬里"]',
   24.670000, 25.300000, 121.280000, 122.010000, -1, true)

ON CONFLICT (country, region_key) DO UPDATE SET
  parent_region_key    = EXCLUDED.parent_region_key,
  included_districts   = EXCLUDED.included_districts,
  region_name_i18n     = EXCLUDED.region_name_i18n,
  updated_at           = now();

-- ============================================================
-- 3. airport_transfer_pricing：插入三區 TPE 定價
--    TSA / RMQ / KHH 暫設 NULL，Phase 2 再補
--    原有「新北」記錄保留，作為未分配區的 fallback
-- ============================================================

-- ── Zone A（13 區）──────────────────────────────────────────
INSERT INTO airport_transfer_pricing
  (country, price_list_name, vehicle_type, region, tpe_price, is_active)
VALUES
  ('TW', '機場接送五人座轎車',   'S',  '新北A', 1300, true),
  ('TW', '機場接送五人座休旅車', 'M',  '新北A', 1400, true),
  ('TW', '機場接送九人座',       'L',  '新北A', 2000, true),
  ('TW', '機場接送Alphard',      'XL', '新北A', 2200, true)
ON CONFLICT (country, price_list_name, vehicle_type, region) DO UPDATE SET
  tpe_price  = EXCLUDED.tpe_price,
  is_active  = EXCLUDED.is_active,
  updated_at = now();

-- ── Zone B（汐止、深坑）────────────────────────────────────
INSERT INTO airport_transfer_pricing
  (country, price_list_name, vehicle_type, region, tpe_price, is_active)
VALUES
  ('TW', '機場接送五人座轎車',   'S',  '新北B', 1400, true),
  ('TW', '機場接送五人座休旅車', 'M',  '新北B', 1500, true),
  ('TW', '機場接送九人座',       'L',  '新北B', 2100, true),
  ('TW', '機場接送Alphard',      'XL', '新北B', 2300, true)
ON CONFLICT (country, price_list_name, vehicle_type, region) DO UPDATE SET
  tpe_price  = EXCLUDED.tpe_price,
  is_active  = EXCLUDED.is_active,
  updated_at = now();

-- ── Zone C（瑞芳、三芝、萬里）─────────────────────────────
INSERT INTO airport_transfer_pricing
  (country, price_list_name, vehicle_type, region, tpe_price, is_active)
VALUES
  ('TW', '機場接送五人座轎車',   'S',  '新北C', 1700, true),
  ('TW', '機場接送五人座休旅車', 'M',  '新北C', 1800, true),
  ('TW', '機場接送九人座',       'L',  '新北C', 2400, true),
  ('TW', '機場接送Alphard',      'XL', '新北C', 2600, true)
ON CONFLICT (country, price_list_name, vehicle_type, region) DO UPDATE SET
  tpe_price  = EXCLUDED.tpe_price,
  is_active  = EXCLUDED.is_active,
  updated_at = now();

-- ============================================================
-- 驗證
-- ============================================================
DO $$
DECLARE
  v_zones INTEGER;
  v_pricing INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_zones
  FROM region_definitions
  WHERE country = 'TW' AND parent_region_key = '新北' AND is_active = true;

  SELECT COUNT(*) INTO v_pricing
  FROM airport_transfer_pricing
  WHERE country = 'TW' AND region IN ('新北A','新北B','新北C') AND is_active = true;

  RAISE NOTICE '=== 新北分區 Phase 1 完成 ===';
  RAISE NOTICE '新北子區數: %（應為 3）', v_zones;
  RAISE NOTICE '新北子區定價行數: %（應為 12）', v_pricing;
END $$;
