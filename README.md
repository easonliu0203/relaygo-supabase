# RelayGo Supabase Services

Supabase database migrations, Edge Functions, and storage configurations for the RelayGo platform.

## 🎯 功能範圍

基於 CQRS 架構，**Supabase/PostgreSQL 作為唯一真實數據源 (Single Source of Truth)**，負責以下核心業務邏輯：

### 核心業務功能
- 💰 **訂單金額管理**：訂單金額計算與追蹤
- 💳 **結帳流程**：GoMyPay 支付整合
- 💸 **退款處理**：退款邏輯與記錄
- 🎁 **獎金計算**：司機獎金與平台費用計算
- 📊 **報表生成**：財務報表與數據分析
- ⭐ **用戶評價**：評分與評論系統
- 💵 **模擬支付**：測試環境支付模擬
- 🏦 **收款帳戶管理**：司機銀行帳戶管理
- 🚗 **車輛管理**：車輛資料與文件管理

### 資料同步
- 🔄 **Firestore 同步**：將關鍵資料同步到 Firebase（用於即時查詢）

## 📁 專案結構

```
supabase/
├── migrations/                    # 資料庫遷移腳本
│   ├── 20250117_create_driver_bank_accounts.sql
│   ├── 20250117_create_driver_documents.sql
│   ├── 20251024_add_financial_columns.sql
│   ├── 20251130_add_driver_location_fields.sql
│   └── ...
├── functions/                     # Supabase Edge Functions
│   ├── _shared/                  # 共用模組
│   ├── payments-create-intent/   # 建立支付意圖
│   ├── payments-confirm/         # 確認支付
│   ├── payments-webhook/         # 支付 Webhook
│   ├── sync-to-firestore/        # 同步到 Firestore
│   ├── backfill-bookings/        # 訂單資料回填
│   └── cleanup-outbox/           # 清理 Outbox
├── storage/                       # Storage 配置
│   ├── create_driver_bank_accounts_bucket.sql
│   ├── create_driver_documents_bucket.sql
│   └── create_driver_vehicle_photos_bucket.sql
└── *.sql                          # 各種資料庫腳本
```

## 🚀 部署指南

### 前置需求
- Supabase CLI: `npm install -g supabase`
- Supabase 專案已設定

### 資料庫遷移

```bash
# 推送所有遷移到 Supabase
supabase db push

# 查看遷移狀態
supabase migration list

# 創建新的遷移
supabase migration new <migration_name>
```

### Edge Functions 部署

```bash
# 部署所有 Functions
supabase functions deploy

# 部署特定 Function
supabase functions deploy payments-create-intent
supabase functions deploy payments-confirm
supabase functions deploy payments-webhook
supabase functions deploy sync-to-firestore

# 查看 Function 日誌
supabase functions logs <function_name>
```

### 本地開發

```bash
# 啟動本地 Supabase
supabase start

# 停止本地 Supabase
supabase stop
```

## 🔧 環境變數設定

需要在 Supabase Dashboard 設定以下環境變數（Secrets）：

```bash
# Firebase 整合
FIREBASE_SERVICE_ACCOUNT=<Firebase 服務帳號 JSON>

# GoMyPay 支付整合
GOMYPAY_MERCHANT_ID=<商戶 ID>
GOMYPAY_API_KEY=<API 金鑰>
GOMYPAY_HASH_KEY=<Hash 金鑰>
GOMYPAY_HASH_IV=<Hash IV>

# Supabase 連接
SUPABASE_URL=<Supabase 專案 URL>
SUPABASE_ANON_KEY=<Supabase Anon Key>
SUPABASE_SERVICE_ROLE_KEY=<Supabase Service Role Key>
```

## 📊 架構說明

### CQRS 架構中的角色

```
┌─────────────────────────────────────────────────────┐
│              RelayGo Platform Architecture           │
├─────────────────────────────────────────────────────┤
│                                                       │
│  Supabase/PostgreSQL (唯一真實數據源)                │
│  ├── 訂單管理                                        │
│  ├── 支付處理                                        │
│  ├── 財務計算                                        │
│  ├── 司機/車輛管理                                   │
│  └── 報表生成                                        │
│                                                       │
│  ↓ 同步關鍵資料                                      │
│                                                       │
│  Firebase (即時查詢與通知)                           │
│  ├── 用戶認證                                        │
│  ├── 推播通知                                        │
│  ├── 即時聊天                                        │
│  └── 定位服務                                        │
│                                                       │
└─────────────────────────────────────────────────────┘
```

### 與其他服務的整合
- **Railway Backend**：透過 Supabase Client 存取資料
- **Firebase**：透過 Edge Functions 同步必要資料
- **Mobile App**：透過 Supabase Client SDK 直接連接
- **Web Admin**：透過 Supabase Client 管理後台資料

## 🔒 安全性

### Row Level Security (RLS)
所有資料表都已啟用 RLS 政策，確保：
- 用戶只能存取自己的訂單和資料
- 司機只能存取自己的收款帳戶和車輛資料
- 管理員有完整的存取權限

### API Key 管理
⚠️ **重要**：絕不將以下文件提交到 Git：
- `*.env` 或 `.env.local`
- `*service-account*.json`
- 任何包含 API keys 的配置文件

## 📝 重要腳本說明

- `add-deposit-paid-column.sql` - 添加訂金支付欄位
- `enable-auto-dispatch-24-7.sql` - 啟用 24/7 自動派單
- `fix-currency-and-platform-fee.sql` - 修復貨幣和平台費用
- `setup-realtime-webhook.sql` - 設定即時 Webhook

## 🔗 相關儲存庫

- [relaygo-backend](https://github.com/easonliu0203/relaygo-backend) - Railway API
- [relaygo-firebase](https://github.com/easonliu0203/relaygo-firebase) - Firebase 服務
- [relaygo-mobile](https://github.com/easonliu0203/relaygo-mobile) - Flutter 手機應用
- [relaygo-web-admin](https://github.com/easonliu0203/relaygo-web-admin) - Web 管理後台
- [relaygo-auto-dispatch-worker](https://github.com/easonliu0203/relaygo-auto-dispatch-worker) - 自動派單 Worker

## 📞 支援

如有問題，請聯繫開發團隊或查看 Supabase Dashboard 的日誌。

