-- ============================================================
-- 機場接送定價表
-- 每一行 = 一個地區 × 一個車型的完整機場定價
-- X 軸：4 個機場欄位 (TSA / TPE / RMQ / KHH)
-- Y 軸：地區 (region)
-- Z 軸：車型 (vehicle_type: XS / S / M / L / XL)
-- ============================================================
CREATE TABLE IF NOT EXISTS airport_transfer_pricing (
  id              uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  country         text        NOT NULL DEFAULT 'TW',           -- 國家碼，預設台灣，未來全球市場使用
  price_list_name text        NOT NULL,                        -- 價目表名稱，例：「機場接送五人座轎車價目表」
  vehicle_type    text        NOT NULL,                        -- 車型：XS / S / M / L / XL
  region          text        NOT NULL,                        -- 地區：雙北 / 桃園 / 新竹 / ...
  tsa_price       integer,                                     -- 台北松山機場 (TSA) 價格 (NTD)
  tpe_price       integer,                                     -- 桃園國際機場 (TPE) 價格 (NTD)
  rmq_price       integer,                                     -- 台中清泉崗機場 (RMQ) 價格 (NTD)
  khh_price       integer,                                     -- 高雄小港機場 (KHH) 價格 (NTD)
  is_active       boolean     NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  -- 同一價目表下，地區 + 車型 不可重複
  UNIQUE (country, price_list_name, vehicle_type, region)
);

-- 常用查詢索引
CREATE INDEX IF NOT EXISTS idx_airport_pricing_lookup
  ON airport_transfer_pricing (country, vehicle_type, region, is_active);

CREATE INDEX IF NOT EXISTS idx_airport_pricing_price_list
  ON airport_transfer_pricing (country, price_list_name, is_active);

-- updated_at 自動更新 trigger
CREATE OR REPLACE FUNCTION update_airport_transfer_pricing_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_airport_transfer_pricing_updated_at
  BEFORE UPDATE ON airport_transfer_pricing
  FOR EACH ROW EXECUTE FUNCTION update_airport_transfer_pricing_updated_at();

-- ============================================================
-- RLS (Row Level Security)
-- ============================================================
ALTER TABLE airport_transfer_pricing ENABLE ROW LEVEL SECURITY;

-- service_role 可讀寫（後端 API 使用）
CREATE POLICY "service_role_full_access" ON airport_transfer_pricing
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- authenticated 使用者（公司端 web-admin 管理員）可讀寫
CREATE POLICY "authenticated_full_access" ON airport_transfer_pricing
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- anon 只能讀取 is_active = true 的資料（App 查詢定價使用）
CREATE POLICY "anon_read_active" ON airport_transfer_pricing
  FOR SELECT
  TO anon
  USING (is_active = true);

-- ============================================================
-- 備註說明
-- ============================================================
COMMENT ON TABLE airport_transfer_pricing IS '機場接送定價表。一行代表一個地區×車型組合，4個機場各為獨立欄位。';
COMMENT ON COLUMN airport_transfer_pricing.country IS '國家碼（ISO 3166-1 alpha-2），預設 TW（台灣）';
COMMENT ON COLUMN airport_transfer_pricing.price_list_name IS '價目表名稱，用於區分不同車型或期間的定價版本';
COMMENT ON COLUMN airport_transfer_pricing.vehicle_type IS '車型代碼：XS / S / M / L / XL';
COMMENT ON COLUMN airport_transfer_pricing.region IS '出發/目的地區域名稱（繁體中文）';
COMMENT ON COLUMN airport_transfer_pricing.tsa_price IS '台北松山機場（TSA）單程定價，新台幣';
COMMENT ON COLUMN airport_transfer_pricing.tpe_price IS '桃園國際機場（TPE）單程定價，新台幣';
COMMENT ON COLUMN airport_transfer_pricing.rmq_price IS '台中清泉崗機場（RMQ）單程定價，新台幣';
COMMENT ON COLUMN airport_transfer_pricing.khh_price IS '高雄小港機場（KHH）單程定價，新台幣';

-- ============================================================
-- 初始資料：機場接送五人座轎車價目表（車型 S）
-- ============================================================
INSERT INTO airport_transfer_pricing
  (country, price_list_name, vehicle_type, region, tsa_price, tpe_price, rmq_price, khh_price)
VALUES
  ('TW', '機場接送五人座轎車價目表', 'S', '雙北', 900,  1100, 3200, 6300),
  ('TW', '機場接送五人座轎車價目表', 'S', '桃園', 1100,  900, 2800, 5800),
  ('TW', '機場接送五人座轎車價目表', 'S', '新竹', 2200, 1700, 2400, 5300),
  ('TW', '機場接送五人座轎車價目表', 'S', '苗栗', 2700, 2400, 2200, 4900),
  ('TW', '機場接送五人座轎車價目表', 'S', '台中', 3200, 2800, 1500, 4300),
  ('TW', '機場接送五人座轎車價目表', 'S', '彰化', 3600, 3200, 2000, 4000),
  ('TW', '機場接送五人座轎車價目表', 'S', '南投', 4000, 3600, 2300, 4400),
  ('TW', '機場接送五人座轎車價目表', 'S', '雲林', 4200, 3800, 2500, 3500),
  ('TW', '機場接送五人座轎車價目表', 'S', '嘉義', 5000, 4400, 3000, 2800),
  ('TW', '機場接送五人座轎車價目表', 'S', '台南', 5700, 5200, 3800, 1700),
  ('TW', '機場接送五人座轎車價目表', 'S', '高雄', 6300, 5800, 4300,  900),
  ('TW', '機場接送五人座轎車價目表', 'S', '屏東', 7000, 6600, 4800, 1400),
  ('TW', '機場接送五人座轎車價目表', 'S', '墾丁', 8000, 7500, 5500, 2800),
  ('TW', '機場接送五人座轎車價目表', 'S', '基隆', 1700, 2200, 3700, 7000),
  ('TW', '機場接送五人座轎車價目表', 'S', '宜蘭', 2500, 3200, 4900, 7800),
  ('TW', '機場接送五人座轎車價目表', 'S', '花蓮', 5400, 6000, 7600, 8400),
  ('TW', '機場接送五人座轎車價目表', 'S', '台東', 7800, 8400, 7400, 4400)
ON CONFLICT (country, price_list_name, vehicle_type, region) DO UPDATE SET
  tsa_price  = EXCLUDED.tsa_price,
  tpe_price  = EXCLUDED.tpe_price,
  rmq_price  = EXCLUDED.rmq_price,
  khh_price  = EXCLUDED.khh_price,
  updated_at = now();
