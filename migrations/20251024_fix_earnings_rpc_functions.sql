-- 修復 RPC 函數：將 display_name 改為 name
-- 執行日期: 2025-10-24

-- ============================================================================
-- 先刪除現有函數
-- ============================================================================
DROP FUNCTION IF EXISTS get_driver_earnings_ranking CASCADE;
DROP FUNCTION IF EXISTS get_all_drivers_earnings CASCADE;

-- ============================================================================
-- 4. 獲取司機收入排行榜
-- ============================================================================
CREATE OR REPLACE FUNCTION get_driver_earnings_ranking(
  p_start_date DATE,
  p_end_date DATE,
  p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
  rank BIGINT,
  driver_id UUID,
  driver_name VARCHAR,
  driver_email VARCHAR,
  total_earnings NUMERIC,
  total_orders BIGINT,
  average_earnings NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM (
    SELECT
      ROW_NUMBER() OVER (ORDER BY SUM(b.driver_earning) DESC) as rank,
      b.driver_id,
      COALESCE(u.raw_user_meta_data->>'displayName', u.email) as driver_name,
      u.email as driver_email,
      SUM(b.driver_earning) as total_earnings,
      COUNT(*) as total_orders,
      ROUND(AVG(b.driver_earning), 2) as average_earnings
    FROM bookings b
    INNER JOIN auth.users u ON b.driver_id = u.id
    WHERE b.status = 'completed'
      AND b.completed_at IS NOT NULL
      AND b.driver_id IS NOT NULL
      AND DATE(b.completed_at) BETWEEN p_start_date AND p_end_date
    GROUP BY b.driver_id, u.raw_user_meta_data, u.email
    ORDER BY SUM(b.driver_earning) DESC
    LIMIT p_limit
  ) ranking_data;
END;
$$;

-- ============================================================================
-- 5. 獲取所有司機收入統計（支援分頁和排序）
-- ============================================================================
CREATE OR REPLACE FUNCTION get_all_drivers_earnings(
  p_start_date DATE,
  p_end_date DATE,
  p_page INTEGER DEFAULT 1,
  p_limit INTEGER DEFAULT 10,
  p_sort_by VARCHAR DEFAULT 'earnings',
  p_sort_order VARCHAR DEFAULT 'desc'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_offset INTEGER;
  v_total_count INTEGER;
  v_total_pages INTEGER;
  v_result JSON;
BEGIN
  -- 計算偏移量
  v_offset := (p_page - 1) * p_limit;
  
  -- 計算總數
  SELECT COUNT(DISTINCT b.driver_id)
  INTO v_total_count
  FROM bookings b
  WHERE b.status = 'completed'
    AND b.completed_at IS NOT NULL
    AND b.driver_id IS NOT NULL
    AND DATE(b.completed_at) BETWEEN p_start_date AND p_end_date;
  
  -- 計算總頁數
  v_total_pages := CEIL(v_total_count::NUMERIC / p_limit);
  
  -- 構建結果
  SELECT json_build_object(
    'success', true,
    'data', json_build_object(
      'drivers', (
        SELECT COALESCE(json_agg(driver_data), '[]'::json)
        FROM (
          SELECT
            b.driver_id as "driverId",
            COALESCE(u.raw_user_meta_data->>'displayName', u.email) as "driverName",
            u.email as "driverEmail",
            SUM(b.driver_earning) as "totalEarnings",
            COUNT(*) as "totalOrders",
            ROUND(AVG(b.driver_earning), 2) as "averageEarnings"
          FROM bookings b
          INNER JOIN auth.users u ON b.driver_id = u.id
          WHERE b.status = 'completed'
            AND b.completed_at IS NOT NULL
            AND b.driver_id IS NOT NULL
            AND DATE(b.completed_at) BETWEEN p_start_date AND p_end_date
          GROUP BY b.driver_id, u.raw_user_meta_data, u.email
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
      'summary', (
        SELECT json_build_object(
          'totalEarnings', COALESCE(SUM(b.driver_earning), 0),
          'totalOrders', COUNT(*),
          'averageEarnings', COALESCE(ROUND(AVG(b.driver_earning), 2), 0),
          'activeDrivers', COUNT(DISTINCT b.driver_id)
        )
        FROM bookings b
        WHERE b.status = 'completed'
          AND b.completed_at IS NOT NULL
          AND b.driver_id IS NOT NULL
          AND DATE(b.completed_at) BETWEEN p_start_date AND p_end_date
      ),
      'pagination', json_build_object(
        'page', p_page,
        'limit', p_limit,
        'total', v_total_count,
        'totalPages', v_total_pages
      )
    )
  )
  INTO v_result;
  
  RETURN v_result;
END;
$$;

-- ============================================================================
-- 授權
-- ============================================================================

-- 授予 service_role 完整權限
GRANT EXECUTE ON FUNCTION get_driver_earnings_ranking TO service_role;
GRANT EXECUTE ON FUNCTION get_all_drivers_earnings TO service_role;

-- 授予 authenticated 用戶執行權限
GRANT EXECUTE ON FUNCTION get_driver_earnings_ranking TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_drivers_earnings TO authenticated;

-- ============================================================================
-- 完成
-- ============================================================================

