-- ============================================
-- affiliate_links: 聯盟推廣連結資料表
-- 存放各聯盟夥伴（Trip.com, Klook 等）的推廣連結
-- 供 AI 行程規劃師在產出行程時自然嵌入
-- ============================================

CREATE TABLE IF NOT EXISTS affiliate_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- 聯盟夥伴識別
    provider VARCHAR(50) NOT NULL,              -- 聯盟夥伴代碼：trip_com, klook, kkday 等
    provider_name VARCHAR(100) NOT NULL,        -- 顯示名稱：Trip.com, Klook 等

    -- 連結分類
    category VARCHAR(50) NOT NULL               -- 類別：flight, hotel, ticket, activity, car_rental, train, bus, insurance
        CHECK (category IN ('flight', 'hotel', 'ticket', 'activity', 'car_rental', 'train', 'bus', 'insurance', 'other')),

    -- 連結名稱（多語）
    name VARCHAR(200) NOT NULL,                 -- 預設顯示名稱
    name_i18n JSONB DEFAULT '{}'::jsonb,        -- 多語名稱 {"zh-TW":"機票搜尋","en":"Flight Search","ja":"航空券検索","ko":"항공권 검색"}

    -- 連結 URL
    url_template TEXT NOT NULL,                 -- URL 模板，可含變數 {city}, {checkin}, {checkout}, {lang}, {from}, {to}, {date}

    -- 網站語言（該連結適用的語言版本）
    site_language VARCHAR(10) DEFAULT 'zh-TW',  -- 連結網站的語言版本：zh-TW, en, ja, ko 等

    -- AI 用描述（告訴 AI 何時該推薦此連結）
    description TEXT,                           -- 例如：「當用戶詢問機票或需要訂機票時推薦」

    -- 適用地區
    regions TEXT[] DEFAULT ARRAY['ALL']::TEXT[], -- 適用地區代碼：TW, JP, KR, TH, ALL 等

    -- 排序與狀態
    priority INTEGER DEFAULT 0,                 -- 同類別中的優先級（越大越優先）
    is_active BOOLEAN DEFAULT true,             -- 是否啟用

    -- 時間戳
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 建立索引：按類別+啟用狀態查詢（最常見查詢）
CREATE INDEX IF NOT EXISTS idx_affiliate_links_category_active
    ON affiliate_links(category, is_active, priority DESC)
    WHERE is_active = true;

-- 建立索引：按供應商查詢
CREATE INDEX IF NOT EXISTS idx_affiliate_links_provider
    ON affiliate_links(provider, is_active)
    WHERE is_active = true;

-- 自動更新 updated_at 觸發器
CREATE OR REPLACE FUNCTION update_affiliate_links_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_affiliate_links_updated_at
    BEFORE UPDATE ON affiliate_links
    FOR EACH ROW
    EXECUTE FUNCTION update_affiliate_links_updated_at();

-- 啟用 RLS
ALTER TABLE affiliate_links ENABLE ROW LEVEL SECURITY;

-- RLS 政策：service_role 完全存取
CREATE POLICY "Service role full access on affiliate_links"
    ON affiliate_links
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- RLS 政策：匿名/已認證用戶可讀取啟用的連結
CREATE POLICY "Anyone can read active affiliate_links"
    ON affiliate_links
    FOR SELECT
    TO anon, authenticated
    USING (is_active = true);

-- 添加表描述
COMMENT ON TABLE affiliate_links IS '聯盟推廣連結資料表，供 AI 行程規劃師嵌入推廣連結';
COMMENT ON COLUMN affiliate_links.provider IS '聯盟夥伴代碼，如 trip_com, klook, kkday';
COMMENT ON COLUMN affiliate_links.category IS '連結類別：flight/hotel/ticket/activity/car_rental/train/bus/insurance/other';
COMMENT ON COLUMN affiliate_links.url_template IS 'URL 模板，支援變數替換：{city}, {checkin}, {checkout}, {lang}, {from}, {to}, {date}';
COMMENT ON COLUMN affiliate_links.site_language IS '連結網站的語言版本，如 zh-TW, en, ja, ko';
COMMENT ON COLUMN affiliate_links.regions IS '適用地區代碼陣列，ALL 表示全球適用';
COMMENT ON COLUMN affiliate_links.priority IS '排序優先級，數字越大越優先';
