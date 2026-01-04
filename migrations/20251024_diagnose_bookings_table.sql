-- ============================================
-- 診斷 bookings 表結構
-- ============================================

-- 檢查 bookings 表是否存在
SELECT 
  CASE 
    WHEN EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'bookings')
    THEN '✅ bookings 表存在'
    ELSE '❌ bookings 表不存在'
  END as table_status;

-- 列出 bookings 表的所有欄位
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'bookings'
ORDER BY ordinal_position;

-- 檢查 completed_at 欄位是否存在
SELECT 
  CASE 
    WHEN EXISTS (
      SELECT FROM information_schema.columns 
      WHERE table_schema = 'public' 
        AND table_name = 'bookings' 
        AND column_name = 'completed_at'
    )
    THEN '✅ completed_at 欄位存在'
    ELSE '❌ completed_at 欄位不存在'
  END as completed_at_status;

-- 檢查其他關鍵欄位
SELECT 
  column_name,
  CASE 
    WHEN EXISTS (
      SELECT FROM information_schema.columns 
      WHERE table_schema = 'public' 
        AND table_name = 'bookings' 
        AND column_name = c.column_name
    )
    THEN '✅ 存在'
    ELSE '❌ 不存在'
  END as status
FROM (
  VALUES 
    ('driver_id'),
    ('status'),
    ('completed_at'),
    ('driver_earning'),
    ('platform_fee'),
    ('total_amount')
) AS c(column_name);

