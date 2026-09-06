-- ============================================================
-- 新增 region_definitions 表
-- 座標 bounding box 判定地區，取代純中文文字比對
-- 用於機場接送定價的地區識別（18 個台灣地區）
-- ============================================================

CREATE TABLE IF NOT EXISTS region_definitions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  country          TEXT NOT NULL DEFAULT 'TW',
  region_key       TEXT NOT NULL,                          -- pricing key：台北/新北/桃園/...
  region_name_i18n JSONB DEFAULT '{}'::jsonb,              -- {"zh-TW":"台北","en":"Taipei",...}
  min_lat          NUMERIC(9,6) NOT NULL,
  max_lat          NUMERIC(9,6) NOT NULL,
  min_lng          NUMERIC(9,6) NOT NULL,
  max_lng          NUMERIC(9,6) NOT NULL,
  priority         INTEGER DEFAULT 0,                      -- 數字越大優先（墾丁 > 屏東）
  is_active        BOOLEAN NOT NULL DEFAULT true,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (country, region_key)
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_region_def_lookup
  ON region_definitions (country, is_active);

-- updated_at 自動更新觸發器
CREATE TRIGGER trg_region_definitions_updated_at
  BEFORE UPDATE ON region_definitions
  FOR EACH ROW EXECUTE FUNCTION update_airport_transfer_pricing_updated_at();

-- ============================================================
-- 種子資料（TW 18 筆）
-- priority: 墾丁(10) > 基隆(5) > 一般縣市(1) > 新北/屏東(0)
-- 當座標落在重疊區域時，priority 高的優先
-- ============================================================
INSERT INTO region_definitions
  (country, region_key, region_name_i18n, min_lat, max_lat, min_lng, max_lng, priority)
VALUES
  ('TW', '墾丁', '{"zh-TW":"墾丁","en":"Kenting","ja":"ケンティン","ko":"컨딩","zh-CN":"垦丁","vi":"Khẩn Đinh","th":"เคินติง","id":"Kenting"}',
    21.870000, 22.100000, 120.650000, 120.880000, 10),

  ('TW', '基隆', '{"zh-TW":"基隆","en":"Keelung","ja":"基隆","ko":"지룽","zh-CN":"基隆","vi":"Cơ Long","th":"จีหลง","id":"Keelung"}',
    25.080000, 25.220000, 121.620000, 121.820000, 5),

  ('TW', '台北', '{"zh-TW":"台北","en":"Taipei","ja":"台北","ko":"타이베이","zh-CN":"台北","vi":"Đài Bắc","th":"ไทเป","id":"Taipei"}',
    24.960000, 25.210000, 121.430000, 121.670000, 1),

  ('TW', '新北', '{"zh-TW":"新北","en":"New Taipei","ja":"新北","ko":"신베이","zh-CN":"新北","vi":"Tân Bắc","th":"นิวไทเป","id":"New Taipei"}',
    24.670000, 25.300000, 121.280000, 122.010000, 0),

  ('TW', '桃園', '{"zh-TW":"桃園","en":"Taoyuan","ja":"桃園","ko":"타오위안","zh-CN":"桃园","vi":"Đào Viên","th":"เถาหยวน","id":"Taoyuan"}',
    24.730000, 25.120000, 120.970000, 121.410000, 1),

  ('TW', '新竹', '{"zh-TW":"新竹","en":"Hsinchu","ja":"新竹","ko":"신주","zh-CN":"新竹","vi":"Tân Trúc","th":"ซินจู๋","id":"Hsinchu"}',
    24.580000, 24.880000, 120.870000, 121.230000, 1),

  ('TW', '苗栗', '{"zh-TW":"苗栗","en":"Miaoli","ja":"苗栗","ko":"먀오리","zh-CN":"苗栗","vi":"Miêu Lật","th":"เหมียวลี่","id":"Miaoli"}',
    24.300000, 24.680000, 120.620000, 121.150000, 1),

  ('TW', '台中', '{"zh-TW":"台中","en":"Taichung","ja":"台中","ko":"타이중","zh-CN":"台中","vi":"Đài Trung","th":"ไถจง","id":"Taichung"}',
    24.030000, 24.450000, 120.470000, 121.000000, 1),

  ('TW', '彰化', '{"zh-TW":"彰化","en":"Changhua","ja":"彰化","ko":"장화","zh-CN":"彰化","vi":"Chương Hóa","th":"จางฮว่า","id":"Changhua"}',
    23.820000, 24.180000, 120.280000, 120.680000, 1),

  ('TW', '南投', '{"zh-TW":"南投","en":"Nantou","ja":"南投","ko":"난터우","zh-CN":"南投","vi":"Nam Đầu","th":"หนานโถว","id":"Nantou"}',
    23.480000, 24.120000, 120.380000, 121.250000, 1),

  ('TW', '雲林', '{"zh-TW":"雲林","en":"Yunlin","ja":"雲林","ko":"윈린","zh-CN":"云林","vi":"Vân Lâm","th":"หยุนหลิน","id":"Yunlin"}',
    23.480000, 23.820000, 120.080000, 120.600000, 1),

  ('TW', '嘉義', '{"zh-TW":"嘉義","en":"Chiayi","ja":"嘉義","ko":"자이","zh-CN":"嘉义","vi":"Gia Nghĩa","th":"เจียอี้","id":"Chiayi"}',
    23.260000, 23.580000, 120.150000, 120.780000, 1),

  ('TW', '台南', '{"zh-TW":"台南","en":"Tainan","ja":"台南","ko":"타이난","zh-CN":"台南","vi":"Đài Nam","th":"ไถหนาน","id":"Tainan"}',
    22.880000, 23.380000, 120.050000, 120.580000, 1),

  ('TW', '高雄', '{"zh-TW":"高雄","en":"Kaohsiung","ja":"高雄","ko":"가오슝","zh-CN":"高雄","vi":"Cao Hùng","th":"เกาสง","id":"Kaohsiung"}',
    22.470000, 23.050000, 120.150000, 120.850000, 1),

  ('TW', '屏東', '{"zh-TW":"屏東","en":"Pingtung","ja":"屏東","ko":"핑둥","zh-CN":"屏东","vi":"Bình Đông","th":"ผิงตง","id":"Pingtung"}',
    21.870000, 22.680000, 120.380000, 120.950000, 0),

  ('TW', '宜蘭', '{"zh-TW":"宜蘭","en":"Yilan","ja":"宜蘭","ko":"이란","zh-CN":"宜兰","vi":"Nghi Lan","th":"อี๋หลาน","id":"Yilan"}',
    24.300000, 24.830000, 121.550000, 121.950000, 1),

  ('TW', '花蓮', '{"zh-TW":"花蓮","en":"Hualien","ja":"花蓮","ko":"화롄","zh-CN":"花莲","vi":"Hoa Liên","th":"ฮวาเหลียน","id":"Hualien"}',
    23.300000, 24.380000, 121.100000, 121.650000, 1),

  ('TW', '台東', '{"zh-TW":"台東","en":"Taitung","ja":"台東","ko":"타이둥","zh-CN":"台东","vi":"Đài Đông","th":"ไถตง","id":"Taitung"}',
    22.300000, 23.450000, 120.700000, 121.250000, 1)

ON CONFLICT (country, region_key) DO NOTHING;

-- 驗證
SELECT region_key, priority, min_lat, max_lat, min_lng, max_lng
FROM region_definitions
WHERE country = 'TW'
ORDER BY priority DESC, region_key;
