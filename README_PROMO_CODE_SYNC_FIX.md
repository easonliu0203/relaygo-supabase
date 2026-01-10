# 優惠碼和統編欄位同步修復

## 問題描述

在第一次支付訂金流程中填寫完優惠碼與統一編號後，取消支付返回訂單詳情頁面時，發現沒有顯示「優惠碼」與「統一編號」資訊。

### 根本原因

1. **Outbox Trigger 缺少欄位**：`bookings_to_outbox()` trigger function 的 payload 中沒有包含優惠碼相關欄位
2. **Firebase 資料不完整**：因為 trigger 沒有同步這些欄位，導致 Firebase 中的 `bookings` 和 `orders_rt` 集合缺少以下欄位：
   - `promoCode`（優惠碼）
   - `taxId`（統一編號）
   - `originalPrice`（原價）
   - `discountAmount`（折扣金額）
   - `finalPrice`（最終價格）
   - `influencerId`（網紅 ID）
   - `influencerCommission`（網紅佣金）

## 修復內容

### 1. 更新 Outbox Trigger (Migration)

**文件**：`migrations/20260110_add_promo_code_to_outbox_trigger.sql`

更新 `bookings_to_outbox()` trigger function，在 payload 中添加以下欄位：
```sql
'promoCode', NEW.promo_code,
'influencerId', NEW.influencer_id,
'influencerCommission', NEW.influencer_commission,
'originalPrice', NEW.original_price,
'discountAmount', NEW.discount_amount,
'finalPrice', NEW.final_price,
'taxId', NEW.tax_id,
'tourPackageId', NEW.tour_package_id,
'tourPackageName', NEW.tour_package_name
```

### 2. Backfill 現有訂單資料

**文件**：`backfill-promo-code-to-firestore.sql`

為所有包含優惠碼或統編的現有訂單創建 outbox 事件，觸發同步到 Firebase。

### 3. Edge Function 同步邏輯

**文件**：`functions/sync-to-firestore/index.ts`（已在之前的修復中完成）

Edge Function 已經包含同步這些欄位的邏輯（第 326-333 行）：
```typescript
// ✅ 新增：優惠碼相關資訊
promoCode: bookingData.promoCode || null,
influencerId: bookingData.influencerId || null,
influencerCommission: bookingData.influencerCommission || 0,
originalPrice: bookingData.originalPrice || null,
discountAmount: bookingData.discountAmount || 0,
finalPrice: bookingData.finalPrice || null,
taxId: bookingData.taxId || null,
```

### 4. Flutter APP 顯示邏輯

**文件**：
- `mobile/lib/core/models/booking_order.dart`（已在之前的修復中完成）
- `mobile/lib/apps/customer/presentation/pages/order_detail_page.dart`（已在之前的修復中完成）

## 執行步驟

### 1. 更新 Trigger Function
```sql
-- 在 Supabase SQL Editor 執行
-- 或使用 Supabase CLI: supabase db push
\i migrations/20260110_add_promo_code_to_outbox_trigger.sql
```

### 2. Backfill 現有訂單
```sql
-- 在 Supabase SQL Editor 執行
\i backfill-promo-code-to-firestore.sql
```

### 3. 觸發 Edge Function 處理事件
```bash
# 手動觸發 Edge Function
curl -X POST "https://vlyhwegpvpnjyocqmfqc.supabase.co/functions/v1/sync-to-firestore" \
  -H "Authorization: Bearer YOUR_ANON_KEY"
```

或者等待 Cron Job 自動執行（每分鐘執行一次）。

## 驗證

### 1. 檢查 Outbox 事件
```sql
SELECT 
  id,
  aggregate_id,
  payload->>'promoCode' as promo_code,
  payload->>'taxId' as tax_id,
  processed_at
FROM outbox
WHERE aggregate_type = 'booking'
  AND (payload->>'promoCode' IS NOT NULL OR payload->>'taxId' IS NOT NULL)
ORDER BY created_at DESC
LIMIT 5;
```

### 2. 檢查 Firebase 資料
在 Firebase Console 中查看 `bookings` 或 `orders_rt` 集合，確認包含：
- `promoCode`
- `taxId`
- `originalPrice`
- `discountAmount`
- `finalPrice`

### 3. 測試 Flutter APP
1. 創建訂單時填寫優惠碼和統編
2. 進入支付頁面後取消支付
3. 返回訂單詳情頁面
4. ✅ 應該能看到優惠碼和統編資訊

## 相關文件

- Migration: `migrations/20260110_add_promo_code_to_outbox_trigger.sql`
- Backfill Script: `backfill-promo-code-to-firestore.sql`
- Test Script: `test-firebase-sync.sql`
- Edge Function: `functions/sync-to-firestore/index.ts`

## 修復日期

2026-01-10

## 影響範圍

- ✅ 新建訂單：自動同步優惠碼和統編欄位
- ✅ 現有訂單：通過 backfill 腳本手動同步
- ✅ Flutter APP：正確顯示優惠碼和統編資訊

