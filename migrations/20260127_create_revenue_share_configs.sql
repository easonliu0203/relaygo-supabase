-- ============================================
-- 創建多維度分潤配置表
-- ============================================
-- 創建日期: 2026-01-27
-- 用途: 支援基於國家、地區、服務類型、優惠碼狀態的細緻分潤配置
-- 向後兼容: 保留 system_settings 中的全局預設值作為回退
-- ============================================

-- 1. 創建分潤配置表
CREATE TABLE IF NOT EXISTS revenue_share_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- 配置維度
  country VARCHAR(2) NOT NULL,                    -- 國家代碼 (ISO 3166-1 alpha-2): TW, JP, KR, etc.
  region VARCHAR(100),                            -- 地區/城市: 台北市, 高雄市, 東京, etc. (NULL 表示全國通用)
  service_type VARCHAR(50) NOT NULL,              -- 服務類型: charter (包車旅遊), instant_ride (即時派車)
  has_promo_code BOOLEAN NOT NULL DEFAULT false,  -- 是否使用優惠碼
  
  -- 分潤百分比
  company_percentage DECIMAL(5,2) NOT NULL CHECK (company_percentage >= 0 AND company_percentage <= 100),
  driver_percentage DECIMAL(5,2) NOT NULL CHECK (driver_percentage >= 0 AND driver_percentage <= 100),
  company_base_percentage DECIMAL(5,2),           -- 使用優惠碼時的公司基準百分比 (推廣者佣金從此扣除)
  
  -- 配置狀態
  is_active BOOLEAN DEFAULT true,
  priority INTEGER DEFAULT 0,                     -- 優先級 (數字越大優先級越高，用於解決衝突)
  
  -- 元數據
  description TEXT,                               -- 配置說明
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by UUID REFERENCES users(id),
  updated_by UUID REFERENCES users(id),
  
  -- 唯一約束: 同一組合只能有一個啟用的配置
  CONSTRAINT unique_active_config UNIQUE (country, region, service_type, has_promo_code, is_active)
    WHERE is_active = true
);

-- 2. 添加檢查約束: 確保百分比總和為 100
ALTER TABLE revenue_share_configs
ADD CONSTRAINT check_percentage_sum 
CHECK (company_percentage + driver_percentage = 100);

-- 3. 創建索引以優化查詢
CREATE INDEX idx_revenue_share_country ON revenue_share_configs(country) WHERE is_active = true;
CREATE INDEX idx_revenue_share_region ON revenue_share_configs(region) WHERE is_active = true;
CREATE INDEX idx_revenue_share_service_type ON revenue_share_configs(service_type) WHERE is_active = true;
CREATE INDEX idx_revenue_share_promo ON revenue_share_configs(has_promo_code) WHERE is_active = true;
CREATE INDEX idx_revenue_share_priority ON revenue_share_configs(priority DESC) WHERE is_active = true;

-- 複合索引用於快速查詢
CREATE INDEX idx_revenue_share_lookup ON revenue_share_configs(
  country, region, service_type, has_promo_code, is_active, priority DESC
);

-- 4. 啟用 RLS (Row Level Security)
ALTER TABLE revenue_share_configs ENABLE ROW LEVEL SECURITY;

-- 5. 創建 RLS 策略
-- 允許 service_role 完全訪問
CREATE POLICY "Service role can do anything with revenue_share_configs"
ON revenue_share_configs
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- 允許已認證用戶讀取啟用的配置
CREATE POLICY "Authenticated users can read active configs"
ON revenue_share_configs
FOR SELECT
TO authenticated
USING (is_active = true);

-- 只有管理員可以修改配置 (需要在應用層檢查 admin 角色)
CREATE POLICY "Only admins can modify configs"
ON revenue_share_configs
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND 'admin' = ANY(users.roles)
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND 'admin' = ANY(users.roles)
  )
);

