# 分潤系統問題診斷報告 - 2026-01-20

## 🐛 問題描述

測試訂單 `03a069a8-8869-481a-88a7-256af036a54b` 的分潤記錄顯示異常：

```
commission_amount: 0.00 ❌ (應該是 100.00)
commission_status: pending ❌ (應該是 completed)
commission_type: NULL ❌ (應該是 percent)
commission_rate: NULL ❌ (應該是 5.0)
order_amount: NULL ❌ (應該是 2000.00)
referee_id: NULL ❌ (應該有客戶 ID)
```

## 🔍 診斷結果

### 1. 訂單狀態
```sql
id: 03a069a8-8869-481a-88a7-256af036a54b
status: completed ✅
customer_id: aa5cf574-2394-4258-aceb-471fcf80f49c ✅
influencer_id: 61d72f11-0b75-4eb1-8dd9-c25893b84e09 ✅
promo_code: QQQ111 ✅
total_amount: 2000.00 ✅
created_at: 2026-01-20 13:21:39
completed_at: 2026-01-20 14:09:03 ✅
```

### 2. 推薦關係
```sql
influencer_id: 61d72f11-0b75-4eb1-8dd9-c25893b84e09 ✅
referee_id: aa5cf574-2394-4258-aceb-471fcf80f49c ✅
promo_code: QQQ111 ✅
created_at: 2026-01-20 10:33:49 ✅
```

### 3. 推廣人設定
```sql
commission_percent: 5 ✅
is_commission_percent_active: true ✅
is_active: true ✅
```

### 4. 觸發器狀態
```sql
trigger_name: trigger_calculate_affiliate_commission
status: Enabled (O) ✅
```

## 🎯 根本原因

**訂單在觸發器 V3 部署之前就已經完成了**

- 訂單完成時間: `2026-01-20 14:09:03`
- 觸發器 V3 部署時間: `2026-01-20 14:15:00`（估計）
- 時間差: 約 6 分鐘

**為什麼手動更新也沒有觸發？**

觸發器條件：
```sql
IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed')
```

當我們手動更新時：
- `OLD.status` = `completed`（已經是完成狀態）
- `NEW.status` = `completed`
- 條件 `OLD.status != 'completed'` 不滿足 ❌
- 觸發器跳過處理

## ✅ 修復操作

### 1. 手動修復分潤記錄

```sql
UPDATE promo_code_usage
SET 
  commission_amount = 100.00,
  commission_status = 'completed',
  commission_type = 'percent',
  commission_rate = 5,
  order_amount = 2000.00,
  referee_id = 'aa5cf574-2394-4258-aceb-471fcf80f49c'
WHERE id = '2644f373-1eba-45c2-8785-480a50f6fa01';
```

✅ **已執行**

### 2. 更新推廣人累積收益

```sql
UPDATE influencers
SET total_earnings = total_earnings + 100.00
WHERE id = '61d72f11-0b75-4eb1-8dd9-c25893b84e09';
```

✅ **已執行**

### 3. 驗證修復結果

```sql
-- 分潤記錄
commission_amount: 100.00 ✅
commission_status: completed ✅
commission_type: percent ✅
commission_rate: 5 ✅
order_amount: 2000.00 ✅
referee_id: aa5cf574-2394-4258-aceb-471fcf80f49c ✅

-- 推廣人累積收益
total_earnings: 240.00 ✅ (140.00 + 100.00)
```

## 📋 當前數據狀態

| 訂單 ID | 訂單金額 | 分潤金額 | 狀態 |
|---------|----------|----------|------|
| `65ec7619...` | 2800.00 | 140.00 | ✅ completed |
| `03a069a8...` | 2000.00 | 100.00 | ✅ completed |
| **總計** | **4800.00** | **240.00** | **2 筆** |

**推廣人累積收益**: 240.00 ✅

## 🚨 重要發現：業務邏輯需要澄清

在診斷過程中發現一個**重要的業務邏輯問題**：

### 場景 3: 客戶使用其他推廣人的優惠碼

**您的描述**:
> 客戶 B 使用其他推廣人 C 的優惠碼時，A（而非 C）獲得分潤

**當前觸發器實現**:
- 查找 `referrals` 表中的推薦關係（首次推薦人 A）
- 給 A 分潤

**問題**:
- 訂單的 `influencer_id` = C（使用 C 的優惠碼）
- 分潤的 `influencer_id` = A（首次推薦人）
- **數據不一致**

**建議**:
請查看 `COMMISSION_BUSINESS_LOGIC_CLARIFICATION.md` 文檔，確認業務邏輯：
- 選項 A: 分潤給首次推薦人（終身綁定）
- 選項 B: 分潤給優惠碼提供者（推薦）

## 🧪 測試建議

### 方法 1: 創建新訂單（推薦）

通過 App 創建一個全新的訂單，完整流程：
1. 使用優惠碼 `QQQ111` 創建訂單
2. 付訂金
3. 完成行程
4. 付尾款（訂單狀態變更為 `completed`）

**預期結果**:
- ✅ 觸發器自動執行
- ✅ 分潤記錄自動更新
- ✅ 累積收益自動累加
- ✅ Railway 日誌中出現 `[Commission Trigger V3]` 訊息

### 方法 2: 使用測試腳本

執行 `TEST_COMMISSION_TRIGGER.sql` 中的測試腳本（需要取消註釋）。

## 📝 後續行動

1. **確認業務邏輯** ⏳
   - 查看 `COMMISSION_BUSINESS_LOGIC_CLARIFICATION.md`
   - 確認分潤邏輯（選項 A 或 B）

2. **創建新訂單測試** ⏳
   - 通過 App 創建新訂單
   - 驗證觸發器自動執行

3. **監控 Railway 日誌** ⏳
   - 搜索 `[Commission Trigger V3]`
   - 確認觸發器執行過程

4. **推送代碼到 GitHub** ⏳
   - Supabase 相關文件
   - 文檔更新

---

**診斷日期**: 2026-01-20  
**診斷人員**: AI Assistant  
**狀態**: 已修復，等待新訂單測試

