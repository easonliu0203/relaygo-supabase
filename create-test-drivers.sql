-- 創建測試司機資料
-- 日期：2025-11-09
-- 目的：修復公司端手動派單功能 - 沒有可選擇的司機

-- ============================================
-- 第一部分: 檢查現有司機資料
-- ============================================

DO $$
DECLARE
    driver_count INTEGER;
    user_count INTEGER;
    profile_count INTEGER;
BEGIN
    -- 檢查 users 表中的司機數量
    SELECT COUNT(*) INTO user_count
    FROM users
    WHERE role = 'driver';
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 現有司機資料統計';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'users 表中的司機數量: %', user_count;
    
    -- 檢查 drivers 表中的司機數量
    SELECT COUNT(*) INTO driver_count
    FROM drivers;
    
    RAISE NOTICE 'drivers 表中的司機數量: %', driver_count;
    
    -- 檢查 user_profiles 表中的司機資料數量
    SELECT COUNT(*) INTO profile_count
    FROM user_profiles
    WHERE user_id IN (SELECT id FROM users WHERE role = 'driver');
    
    RAISE NOTICE 'user_profiles 表中的司機資料數量: %', profile_count;
    RAISE NOTICE '========================================';
    
    -- 如果沒有司機，提示需要創建
    IF user_count = 0 THEN
        RAISE NOTICE '⚠️  沒有找到任何司機用戶，將創建測試司機';
    ELSE
        RAISE NOTICE '✅ 找到 % 位司機用戶', user_count;
    END IF;
END $$;

-- ============================================
-- 第二部分: 創建測試司機用戶
-- ============================================

-- 司機 1: 張三 (小型車 - 3-4人座)
INSERT INTO users (firebase_uid, email, phone, role, status, preferred_language)
VALUES (
    'test-driver-001',
    'driver1@relaygo.com',
    '0912345678',
    'driver',
    'active',
    'zh-TW'
)
ON CONFLICT (firebase_uid) DO UPDATE
SET 
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    status = EXCLUDED.status,
    updated_at = NOW();

-- 司機 2: 李四 (小型車 - 3-4人座)
INSERT INTO users (firebase_uid, email, phone, role, status, preferred_language)
VALUES (
    'test-driver-002',
    'driver2@relaygo.com',
    '0923456789',
    'driver',
    'active',
    'zh-TW'
)
ON CONFLICT (firebase_uid) DO UPDATE
SET 
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    status = EXCLUDED.status,
    updated_at = NOW();

-- 司機 3: 王五 (大型車 - 8-9人座)
INSERT INTO users (firebase_uid, email, phone, role, status, preferred_language)
VALUES (
    'test-driver-003',
    'driver3@relaygo.com',
    '0934567890',
    'driver',
    'active',
    'zh-TW'
)
ON CONFLICT (firebase_uid) DO UPDATE
SET 
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    status = EXCLUDED.status,
    updated_at = NOW();

-- 司機 4: 趙六 (大型車 - 8-9人座)
INSERT INTO users (firebase_uid, email, phone, role, status, preferred_language)
VALUES (
    'test-driver-004',
    'driver4@relaygo.com',
    '0945678901',
    'driver',
    'active',
    'zh-TW'
)
ON CONFLICT (firebase_uid) DO UPDATE
SET 
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    status = EXCLUDED.status,
    updated_at = NOW();

-- ============================================
-- 第三部分: 創建司機個人資料
-- ============================================

-- 司機 1 個人資料
INSERT INTO user_profiles (user_id, first_name, last_name, phone)
SELECT 
    id,
    '張',
    '三',
    '0912345678'
FROM users
WHERE firebase_uid = 'test-driver-001'
ON CONFLICT (user_id) DO UPDATE
SET 
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    phone = EXCLUDED.phone,
    updated_at = NOW();

-- 司機 2 個人資料
INSERT INTO user_profiles (user_id, first_name, last_name, phone)
SELECT 
    id,
    '李',
    '四',
    '0923456789'
FROM users
WHERE firebase_uid = 'test-driver-002'
ON CONFLICT (user_id) DO UPDATE
SET 
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    phone = EXCLUDED.phone,
    updated_at = NOW();

