-- 新增自拍照片和多元登記證文件類型
-- 日期：2026-01-28
-- 目的：支持司機端 App 上傳自拍照片和多元登記證

-- ============================================
-- 第一部分: 更新 driver_documents 表的 CHECK 約束
-- ============================================

-- 1. 刪除舊的 CHECK 約束
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'driver_documents_type_check'
  ) THEN
    ALTER TABLE driver_documents DROP CONSTRAINT driver_documents_type_check;
  END IF;
END $$;

-- 2. 添加新的 CHECK 約束，支持 9 種文件類型（新增 selfie_photo 和 taxi_permit）
ALTER TABLE driver_documents
ADD CONSTRAINT driver_documents_type_check
CHECK (type IN (
  'selfie_photo',           -- 自拍照片（清楚且不遮額頭）- 新增
  'id_card_front',          -- 身分證（正面）
  'id_card_back',           -- 身分證（背面）
  'drivers_license',        -- 駕照
  'vehicle_registration',   -- 行照
  'taxi_permit',            -- 多元登記證（即時接單必須）- 新增
  'insurance_policy',       -- 保險單
  'police_clearance',       -- 良民證
  'no_accident_record',     -- 無肇事紀錄
  -- 保留舊的類型名稱以兼容現有數據
  'id_card',                -- 舊：身分證（未拆分）
  'license',                -- 舊：駕照
  'insurance'               -- 舊：保險單
));

-- ============================================
-- 第二部分: 更新表註釋
-- ============================================

COMMENT ON COLUMN driver_documents.type IS '文件類型：selfie_photo（自拍照片）、id_card_front（身分證正面）、id_card_back（身分證背面）、drivers_license（駕照）、vehicle_registration（行照）、taxi_permit（多元登記證）、insurance_policy（保險單）、police_clearance（良民證）、no_accident_record（無肇事紀錄）';

-- ============================================
-- 完成
-- ============================================

DO $$
BEGIN
  RAISE NOTICE '✅ driver_documents 表已更新，新增 selfie_photo 和 taxi_permit 文件類型';
  RAISE NOTICE '   - selfie_photo: 自拍照片（清楚且不遮額頭）';
  RAISE NOTICE '   - taxi_permit: 多元登記證（即時接單必須）';
END $$;

