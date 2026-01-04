-- 檢查並修復司機資料問題
-- 日期：2025-11-09
-- 問題：公司端手動派單功能 - 司機列表不顯示

-- ============================================
-- 第一部分: 檢查現有司機資料
-- ============================================

DO $$
DECLARE
    user_count INTEGER;
    profile_count INTEGER;
    driver_count INTEGER;
BEGIN
    -- 檢查 users 表中的司機數量
    SELECT COUNT(*) INTO user_count
    FROM users
    WHERE role = 'driver';
    
    -- 檢查 user_profiles 表中的司機資料數量
    SELECT COUNT(*) INTO profile_count
    FROM user_profiles
    WHERE user_id IN (SELECT id FROM users WHERE role = 'driver');
    
    -- 檢查 drivers 表中的司機數量
    SELECT COUNT(*) INTO driver_count
    FROM drivers;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 現有司機資料統計';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'users 表中的司機數量: %', user_count;
    RAISE NOTICE 'user_profiles 表中的司機資料數量: %', profile_count;
    RAISE NOTICE 'drivers 表中的司機數量: %', driver_count;
    RAISE NOTICE '========================================';
    
    -- 檢查是否有司機缺少 profile
    IF user_count > profile_count THEN
        RAISE WARNING '⚠️  有 % 位司機缺少 user_profiles 記錄', user_count - profile_count;
    ELSE
        RAISE NOTICE '✅ 所有司機都有 user_profiles 記錄';
    END IF;
    
    -- 檢查是否有司機缺少 drivers 記錄
    IF user_count > driver_count THEN
        RAISE WARNING '⚠️  有 % 位司機缺少 drivers 記錄', user_count - driver_count;
    ELSE
        RAISE NOTICE '✅ 所有司機都有 drivers 記錄';
    END IF;
END $$;

-- ============================================
-- 第二部分: 顯示司機詳細資料
-- ============================================

SELECT 
    u.id AS user_id,
    u.firebase_uid,
    u.email,
    u.role,
    u.status,
    p.id AS profile_id,
    p.first_name,
    p.last_name,
    p.phone,
    d.id AS driver_id,
    d.vehicle_type,
    d.vehicle_model,
    d.is_available,
    d.rating
FROM users u
LEFT JOIN user_profiles p ON u.id = p.user_id
LEFT JOIN drivers d ON u.id = d.user_id
WHERE u.role = 'driver'
ORDER BY u.created_at DESC;

-- ============================================
-- 第三部分: 為缺少 profile 的司機創建記錄
-- ============================================

-- 為現有司機創建 user_profiles 記錄（如果不存在）
INSERT INTO user_profiles (user_id, first_name, last_name, phone)
SELECT 
    u.id,
    '測試',
    '司機',
    COALESCE(u.phone, '0912345678')
FROM users u
WHERE u.role = 'driver'
  AND NOT EXISTS (
    SELECT 1 FROM user_profiles p WHERE p.user_id = u.id
  )
ON CONFLICT (user_id) DO NOTHING;

-- 驗證創建結果
DO $$
DECLARE
    created_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO created_count
    FROM user_profiles
    WHERE user_id IN (SELECT id FROM users WHERE role = 'driver');
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ user_profiles 記錄創建完成';
    RAISE NOTICE '========================================';
    RAISE NOTICE '現在有 % 條司機 profile 記錄', created_count;
    RAISE NOTICE '========================================';
END $$;

-- ============================================
-- 第四部分: 顯示更新後的司機列表
-- ============================================

SELECT 
    u.id AS user_id,
    u.email,
    CONCAT(p.first_name, ' ', p.last_name) AS name,
    p.phone,
    d.vehicle_type,
    d.vehicle_model,
    d.vehicle_plate,
    d.is_available,
    d.rating,
    d.total_trips
FROM users u
LEFT JOIN user_profiles p ON u.id = p.user_id
LEFT JOIN drivers d ON u.id = d.user_id
WHERE u.role = 'driver'
  AND u.status = 'active'
ORDER BY u.created_at DESC;

-- ============================================
-- 第五部分: 測試 API 查詢邏輯
-- ============================================

-- 模擬 API 的查詢邏輯
DO $$
DECLARE
    available_drivers_count INTEGER;
BEGIN
    -- 計算可用司機數量（模擬 API 邏輯）
    SELECT COUNT(*) INTO available_drivers_count
    FROM users u
    INNER JOIN user_profiles p ON u.id = p.user_id
    INNER JOIN drivers d ON u.id = d.user_id
    WHERE u.role = 'driver'
      AND u.status = 'active'
      AND d.is_available = true;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 API 查詢結果模擬';
    RAISE NOTICE '========================================';
    RAISE NOTICE '可用司機數量: %', available_drivers_count;
    RAISE NOTICE '========================================';
    
    IF available_drivers_count = 0 THEN
        RAISE WARNING '⚠️  沒有可用司機！請檢查：';
        RAISE WARNING '   1. 是否有司機的 is_available = true';
        RAISE WARNING '   2. 是否有司機的 status = active';
        RAISE WARNING '   3. 是否所有司機都有 user_profiles 記錄';
    ELSE
        RAISE NOTICE '✅ 找到 % 位可用司機', available_drivers_count;
    END IF;
END $$;

-- 顯示可用司機列表（模擬 API 返回）
SELECT 
    u.id AS user_id,
    u.email,
    CONCAT(p.first_name, ' ', p.last_name) AS driver_name,
    p.phone,
    d.vehicle_type,
    d.vehicle_model,
    d.vehicle_plate,
    d.rating,
    d.total_trips,
    d.is_available
FROM users u
INNER JOIN user_profiles p ON u.id = p.user_id
INNER JOIN drivers d ON u.id = d.user_id
WHERE u.role = 'driver'
  AND u.status = 'active'
  AND d.is_available = true
ORDER BY d.rating DESC, d.total_trips DESC;

