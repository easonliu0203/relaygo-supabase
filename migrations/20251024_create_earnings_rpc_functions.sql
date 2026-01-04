-- ============================================
-- 財務報表系統 - RPC 函數
-- 建立日期: 2025-10-24
-- 用途: 提供伺服器端聚合計算的財務統計功能
-- ============================================
-- 注意：執行此文件前，請先執行 20251024_add_financial_columns.sql
-- ============================================

-- ============================================
-- 1. get_driver_earnings - 獲取司機收入統計
-- ============================================

CREATE OR REPLACE FUNCTION get_driver_earnings(
  p_driver_id UUID,
  p_start_date DATE,
  p_end_date DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  -- 計算司機收入統計
  SELECT json_build_object(
    'totalEarnings', COALESCE(SUM(driver_earning), 0),
    'totalOrders', COUNT(*),
    'averageEarnings', COALESCE(AVG(driver_earning), 0),
    'dailyEarnings', (
      SELECT json_agg(daily_data ORDER BY date)
      FROM (
        SELECT 
          DATE(completed_at) as date,
          SUM(driver_earning) as earnings,
          COUNT(*) as orders
        FROM bookings
        WHERE driver_id = p_driver_id
          AND status = 'completed'
          AND completed_at IS NOT NULL
          AND DATE(completed_at) BETWEEN p_start_date AND p_end_date
        GROUP BY DATE(completed_at)
        ORDER BY DATE(completed_at)
      ) daily_data
    )
  ) INTO v_result
  FROM bookings
  WHERE driver_id = p_driver_id
    AND status = 'completed'
    AND completed_at IS NOT NULL
    AND DATE(completed_at) BETWEEN p_start_date AND p_end_date;

  RETURN v_result;
END;
$$;

-- 添加函數註釋
COMMENT ON FUNCTION get_driver_earnings IS '獲取指定司機在指定時間範圍內的收入統計';

-- ============================================
-- 2. get_platform_earnings - 獲取平台收入統計
-- ============================================

CREATE OR REPLACE FUNCTION get_platform_earnings(
  p_start_date DATE,
  p_end_date DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  -- 計算平台收入統計
  SELECT json_build_object(
    'totalPlatformFee', COALESCE(SUM(platform_fee), 0),
    'totalRevenue', COALESCE(SUM(total_amount), 0),
    'totalOrders', COUNT(*),
    'averageCommissionRate', COALESCE(
      AVG(platform_fee / NULLIF(total_amount, 0)), 
      0
    ),
    'dailyEarnings', (
      SELECT json_agg(daily_data ORDER BY date)
      FROM (
        SELECT 
          DATE(completed_at) as date,
          SUM(platform_fee) as platform_fee,
          SUM(total_amount) as revenue,
          COUNT(*) as orders
        FROM bookings
        WHERE status = 'completed'
          AND completed_at IS NOT NULL
          AND DATE(completed_at) BETWEEN p_start_date AND p_end_date
        GROUP BY DATE(completed_at)
        ORDER BY DATE(completed_at)
      ) daily_data
    )
  ) INTO v_result
  FROM bookings
  WHERE status = 'completed'
    AND completed_at IS NOT NULL
    AND DATE(completed_at) BETWEEN p_start_date AND p_end_date;

  RETURN v_result;
END;
$$;

-- 添加函數註釋
COMMENT ON FUNCTION get_platform_earnings IS '獲取平台在指定時間範圍內的抽成收入統計';

-- ============================================
-- 3. get_daily_earnings_summary - 獲取每日收入摘要
-- ============================================

CREATE OR REPLACE FUNCTION get_daily_earnings_summary(
  p_start_date DATE,
  p_end_date DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  -- 計算每日收入摘要
  SELECT json_agg(daily_data ORDER BY date)
  INTO v_result
  FROM (
    SELECT 
      DATE(completed_at) as date,
      SUM(total_amount) as total_revenue,
      SUM(driver_earning) as driver_earnings,
      SUM(platform_fee) as platform_fee,
      COUNT(*) as orders,
      COUNT(DISTINCT driver_id) as drivers_count
    FROM bookings
    WHERE status = 'completed'
      AND completed_at IS NOT NULL
      AND DATE(completed_at) BETWEEN p_start_date AND p_end_date
    GROUP BY DATE(completed_at)
    ORDER BY DATE(completed_at)
  ) daily_data;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

-- 添加函數註釋
COMMENT ON FUNCTION get_daily_earnings_summary IS '獲取指定時間範圍內每日的收入摘要';

-- ============================================
-- 4. get_driver_earnings_ranking - 獲取司機收入排行
-- ============================================

CREATE OR REPLACE FUNCTION get_driver_earnings_ranking(
  p_start_date DATE,
  p_end_date DATE,
  p_limit INTEGER DEFAULT 10
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  -- 計算司機收入排行
  SELECT json_agg(ranking_data ORDER BY rank)
  INTO v_result
  FROM (
    SELECT
      ROW_NUMBER() OVER (ORDER BY SUM(b.driver_earning) DESC) as rank,
      b.driver_id,
      u.name as driver_name,
      u.email as driver_email,
      SUM(b.driver_earning) as total_earnings,
      COUNT(*) as total_orders,
      AVG(b.driver_earning) as average_earnings
    FROM bookings b
    LEFT JOIN users u ON b.driver_id = u.id
    WHERE b.status = 'completed'
      AND b.completed_at IS NOT NULL
      AND b.driver_id IS NOT NULL
      AND DATE(b.completed_at) BETWEEN p_start_date AND p_end_date
    GROUP BY b.driver_id, u.name, u.email
    ORDER BY SUM(b.driver_earning) DESC
    LIMIT p_limit
  ) ranking_data;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

-- 添加函數註釋
COMMENT ON FUNCTION get_driver_earnings_ranking IS '獲取指定時間範圍內司機收入排行榜';

-- ============================================
-- 5. get_all_drivers_earnings - 獲取所有司機收入統計（支援分頁）
-- ============================================

CREATE OR REPLACE FUNCTION get_all_drivers_earnings(
  p_start_date DATE,
  p_end_date DATE,
  p_page INTEGER DEFAULT 1,
  p_limit INTEGER DEFAULT 10,
  p_sort_by TEXT DEFAULT 'earnings',
  p_sort_order TEXT DEFAULT 'desc'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
  v_offset INTEGER;
  v_total_count INTEGER;
BEGIN
  -- 計算偏移量
  v_offset := (p_page - 1) * p_limit;

  -- 獲取總數
  SELECT COUNT(DISTINCT driver_id)
  INTO v_total_count
  FROM bookings
  WHERE status = 'completed'
    AND completed_at IS NOT NULL
    AND driver_id IS NOT NULL
    AND DATE(completed_at) BETWEEN p_start_date AND p_end_date;

  -- 計算所有司機收入統計（支援排序和分頁）
  SELECT json_build_object(
    'drivers', (
      SELECT json_agg(driver_data)
      FROM (
        SELECT
          b.driver_id as "driverId",
          u.name as "driverName",
          u.email as "driverEmail",
          SUM(b.driver_earning) as "totalEarnings",
          COUNT(*) as "totalOrders",
          AVG(b.driver_earning) as "averageEarnings"
        FROM bookings b
        LEFT JOIN users u ON b.driver_id = u.id
        WHERE b.status = 'completed'
          AND b.completed_at IS NOT NULL
          AND b.driver_id IS NOT NULL
          AND DATE(b.completed_at) BETWEEN p_start_date AND p_end_date
        GROUP BY b.driver_id, u.name, u.email
        ORDER BY 
          CASE 
            WHEN p_sort_by = 'earnings' AND p_sort_order = 'desc' THEN SUM(b.driver_earning)
          END DESC,
          CASE 
            WHEN p_sort_by = 'earnings' AND p_sort_order = 'asc' THEN SUM(b.driver_earning)
          END ASC,
          CASE 
            WHEN p_sort_by = 'orders' AND p_sort_order = 'desc' THEN COUNT(*)
          END DESC,
          CASE 
            WHEN p_sort_by = 'orders' AND p_sort_order = 'asc' THEN COUNT(*)
          END ASC,
          CASE 
            WHEN p_sort_by = 'average' AND p_sort_order = 'desc' THEN AVG(b.driver_earning)
          END DESC,
          CASE 
            WHEN p_sort_by = 'average' AND p_sort_order = 'asc' THEN AVG(b.driver_earning)
          END ASC
        LIMIT p_limit
        OFFSET v_offset
      ) driver_data
    ),
    'pagination', json_build_object(
      'page', p_page,
      'limit', p_limit,
      'total', v_total_count,
      'totalPages', CEIL(v_total_count::DECIMAL / p_limit)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- 添加函數註釋
COMMENT ON FUNCTION get_all_drivers_earnings IS '獲取所有司機收入統計（支援分頁和排序）';

-- ============================================
-- 建立索引以優化查詢效能
-- ============================================

-- 司機 ID 索引
CREATE INDEX IF NOT EXISTS idx_bookings_driver_id 
ON bookings(driver_id) 
WHERE driver_id IS NOT NULL;

-- 完成時間索引
CREATE INDEX IF NOT EXISTS idx_bookings_completed_at 
ON bookings(completed_at) 
WHERE completed_at IS NOT NULL;

-- 複合索引（司機 + 狀態 + 完成時間）
CREATE INDEX IF NOT EXISTS idx_bookings_driver_status_completed 
ON bookings(driver_id, status, completed_at) 
WHERE driver_id IS NOT NULL AND completed_at IS NOT NULL;

-- 複合索引（狀態 + 完成時間）
CREATE INDEX IF NOT EXISTS idx_bookings_status_completed 
ON bookings(status, completed_at) 
WHERE completed_at IS NOT NULL;

-- ============================================
-- 授予權限
-- ============================================

-- 授予 authenticated 用戶執行這些函數的權限
GRANT EXECUTE ON FUNCTION get_driver_earnings TO authenticated;
GRANT EXECUTE ON FUNCTION get_platform_earnings TO authenticated;
GRANT EXECUTE ON FUNCTION get_daily_earnings_summary TO authenticated;
GRANT EXECUTE ON FUNCTION get_driver_earnings_ranking TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_drivers_earnings TO authenticated;

-- ============================================
-- 測試查詢範例
-- ============================================

-- 測試 get_driver_earnings
-- SELECT get_driver_earnings(
--   'driver-uuid-here'::UUID,
--   '2025-10-01'::DATE,
--   '2025-10-31'::DATE
-- );

-- 測試 get_platform_earnings
-- SELECT get_platform_earnings(
--   '2025-10-01'::DATE,
--   '2025-10-31'::DATE
-- );

-- 測試 get_daily_earnings_summary
-- SELECT get_daily_earnings_summary(
--   '2025-10-01'::DATE,
--   '2025-10-31'::DATE
-- );

-- 測試 get_driver_earnings_ranking
-- SELECT get_driver_earnings_ranking(
--   '2025-10-01'::DATE,
--   '2025-10-31'::DATE,
--   10
-- );

-- 測試 get_all_drivers_earnings
-- SELECT get_all_drivers_earnings(
--   '2025-10-01'::DATE,
--   '2025-10-31'::DATE,
--   1,  -- page
--   10, -- limit
--   'earnings', -- sort_by
--   'desc' -- sort_order
-- );