-- 司機 3 個人資料
INSERT INTO user_profiles (user_id, first_name, last_name, phone)
SELECT 
    id,
    '王',
    '五',
    '0934567890'
FROM users
WHERE firebase_uid = 'test-driver-003'
ON CONFLICT (user_id) DO UPDATE
SET 
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    phone = EXCLUDED.phone,
    updated_at = NOW();

-- 司機 4 個人資料
INSERT INTO user_profiles (user_id, first_name, last_name, phone)
SELECT 
    id,
    '趙',
    '六',
    '0945678901'
FROM users
WHERE firebase_uid = 'test-driver-004'
ON CONFLICT (user_id) DO UPDATE
SET 
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    phone = EXCLUDED.phone,
    updated_at = NOW();

-- ============================================
-- 第四部分: 創建司機詳細資料
-- ============================================

-- 司機 1 詳細資料 (小型車)
INSERT INTO drivers (
    user_id,
    license_number,
    license_expiry,
    vehicle_type,
    vehicle_model,
    vehicle_year,
    vehicle_plate,
    insurance_number,
    insurance_expiry,
    background_check_status,
    rating,
    total_trips,
    is_available
)
SELECT 
    id,
    'DL-001-2025',
    '2026-12-31'::DATE,
    'small',
    'Toyota Camry',
    2023,
    'ABC-1234',
    'INS-001-2025',
    '2026-06-30'::DATE,
    'approved',
    4.8,
    150,
    true
FROM users
WHERE firebase_uid = 'test-driver-001'
ON CONFLICT (user_id) DO UPDATE
SET 
    license_number = EXCLUDED.license_number,
    license_expiry = EXCLUDED.license_expiry,
    vehicle_type = EXCLUDED.vehicle_type,
    vehicle_model = EXCLUDED.vehicle_model,
    vehicle_year = EXCLUDED.vehicle_year,
    vehicle_plate = EXCLUDED.vehicle_plate,
    insurance_number = EXCLUDED.insurance_number,
    insurance_expiry = EXCLUDED.insurance_expiry,
    background_check_status = EXCLUDED.background_check_status,
    rating = EXCLUDED.rating,
    total_trips = EXCLUDED.total_trips,
    is_available = EXCLUDED.is_available,
    updated_at = NOW();

-- 司機 2 詳細資料 (小型車)
INSERT INTO drivers (
    user_id,
    license_number,
    license_expiry,
    vehicle_type,
    vehicle_model,
    vehicle_year,
    vehicle_plate,
    insurance_number,
    insurance_expiry,
    background_check_status,
    rating,
    total_trips,
    is_available
)
SELECT 
    id,
    'DL-002-2025',
    '2027-03-31'::DATE,
    'small',
    'Honda Accord',
    2022,
    'DEF-5678',
    'INS-002-2025',
    '2026-09-30'::DATE,
    'approved',
    4.6,
    120,
    true
FROM users
WHERE firebase_uid = 'test-driver-002'
ON CONFLICT (user_id) DO UPDATE
SET 
    license_number = EXCLUDED.license_number,
    license_expiry = EXCLUDED.license_expiry,
    vehicle_type = EXCLUDED.vehicle_type,
    vehicle_model = EXCLUDED.vehicle_model,
    vehicle_year = EXCLUDED.vehicle_year,
    vehicle_plate = EXCLUDED.vehicle_plate,
    insurance_number = EXCLUDED.insurance_number,
    insurance_expiry = EXCLUDED.insurance_expiry,
    background_check_status = EXCLUDED.background_check_status,
    rating = EXCLUDED.rating,
    total_trips = EXCLUDED.total_trips,
    is_available = EXCLUDED.is_available,
    updated_at = NOW();

-- 司機 3 詳細資料 (大型車)
INSERT INTO drivers (
    user_id,
    license_number,
    license_expiry,
    vehicle_type,
    vehicle_model,
    vehicle_year,
    vehicle_plate,
    insurance_number,
    insurance_expiry,
    background_check_status,
    rating,
    total_trips,
    is_available
)
SELECT 
    id,
    'DL-003-2025',
    '2026-08-31'::DATE,
    'large',
    'Mercedes-Benz Vito',
    2023,
    'GHI-9012',
    'INS-003-2025',
    '2026-12-31'::DATE,
    'approved',
    4.9,
    200,
    true
