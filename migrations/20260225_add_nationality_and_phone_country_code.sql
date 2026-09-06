-- 新增國籍與國際電話代碼欄位到 user_profiles 表
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS nationality_code VARCHAR(5);
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS phone_country_code VARCHAR(10);

COMMENT ON COLUMN user_profiles.nationality_code IS '國籍代碼 (TW, JP, US...)';
COMMENT ON COLUMN user_profiles.phone_country_code IS '國際電話代碼 (+886, +81, +1...)';
