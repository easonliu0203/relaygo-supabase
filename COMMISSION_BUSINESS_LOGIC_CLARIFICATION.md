# 分潤業務邏輯澄清與修復方案

## 📋 當前問題

### 問題 1: 觸發器未執行
**測試訂單**: `03a069a8-8869-481a-88a7-256af036a54b`
- 訂單在觸發器 V3 部署**之前**就已完成
- 手動更新訂單狀態時，`OLD.status` 已經是 `completed`
- 觸發器條件不滿足：`NEW.status = 'completed' AND OLD.status != 'completed'`

**解決方案**: 已手動修復此訂單的分潤記錄 ✅

### 問題 2: 業務邏輯不清晰

需要明確以下場景的分潤邏輯：

## 🎯 業務邏輯場景分析

### 場景 1: 客戶 B 第一次使用推廣人 A 的優惠碼

**流程**:
1. B 創建訂單，使用優惠碼 `AAA111`（屬於推廣人 A）
2. 系統在 `referrals` 表創建 A→B 的推薦關係（終身綁定）
3. 訂單的 `influencer_id` = A
4. B 享受 A 的優惠碼折扣
5. 訂單完成時，A 獲得分潤

**數據狀態**:
```sql
-- bookings 表
influencer_id: A
promo_code: AAA111

-- referrals 表
influencer_id: A
referee_id: B

-- promo_code_usage 表
influencer_id: A  ← 分潤給 A
```

✅ **當前實現正確**

---

### 場景 2: 客戶 B 後續繼續使用推廣人 A 的優惠碼

**流程**:
1. B 創建新訂單，使用優惠碼 `AAA111`
2. 系統檢查 `referrals` 表，發現 A→B 關係已存在，不重複創建
3. 訂單的 `influencer_id` = A
4. B 享受 A 的優惠碼折扣
5. 訂單完成時，A 獲得分潤

**數據狀態**:
```sql
-- bookings 表
influencer_id: A
promo_code: AAA111

-- referrals 表（不變）
influencer_id: A
referee_id: B

-- promo_code_usage 表
influencer_id: A  ← 分潤給 A
```

✅ **當前實現正確**

---

### 場景 3: 客戶 B 使用其他推廣人 C 的優惠碼

**需要澄清的問題**:

#### 選項 A: 分潤給首次推薦人 A（終身綁定）

**流程**:
1. B 創建訂單，使用優惠碼 `CCC111`（屬於推廣人 C）
2. 系統檢查 `referrals` 表，發現 A→B 關係已存在
3. 訂單的 `influencer_id` = C（因為使用了 C 的優惠碼）
4. B 享受 C 的優惠碼折扣
5. 訂單完成時，**A（而非 C）獲得分潤**

**數據狀態**:
```sql
-- bookings 表
influencer_id: C  ← 使用 C 的優惠碼
promo_code: CCC111

-- referrals 表（不變）
influencer_id: A  ← 但推薦關係仍是 A
referee_id: B

-- promo_code_usage 表
influencer_id: A  ← 分潤給 A（首次推薦人）
```

**問題**:
- 訂單的 `influencer_id` 和分潤的 `influencer_id` 不一致
- C 提供了折扣但沒有獲得分潤
- 可能導致推廣人 C 的不滿

---

#### 選項 B: 分潤給優惠碼提供者 C

**流程**:
1. B 創建訂單，使用優惠碼 `CCC111`
2. 系統檢查 `referrals` 表，發現 A→B 關係已存在（不變）
3. 訂單的 `influencer_id` = C
4. B 享受 C 的優惠碼折扣
5. 訂單完成時，**C 獲得分潤**

**數據狀態**:
```sql
-- bookings 表
influencer_id: C
promo_code: CCC111

-- referrals 表（不變）
influencer_id: A  ← 推薦關係仍是 A
referee_id: B

-- promo_code_usage 表
influencer_id: C  ← 分潤給 C（優惠碼提供者）
```

**優點**:
- 邏輯清晰：誰提供優惠碼，誰獲得分潤
- 推廣人 C 有動力分享優惠碼
- 訂單的 `influencer_id` 和分潤的 `influencer_id` 一致

---

## 🔧 當前觸發器實現

當前觸發器使用**選項 A**的邏輯：

```sql
-- 查找推薦關係（首次推薦人）
SELECT * INTO v_referral 
FROM referrals 
WHERE referee_id = NEW.customer_id;

-- 給首次推薦人分潤
INSERT INTO promo_code_usage (influencer_id, ...)
VALUES (v_referral.influencer_id, ...);  -- 使用推薦關係的 influencer_id
```

## ✅ 建議的業務邏輯

### 推薦方案: 選項 B（分潤給優惠碼提供者）

**理由**:
1. **邏輯清晰**: 誰提供優惠碼，誰獲得分潤
2. **數據一致**: 訂單的 `influencer_id` = 分潤的 `influencer_id`
3. **激勵機制**: 推廣人有動力持續分享優惠碼
4. **公平性**: 提供折扣的人獲得回報

**修改觸發器**:
```sql
-- 不查找 referrals 表，直接使用訂單的 influencer_id
SELECT * INTO v_influencer
FROM influencers
WHERE id = NEW.influencer_id  -- 使用訂單的 influencer_id
  AND is_active = true;
```

**推薦關係的作用**:
- 僅用於追蹤首次推薦來源
- 用於統計推廣人的推薦人數
- 不影響分潤計算

---

## 📝 需要確認的問題

請確認以下問題，以便我修改觸發器：

1. **分潤邏輯**: 選擇選項 A 還是選項 B？
   - [ ] 選項 A: 分潤給首次推薦人（終身綁定）
   - [ ] 選項 B: 分潤給優惠碼提供者（推薦）

2. **推薦關係的作用**: 如果選擇選項 B，推薦關係僅用於統計，不影響分潤？
   - [ ] 是
   - [ ] 否

3. **多次使用不同優惠碼**: 客戶可以使用不同推廣人的優惠碼嗎？
   - [ ] 可以（每次訂單可以使用不同優惠碼）
   - [ ] 不可以（首次綁定後只能使用該推廣人的優惠碼）

---

**創建日期**: 2026-01-20  
**狀態**: 等待業務邏輯確認

