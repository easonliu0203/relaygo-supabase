-- ============================================================
-- 新增 airport_transfer_vehicle_types 表
-- 將車型元資料（名稱、容量、i18n）從 pricing 表中抽離
-- 透過 (country, vehicle_type) 與 airport_transfer_pricing 關聯
-- ============================================================

CREATE TABLE IF NOT EXISTS airport_transfer_vehicle_types (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  country              TEXT NOT NULL DEFAULT 'TW',
  vehicle_type         TEXT NOT NULL,                          -- XS / S / M / L / XL
  price_list_name      TEXT NOT NULL,                          -- 中文 fallback
  price_list_name_i18n JSONB DEFAULT '{}'::jsonb,              -- {"zh-TW":"...","en":"...",...}
  capacity_info        TEXT,                                    -- 中文 fallback
  capacity_info_i18n   JSONB DEFAULT '{}'::jsonb,              -- {"zh-TW":"...","en":"...",...}
  display_order        INTEGER DEFAULT 0,
  is_active            BOOLEAN NOT NULL DEFAULT true,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (country, vehicle_type)
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_airport_vt_lookup
  ON airport_transfer_vehicle_types (country, is_active, display_order);

-- GIN 索引（i18n JSONB 查詢用）
CREATE INDEX IF NOT EXISTS idx_airport_vt_price_list_name_i18n
  ON airport_transfer_vehicle_types USING GIN (price_list_name_i18n);

CREATE INDEX IF NOT EXISTS idx_airport_vt_capacity_info_i18n
  ON airport_transfer_vehicle_types USING GIN (capacity_info_i18n);

-- updated_at 自動更新觸發器（複用已有的 function）
CREATE TRIGGER trg_airport_transfer_vehicle_types_updated_at
  BEFORE UPDATE ON airport_transfer_vehicle_types
  FOR EACH ROW EXECUTE FUNCTION update_airport_transfer_pricing_updated_at();

-- ============================================================
-- 種子資料（TW 4 筆）
-- ============================================================
INSERT INTO airport_transfer_vehicle_types
  (country, vehicle_type, price_list_name, capacity_info, display_order)
VALUES
  ('TW', 'S',  '機場接送五人座轎車',   '最多3人，行李2件',         1),
  ('TW', 'M',  '機場接送五人座休旅車', '最多3人，行李3件',         2),
  ('TW', 'L',  '機場接送九人座',       '最多6人，行李5件',         3),
  ('TW', 'XL', '機場接送Alphard',      '最多6人，行李5件（豪華）',  4)
ON CONFLICT (country, vehicle_type) DO NOTHING;

-- 驗證
SELECT vehicle_type, price_list_name, capacity_info, display_order
FROM airport_transfer_vehicle_types
WHERE country = 'TW'
ORDER BY display_order;