-- 6. 創建更新時間戳觸發器
CREATE OR REPLACE FUNCTION update_revenue_share_configs_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_revenue_share_configs_timestamp
BEFORE UPDATE ON revenue_share_configs
FOR EACH ROW
EXECUTE FUNCTION update_revenue_share_configs_updated_at();

-- 7. 插入預設配置 (向後兼容現有系統)
-- 台灣 - 包車旅遊 - 無優惠碼 (預設: 公司 25%, 司機 75%)
INSERT INTO revenue_share_configs (
  country, region, service_type, has_promo_code,
  company_percentage, driver_percentage,
  description, priority
) VALUES (
  'TW', NULL, 'charter', false,
  25, 75,
  '台灣全國 - 包車旅遊 - 未使用優惠碼 (預設配置)',
  0
);

-- 台灣 - 包車旅遊 - 使用優惠碼 (預設: 公司基準 30%, 司機 70%)
INSERT INTO revenue_share_configs (
  country, region, service_type, has_promo_code,
  company_percentage, driver_percentage, company_base_percentage,
  description, priority
) VALUES (
  'TW', NULL, 'charter', true,
  30, 70, 30,
  '台灣全國 - 包車旅遊 - 使用優惠碼 (預設配置，推廣者佣金從公司基準扣除)',
  0
);

-- 8. 創建查詢函數: 根據訂單條件查找最佳匹配的分潤配置
CREATE OR REPLACE FUNCTION get_revenue_share_config(
  p_country VARCHAR(2),
  p_region VARCHAR(100),
  p_service_type VARCHAR(50),
  p_has_promo_code BOOLEAN
)
RETURNS TABLE (
  id UUID,
  company_percentage DECIMAL(5,2),
  driver_percentage DECIMAL(5,2),
  company_base_percentage DECIMAL(5,2),
  description TEXT
) AS $$
BEGIN
  -- 優先級查詢順序:
  -- 1. 精確匹配: 國家 + 地區 + 服務類型 + 優惠碼狀態
  -- 2. 國家 + 服務類型 + 優惠碼狀態 (忽略地區)
  -- 3. 回退到 system_settings 的全局配置
  
  RETURN QUERY
  SELECT 
    rsc.id,
    rsc.company_percentage,
    rsc.driver_percentage,
    rsc.company_base_percentage,
    rsc.description
  FROM revenue_share_configs rsc
  WHERE rsc.is_active = true
    AND rsc.country = p_country
    AND (rsc.region = p_region OR rsc.region IS NULL)
    AND rsc.service_type = p_service_type
    AND rsc.has_promo_code = p_has_promo_code
  ORDER BY 
    -- 優先選擇有地區指定的配置
    CASE WHEN rsc.region IS NOT NULL THEN 1 ELSE 0 END DESC,
    -- 然後按優先級排序
    rsc.priority DESC,
    -- 最後按創建時間排序 (最新的優先)
    rsc.created_at DESC
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- 9. 添加註釋
COMMENT ON TABLE revenue_share_configs IS '多維度分潤配置表 - 支援基於國家、地區、服務類型、優惠碼狀態的細緻分潤設定';
COMMENT ON COLUMN revenue_share_configs.country IS '國家代碼 (ISO 3166-1 alpha-2)';
COMMENT ON COLUMN revenue_share_configs.region IS '地區/城市 (NULL 表示全國通用)';
COMMENT ON COLUMN revenue_share_configs.service_type IS '服務類型: charter (包車旅遊), instant_ride (即時派車)';
COMMENT ON COLUMN revenue_share_configs.has_promo_code IS '是否使用優惠碼';
COMMENT ON COLUMN revenue_share_configs.company_base_percentage IS '使用優惠碼時的公司基準百分比 (推廣者佣金從此扣除)';
COMMENT ON COLUMN revenue_share_configs.priority IS '優先級 (數字越大優先級越高)';
COMMENT ON FUNCTION get_revenue_share_config IS '根據訂單條件查找最佳匹配的分潤配置';

