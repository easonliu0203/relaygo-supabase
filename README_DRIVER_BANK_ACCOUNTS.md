# 司機銀行帳戶功能 - Supabase 設置指南

## 概述

司機銀行帳戶功能使用 **Supabase** 作為唯一真實來源（CQRS 架構），包括：
- **Supabase Database**: 存儲銀行帳戶資訊
- **Supabase Storage**: 存儲存摺封面照片

## 設置步驟

### 1. 創建資料庫表

在 Supabase Dashboard > SQL Editor 中執行：

```bash
supabase/migrations/20250117_create_driver_bank_accounts.sql
```

這將創建：
- `driver_bank_accounts` 表
- 索引和約束
- RLS (Row Level Security) 策略

### 2. 創建 Storage Bucket

在 Supabase Dashboard > SQL Editor 中執行：

```bash
supabase/storage/create_driver_bank_accounts_bucket.sql
```

這將創建：
- `driver-bank-accounts` bucket（公開訪問）
- Storage 安全策略

### 3. 驗證設置

#### 驗證資料庫表

```sql
-- 檢查表是否存在
SELECT * FROM driver_bank_accounts LIMIT 1;

-- 檢查 RLS 策略
SELECT * FROM pg_policies WHERE tablename = 'driver_bank_accounts';
```

#### 驗證 Storage Bucket

```sql
-- 檢查 bucket 是否存在
SELECT * FROM storage.buckets WHERE id = 'driver-bank-accounts';

-- 檢查 Storage 策略
SELECT * FROM storage.policies WHERE bucket_id = 'driver-bank-accounts';
```

## 資料結構

### driver_bank_accounts 表

| 欄位 | 類型 | 說明 |
|------|------|------|
| id | UUID | 主鍵 |
| driver_id | VARCHAR(128) | 司機的 Firebase UID（外鍵） |
| bank_name | VARCHAR(100) | 銀行名稱 |
| bank_code | VARCHAR(6) | 銀行代碼（3-6位數字） |
| branch_name | VARCHAR(100) | 分行名稱 |
| account_holder_name | VARCHAR(100) | 帳戶持有人姓名 |
| account_number | VARCHAR(50) | 帳戶號碼 |
| cover_photo_url | TEXT | 存摺封面照片 URL |
| created_at | TIMESTAMPTZ | 創建時間 |
| updated_at | TIMESTAMPTZ | 更新時間 |

**約束**:
- `driver_id` 必須是 `users.firebase_uid` 的有效值
- 每個司機只能有一個銀行帳戶（UNIQUE 約束）

## Storage 結構

### driver-bank-accounts Bucket

**路徑格式**: `{firebase_uid}/cover_{timestamp}.jpg`

**範例**:
```
driver-bank-accounts/
  ├── abc123xyz/
  │   └── cover_1705456789000.jpg
  ├── def456uvw/
  │   └── cover_1705456790000.jpg
```

**文件限制**:
- 最大文件大小: 2 MB（由 App 端驗證）
- 允許的 MIME 類型: `image/jpeg`, `image/png`, `image/webp`
- 圖片尺寸: 短邊 ≥ 800px

## 安全策略

### RLS 策略（Database）

1. **SELECT**: 司機只能查看自己的銀行帳戶
2. **INSERT**: 司機只能插入自己的銀行帳戶
3. **UPDATE**: 司機只能更新自己的銀行帳戶
4. **DELETE**: 司機只能刪除自己的銀行帳戶
5. **管理員**: 可以查看所有銀行帳戶

### Storage 策略

1. **上傳**: 司機只能上傳到自己的資料夾
2. **更新**: 司機只能更新自己的照片
3. **刪除**: 司機只能刪除自己的照片
4. **查看**: 司機只能查看自己的照片
5. **管理員**: 可以查看所有照片

## 使用方式

### Flutter App 端

使用 `DriverBankAccountService`:

```dart
final service = DriverBankAccountService();

// 上傳照片
final photoUrl = await service.uploadBankAccountPhoto(imageFile);

// 保存銀行帳戶
await service.saveBankAccount(
  bankName: '台灣銀行',
  bankCode: '004',
  branchName: '台北分行',
  accountHolderName: '王小明',
  accountNumber: '1234567890',
  coverPhotoUrl: photoUrl!,
);

// 獲取銀行帳戶
final account = await service.getBankAccount();

// 刪除銀行帳戶
await service.deleteBankAccount();
```

## 注意事項

1. **Firebase UID 作為外鍵**: `driver_id` 使用 Firebase Auth 的 UID，不是 Supabase 的 UUID
2. **唯一約束**: 每個司機只能有一個銀行帳戶
3. **照片壓縮**: App 端會自動壓縮照片至 ≤ 1 MB
4. **RLS 啟用**: 確保 RLS 已啟用，保護用戶數據安全
5. **公開 Bucket**: Storage bucket 設為公開，以便顯示照片

## 疑難排解

### 無法上傳照片

1. 檢查 Storage bucket 是否存在
2. 檢查 Storage 策略是否正確
3. 檢查 Firebase Auth JWT 是否有效

### 無法保存資料

1. 檢查 `driver_bank_accounts` 表是否存在
2. 檢查 RLS 策略是否正確
3. 檢查 `driver_id` 是否存在於 `users.firebase_uid`

### RLS 策略錯誤

確保 JWT 中包含 `sub` 欄位（Firebase UID）：

```sql
SELECT auth.jwt() ->> 'sub';
```

