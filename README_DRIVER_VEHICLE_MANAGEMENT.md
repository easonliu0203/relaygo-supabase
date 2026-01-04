# 司機車輛管理功能 - Supabase 設置指南

## 概述

司機車輛管理功能已從 Firebase 遷移到 Supabase，包括：
- **文件管理**：身分證、駕照、行照、保險單、良民證、無肇事紀錄
- **車輛照片管理**：外觀照片（4張）+ 內裝照片（5張）
- **靠行公司資訊**：公司名稱、統一編號、聯絡電話、地址

---

## 資料庫架構

### 1. `driver_documents` 表

存儲司機的所有文件 URL。

**欄位**:
- `id` (UUID) - 主鍵
- `driver_id` (VARCHAR) - 司機的 Firebase UID（外鍵）
- `id_card_front_url` (TEXT) - 身分證正面
- `id_card_back_url` (TEXT) - 身分證背面
- `driver_license_url` (TEXT) - 駕照
- `vehicle_registration_url` (TEXT) - 行照
- `insurance_url` (TEXT) - 保險單
- `police_clearance_url` (TEXT) - 良民證
- `no_accident_record_url` (TEXT) - 無肇事紀錄
- `created_at` (TIMESTAMP) - 創建時間
- `updated_at` (TIMESTAMP) - 更新時間

**約束**:
- `UNIQUE(driver_id)` - 每個司機只能有一筆記錄

### 2. `driver_vehicle_photos` 表

存儲司機的車輛照片 URL。

**欄位**:
- `id` (UUID) - 主鍵
- `driver_id` (VARCHAR) - 司機的 Firebase UID（外鍵）
- `front_left_url` (TEXT) - 左前方
- `front_right_url` (TEXT) - 右前方
- `rear_left_url` (TEXT) - 左後方
- `rear_right_url` (TEXT) - 右後方
- `interior_front_url` (TEXT) - 前座
- `interior_rear1_url` (TEXT) - 後座1
- `interior_rear2_url` (TEXT) - 後座2
- `interior_rear3_url` (TEXT) - 後座3
- `trunk_url` (TEXT) - 後車廂
- `created_at` (TIMESTAMP) - 創建時間
- `updated_at` (TIMESTAMP) - 更新時間

**約束**:
- `UNIQUE(driver_id)` - 每個司機只能有一筆記錄

### 3. `driver_company_info` 表

存儲司機的靠行公司資訊。

**欄位**:
- `id` (UUID) - 主鍵
- `driver_id` (VARCHAR) - 司機的 Firebase UID（外鍵）
- `company_name` (VARCHAR) - 公司名稱
- `tax_id` (VARCHAR) - 統一編號
- `contact_phone` (VARCHAR) - 聯絡電話
- `address` (TEXT) - 地址
- `created_at` (TIMESTAMP) - 創建時間
- `updated_at` (TIMESTAMP) - 更新時間

**約束**:
- `UNIQUE(driver_id)` - 每個司機只能有一筆記錄

---

## Storage Buckets

### 1. `driver-documents` Bucket

存儲司機文件照片。

**路徑格式**: `{driver_id}/{document_type}_{timestamp}.jpg`

**範例**: `abc123/id_card_front_1705567890000.jpg`

### 2. `driver-vehicle-photos` Bucket

存儲司機車輛照片。

**路徑格式**: `{driver_id}/{photo_type}_{timestamp}.jpg`

**範例**: `abc123/front_left_1705567890000.jpg`

---

## 安全策略 (RLS)

所有表和 Storage Buckets 都已設置 Row Level Security (RLS) 策略：

### 資料庫 RLS 策略

```sql
-- 司機只能讀取自己的資料
CREATE POLICY "司機可以讀取自己的資料"
ON driver_documents FOR SELECT
USING (driver_id = (auth.jwt() ->> 'sub'));

-- 司機只能插入/更新自己的資料
CREATE POLICY "司機可以插入/更新自己的資料"
ON driver_documents FOR INSERT
WITH CHECK (driver_id = (auth.jwt() ->> 'sub'));
```

### Storage RLS 策略

```sql
-- 司機只能上傳到自己的資料夾
CREATE POLICY "司機可以上傳到自己的資料夾"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'driver-documents' AND
  (storage.foldername(name))[1] = (auth.jwt() ->> 'sub')
);
```

---

## 設置步驟

### 步驟 1: 執行資料庫遷移

```bash
# 在 Supabase Dashboard 的 SQL Editor 中執行以下腳本
supabase/migrations/20250117_create_driver_documents.sql
supabase/migrations/20250117_create_driver_vehicle_photos.sql
supabase/migrations/20250117_create_driver_company_info.sql
```

### 步驟 2: 創建 Storage Buckets

```bash
# 在 Supabase Dashboard 的 SQL Editor 中執行以下腳本
supabase/storage/create_driver_documents_bucket.sql
supabase/storage/create_driver_vehicle_photos_bucket.sql
```

### 步驟 3: 驗證設置

1. 檢查表是否創建成功
2. 檢查 RLS 策略是否啟用
3. 檢查 Storage Buckets 是否創建成功
4. 測試上傳和讀取功能

---

## Flutter 使用方式

### 上傳文件

```dart
final DriverVehicleService _vehicleService = DriverVehicleService();

// 上傳文件
final String? url = await _vehicleService.uploadDocument(
  imageFile,
  'id_card_front',
);

// 保存到資料庫
await _vehicleService.saveDocuments(
  idCardFrontUrl: url,
);
```

### 上傳車輛照片

```dart
// 上傳車輛照片
final String? url = await _vehicleService.uploadVehiclePhoto(
  imageFile,
  'front_left',
);

// 保存到資料庫
await _vehicleService.saveVehiclePhotos(
  frontLeftUrl: url,
);
```

### 保存靠行公司資訊

```dart
await _vehicleService.saveCompanyInfo(
  companyName: '測試公司',
  taxId: '12345678',
  contactPhone: '0912345678',
  address: '台北市信義區',
);
```

---

## 注意事項

1. **Firebase UID 作為外鍵**: 使用 Firebase Auth UID 作為 `driver_id`，不是 Supabase UUID
2. **圖片壓縮**: 所有圖片自動壓縮至 ≤ 1 MB
3. **RLS 安全**: 確保 RLS 策略正確設置，保護用戶數據
4. **Upsert 操作**: 使用 `upsert` 操作，自動處理插入和更新

---

## 相關文件

- `mobile/lib/core/services/driver_vehicle_service.dart` - 車輛管理服務
- `mobile/lib/core/services/supabase_storage_service.dart` - Supabase Storage 服務
- `mobile/lib/apps/driver/presentation/pages/vehicle_management_page.dart` - 車輛管理頁面