FROM users
WHERE firebase_uid = 'test-driver-003'
ON CONFLICT (user_id) DO UPDATE
SET 
    license_number = EXCLUDED.license_number,
    license_expiry = EXCLUDED.license_expiry,
    vehicle_type = EXCLUDED.vehicle_type,
    vehicle_model = EXCLUDED.vehicle_model,
    vehicle_year = EXCLUDED.vehicle_year,
    vehicle_plate = EXCLUDED.vehicle_plate,
    insurance_number = EXCLUDED.insurance_number,
    insurance_expiry = EXCLUDED.insurance_expiry,
    background_check_status = EXCLUDED.background_check_status,
    rating = EXCLUDED.rating,
    total_trips = EXCLUDED.total_trips,
    is_available = EXCLUDED.is_available,
    updated_at = NOW();

-- 司機 4 詳細資料 (大型車)
INSERT INTO drivers (
    user_id,
    license_number,
    license_expiry,
    vehicle_type,
    vehicle_model,
    vehicle_year,
    vehicle_plate,
    insurance_number,
    insurance_expiry,
    background_check_status,
    rating,
    total_trips,
    is_available
)
SELECT 
    id,
    'DL-004-2025',
    '2027-01-31'::DATE,
    'large',
    'Toyota Hiace',
    2022,
    'JKL-3456',
    'INS-004-2025',
    '2026-11-30'::DATE,
    'approved',
    4.7,
    180,
    true
FROM users
WHERE firebase_uid = 'test-driver-004'
ON CONFLICT (user_id) DO UPDATE
SET 
    license_number = EXCLUDED.license_number,
    license_expiry = EXCLUDED.license_expiry,
    vehicle_type = EXCLUDED.vehicle_type,
    vehicle_model = EXCLUDED.vehicle_model,
    vehicle_year = EXCLUDED.vehicle_year,
    vehicle_plate = EXCLUDED.vehicle_plate,
    insurance_number = EXCLUDED.insurance_number,
    insurance_expiry = EXCLUDED.insurance_expiry,
    background_check_status = EXCLUDED.background_check_status,
    rating = EXCLUDED.rating,
    total_trips = EXCLUDED.total_trips,
    is_available = EXCLUDED.is_available,
    updated_at = NOW();

-- ============================================
-- 第五部分: 驗證創建結果
-- ============================================

DO $$
DECLARE
    driver_count INTEGER;
    user_count INTEGER;
    profile_count INTEGER;
BEGIN
    -- 檢查 users 表中的司機數量
    SELECT COUNT(*) INTO user_count
    FROM users
    WHERE role = 'driver';
    
    -- 檢查 drivers 表中的司機數量
    SELECT COUNT(*) INTO driver_count
    FROM drivers;
    
    -- 檢查 user_profiles 表中的司機資料數量
    SELECT COUNT(*) INTO profile_count
    FROM user_profiles
    WHERE user_id IN (SELECT id FROM users WHERE role = 'driver');
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ 測試司機創建完成';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'users 表中的司機數量: %', user_count;
    RAISE NOTICE 'drivers 表中的司機數量: %', driver_count;
    RAISE NOTICE 'user_profiles 表中的司機資料數量: %', profile_count;
    RAISE NOTICE '========================================';
    
    -- 檢查是否所有司機都有完整資料
    IF user_count = driver_count AND driver_count = profile_count THEN
        RAISE NOTICE '✅ 所有司機都有完整的資料';
    ELSE
        RAISE WARNING '⚠️  部分司機缺少資料';
        RAISE WARNING '   users: %, drivers: %, profiles: %', user_count, driver_count, profile_count;
    END IF;
END $$;

-- ============================================
-- 第六部分: 顯示創建的司機列表
-- ============================================

SELECT 
    u.id,
    u.email,
    u.phone,
    u.status,
    CONCAT(p.first_name, ' ', p.last_name) AS name,
    d.vehicle_type,
    d.vehicle_model,
    d.vehicle_plate,
    d.rating,
    d.total_trips,
    d.is_available
FROM users u
LEFT JOIN user_profiles p ON u.id = p.user_id
LEFT JOIN drivers d ON u.id = d.user_id
WHERE u.role = 'driver'
ORDER BY u.created_at DESC;

