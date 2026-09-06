/**
 * Supabase Edge Function: sync-to-firestore
 *
 * 功能：消費 outbox 事件佇列，將訂單變更推送到 Firestore
 * 架構：Outbox Pattern / CDC (Change Data Capture)
 *
 * 資料流：
 * 1. Supabase Trigger 監聽 bookings 表變更
 * 2. 寫入 outbox 表（事件佇列）
 * 3. 本 Edge Function 消費 outbox 事件
 * 4. 推送到 Firestore（雙寫策略）：
 *    - orders_rt/{bookingId} 集合（客戶端即時訂單）
 *    - bookings/{bookingId} 集合（完整訂單記錄）
 * 5. 標記事件為已處理
 *
 * 修復歷史：
 * - 2025-10-04: aggregate_type 從 'order' 改為 'booking'
 * - 2025-10-04: 函數重命名為 syncBookingToFirestore
 * - 2025-10-04: payload 欄位映射更新以匹配 Trigger
 * - 2025-10-06: 實施雙寫策略（同時寫入 orders_rt 和 bookings）
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Firebase Service Account（從環境變數讀取 JSON）
const FIREBASE_SERVICE_ACCOUNT = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!

// Supabase 配置
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// 解析 Service Account
let serviceAccount: any
let FIREBASE_PROJECT_ID: string

try {
  serviceAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT)
  FIREBASE_PROJECT_ID = serviceAccount.project_id
  console.log('✅ Service Account 解析成功, Project ID:', FIREBASE_PROJECT_ID)
} catch (error) {
  console.error('❌ Service Account 解析失敗:', error)
  throw error
}

// OAuth 2.0 Access Token 緩存
let accessToken: string | null = null
let tokenExpiry: number = 0

/**
 * 獲取 OAuth 2.0 Access Token
 */
async function getAccessToken(): Promise<string> {
  // 如果 token 還有效，直接返回
  if (accessToken && Date.now() < tokenExpiry) {
    return accessToken
  }

  console.log('🔑 獲取新的 Access Token...')

  // 創建 JWT
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  }

  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }

  // Base64URL 編碼
  const base64url = (str: string) => {
    return btoa(str)
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '')
  }

  const encodedHeader = base64url(JSON.stringify(header))
  const encodedPayload = base64url(JSON.stringify(payload))
  const signatureInput = `${encodedHeader}.${encodedPayload}`

  // 使用 private_key 簽名
  const privateKey = serviceAccount.private_key
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKey),
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signatureInput)
  )

  const encodedSignature = base64url(String.fromCharCode(...new Uint8Array(signature)))
  const jwt = `${signatureInput}.${encodedSignature}`

  // 交換 JWT 為 Access Token
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  if (!response.ok) {
    const error = await response.text()
    console.error('❌ 獲取 Access Token 失敗:', error)
    throw new Error(`獲取 Access Token 失敗: ${error}`)
  }

  const data = await response.json()
  accessToken = data.access_token
  tokenExpiry = Date.now() + (data.expires_in - 60) * 1000 // 提前 60 秒過期

  console.log('✅ Access Token 獲取成功')
  return accessToken
}

/**
 * 將 PEM 格式的 private key 轉換為 ArrayBuffer
 */
function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes.buffer
}


interface OutboxEvent {
  id: string
  aggregate_type: string
  aggregate_id: string
  event_type: 'created' | 'updated' | 'deleted'
  payload: any
  created_at: string
  retry_count: number
}

serve(async (req) => {
  try {
    // 創建 Supabase 客戶端
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    // 1. 查詢未處理的事件（批次處理，每次最多 10 個）
    const { data: events, error: fetchError } = await supabase
      .from('outbox')
      .select('*')
      .is('processed_at', null)
      .lt('retry_count', 3) // 最多重試 3 次
      .order('created_at', { ascending: true })
      .limit(10)

    if (fetchError) {
      throw new Error(`查詢 outbox 失敗: ${fetchError.message}`)
    }

    if (!events || events.length === 0) {
      return new Response(
        JSON.stringify({ message: '沒有待處理的事件', processed: 0 }),
        { headers: { 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    console.log(`找到 ${events.length} 個待處理事件`)

    // 2. 處理每個事件
    const results = await Promise.allSettled(
      events.map((event: OutboxEvent) => processEvent(event, supabase))
    )

    // 3. 統計處理結果
    const successCount = results.filter(r => r.status === 'fulfilled').length
    const failureCount = results.filter(r => r.status === 'rejected').length

    console.log(`處理完成: 成功 ${successCount}, 失敗 ${failureCount}`)

    return new Response(
      JSON.stringify({
        message: '事件處理完成',
        total: events.length,
        success: successCount,
        failure: failureCount,
      }),
      { headers: { 'Content-Type': 'application/json' }, status: 200 }
    )
  } catch (error) {
    console.error('Edge Function 錯誤:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})

/**
 * 處理單個 outbox 事件
 */
async function processEvent(event: OutboxEvent, supabase: any): Promise<void> {
  try {
    console.log(`處理事件: ${event.id}, 類型: ${event.event_type}, 聚合: ${event.aggregate_id}`)

    // 根據事件類型處理
    if (event.aggregate_type === 'booking') {
      await syncBookingToFirestore(event)
    } else if (event.aggregate_type === 'chat_message') {
      await syncChatMessageToFirestore(event)
    } else {
      console.warn(`未知的聚合類型: ${event.aggregate_type}`)
    }

    // 標記為已處理
    await supabase
      .from('outbox')
      .update({ processed_at: new Date().toISOString() })
      .eq('id', event.id)

    console.log(`事件 ${event.id} 處理成功`)
  } catch (error) {
    console.error(`事件 ${event.id} 處理失敗:`, error)

    // 更新重試次數和錯誤訊息
    await supabase
      .from('outbox')
      .update({
        retry_count: event.retry_count + 1,
        error_message: error.message,
      })
      .eq('id', event.id)

    throw error
  }
}

/**
 * 同步訂單到 Firestore
 */
async function syncBookingToFirestore(event: OutboxEvent): Promise<void> {
  const bookingId = event.aggregate_id
  const bookingData = event.payload

  console.log(`同步訂單到 Firestore: ${bookingId}`, bookingData)

  // 組合 bookingTime（從 startDate 和 startTime）
  let bookingTimeStr: string
  if (bookingData.startDate && bookingData.startTime) {
    bookingTimeStr = `${bookingData.startDate}T${bookingData.startTime}`
  } else {
    bookingTimeStr = bookingData.createdAt
  }

  // 處理 GeoPoint（從 Supabase 的 location 格式轉換）
  // ✅ 修復：使用 payload 中的座標，不再使用硬編碼預設值
  const pickupLocation = bookingData.pickupLocation || null
  const dropoffLocation = bookingData.dropoffLocation || null  // ✅ 新增：從 payload 讀取 dropoff 座標

  // 轉換資料格式為客戶端 App 期望的格式
  const firestoreData = {
    // 基本資訊
    customerId: bookingData.customerId,
    driverId: bookingData.driverId || null,

    // 客戶資訊
    customerName: bookingData.customerName || null,
    customerPhone: bookingData.customerPhone || null,

    // 司機資訊
    driverName: bookingData.driverName || null,
    driverPhone: bookingData.driverPhone || null,
    driverVehiclePlate: bookingData.driverVehiclePlate || null,
    driverVehicleModel: bookingData.driverVehicleModel || null,
    driverRating: bookingData.driverRating || null,

    // 地點資訊
    pickupAddress: bookingData.pickupAddress || '',
    // ✅ 修復：處理座標可能為 null 的情況
    pickupLocation: pickupLocation ? {
      _latitude: pickupLocation.latitude,
      _longitude: pickupLocation.longitude,
    } : null,
    dropoffAddress: bookingData.destination || '',
    // ✅ 修復：使用 payload 中的 dropoff 座標
    dropoffLocation: dropoffLocation ? {
      _latitude: dropoffLocation.latitude,
      _longitude: dropoffLocation.longitude,
    } : null,

    // 時間資訊（使用 _timestamp 標記，convertToFirestoreFields 會轉換為 Firestore Timestamp）
    bookingTime: {
      _timestamp: bookingTimeStr,
    },

    // 乘客資訊（使用 _integer 標記，convertToFirestoreFields 會轉換為整數）
    passengerCount: {
      _integer: bookingData.passengerCount || 1,
    },
    luggageCount: bookingData.luggageCount ? {
      _integer: bookingData.luggageCount,
    } : null,
    notes: bookingData.specialRequirements || null,

    // ✅ 新增：旅遊方案資訊
    tourPackageId: bookingData.tourPackageId || null,
    tourPackageName: bookingData.tourPackageName || null,

    // ✅ 新增：優惠碼相關資訊
    promoCode: bookingData.promoCode || null,
    influencerId: bookingData.influencerId || null,
    influencerCommission: bookingData.influencerCommission || 0,
    originalPrice: bookingData.originalPrice || null,
    discountAmount: bookingData.discountAmount || 0,
    finalPrice: bookingData.finalPrice || null,
    taxId: bookingData.taxId || null,

    // ✅ 訂單維度資訊（用於多維度分潤配置）
    country: bookingData.country || 'TW',  // 國家代碼（預設台灣）
    serviceType: bookingData.serviceType || 'charter',  // 服務類型（charter=包車旅遊, instant_ride=即時派車）

    // 費用資訊
    estimatedFare: bookingData.totalAmount || 0,
    depositAmount: bookingData.depositAmount || 0,
    overtimeFee: bookingData.overtimeFee || 0,  // ✅ 添加超時費用
    tipAmount: bookingData.tipAmount || 0,  // ✅ 添加小費金額
    // ✅ 司機實得小費（已扣金流手續費）。費率為訂單快照，現金小費為 0%。
    //    此金額已包含在 driverEarning 內，顯示時不要再自行乘上 0.97。
    tipAfterFee: bookingData.tipAfterFee || 0,
    tipFeePercentage: bookingData.tipFeePercentage || 0,
    platformFee: bookingData.platformFee || 0,  // ✅ 添加平台抽成
    driverEarning: bookingData.driverEarning || 0,  // ✅ 添加司機收入
    // ✅ 活動單（固定給付）用：司機端需要說明為何收入不是總額的固定比例
    driverPayoutMode: bookingData.driverPayoutMode || 'percent',
    driverFixedAmount: bookingData.driverFixedAmount || 0,
    driverSharePercentage: bookingData.driverSharePercentage || 0,
    charterSurcharge: bookingData.charter_surcharge || 0,  // ✅ 跨區接送費快照
    depositPaid: false,

    // 狀態映射：將 Supabase 狀態轉換為 Flutter APP 期望的狀態
    // ✅ 四階段分類：付款與搜尋 → 服務中 → 結算 → 最終
    status: (() => {
      const supabaseStatus = bookingData.status;
      console.log(`[狀態映射] Supabase 狀態: ${supabaseStatus}`);

      const statusMapping: { [key: string]: string } = {
        // === 階段 I: 付款與搜尋 ===
        'pending_payment': 'PENDING_PAYMENT',   // 待付訂金 → 待付訂金（客戶尚未支付訂金）
        'paid_deposit': 'pending',              // 已付訂金 → 待配對（等待派單）
        'assigned': 'awaitingDriver',           // 已分配司機 → 待司機確認
        'matched': 'awaitingDriver',            // 手動派單 → 待司機確認

        // === 階段 II: 服務中 ===
        'driver_confirmed': 'matched',          // 司機確認後 → 已配對
        'driver_departed': 'ON_THE_WAY',        // 司機已出發 → 正在路上
        'driver_arrived': 'ON_THE_WAY',         // 司機已到達 → 正在路上
        'trip_started': 'inProgress',           // 行程開始 → 進行中
        'in_progress': 'inProgress',            // 通用進行中狀態

        // === 階段 III: 結算 ===
        'trip_ended': 'awaitingBalance',        // 行程結束 → 待付尾款
        'pending_balance': 'awaitingBalance',   // 待付尾款 → 待付尾款

        // === 階段 IV: 最終 ===
        'completed': 'completed',               // 訂單完成 → 已完成
        'cancelled': 'cancelled',               // 已取消 → 已取消
      };

      const firestoreStatus = statusMapping[supabaseStatus] || 'pending';
      console.log(`[狀態映射] Firestore 狀態: ${firestoreStatus}`);

      return firestoreStatus;
    })(),

    // 時間戳記（使用 _timestamp 標記）
    createdAt: {
      _timestamp: bookingData.createdAt,
    },
    matchedAt: bookingData.actualStartTime ? {
      _timestamp: bookingData.actualStartTime,
    } : null,
    completedAt: bookingData.actualEndTime ? {
      _timestamp: bookingData.actualEndTime,
    } : null,
  }

  console.log(`轉換後的 Firestore 資料:`, firestoreData)

  // 根據事件類型執行不同操作
  if (event.event_type === 'deleted') {
    // 刪除 Firestore 文檔
    await deleteFirestoreDocument(bookingId)
  } else {
    // 創建或更新 Firestore 文檔
    await upsertFirestoreDocument(bookingId, firestoreData)
  }
}

/**
 * 創建或更新 Firestore 文檔（雙寫策略：同時寫入 orders_rt 和 bookings）
 */
async function upsertFirestoreDocument(bookingId: string, data: any): Promise<void> {
  console.log(`準備更新 Firestore（雙寫）: orders_rt/${bookingId} 和 bookings/${bookingId}`)

  // 獲取 Access Token
  const token = await getAccessToken()

  // 轉換為 Firestore 格式
  const firestoreFields = convertToFirestoreFields(data)

  // 定義兩個集合的 URL
  const collections = [
    { name: 'orders_rt', url: `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/orders_rt/${bookingId}` },
    { name: 'bookings', url: `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/bookings/${bookingId}` },
  ]

  // 記錄成功和失敗的集合
  const results = {
    success: [] as string[],
    failed: [] as { collection: string; error: string }[],
  }

  // 依次寫入兩個集合
  for (const collection of collections) {
    try {
      const response = await fetch(collection.url, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          fields: firestoreFields,
        }),
      })

      if (!response.ok) {
        const errorText = await response.text()
        console.error(`Firestore 更新失敗 (${collection.name}, ${response.status}):`, errorText)
        results.failed.push({
          collection: collection.name,
          error: `${response.status}: ${errorText}`,
        })
      } else {
        console.log(`✅ Firestore 文檔已更新: ${collection.name}/${bookingId}`)
        results.success.push(collection.name)
      }
    } catch (error) {
      console.error(`Firestore 更新異常 (${collection.name}):`, error)
      results.failed.push({
        collection: collection.name,
        error: error.message,
      })
    }
  }

  // 檢查結果
  if (results.failed.length > 0) {
    const errorMsg = `部分集合更新失敗: ${results.failed.map(f => `${f.collection} (${f.error})`).join(', ')}`
    console.error(errorMsg)

    // 如果兩個都失敗，拋出錯誤
    if (results.success.length === 0) {
      throw new Error(`所有集合更新失敗: ${errorMsg}`)
    }

    // 如果只有一個失敗，記錄警告但不拋出錯誤
    console.warn(`⚠️ 雙寫部分成功: 成功 [${results.success.join(', ')}], 失敗 [${results.failed.map(f => f.collection).join(', ')}]`)
  } else {
    console.log(`✅ 雙寫成功: orders_rt/${bookingId} 和 bookings/${bookingId}`)
  }
}

/**
 * 刪除 Firestore 文檔（雙刪策略：同時刪除 orders_rt 和 bookings）
 */
async function deleteFirestoreDocument(bookingId: string): Promise<void> {
  console.log(`準備刪除 Firestore（雙刪）: orders_rt/${bookingId} 和 bookings/${bookingId}`)

  // 獲取 Access Token
  const token = await getAccessToken()

  // 定義兩個集合的 URL
  const collections = [
    { name: 'orders_rt', url: `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/orders_rt/${bookingId}` },
    { name: 'bookings', url: `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/bookings/${bookingId}` },
  ]

  // 記錄成功和失敗的集合
  const results = {
    success: [] as string[],
    failed: [] as { collection: string; error: string }[],
  }

  // 依次刪除兩個集合
  for (const collection of collections) {
    try {
      const response = await fetch(collection.url, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      })

      if (!response.ok && response.status !== 404) {
        const errorText = await response.text()
        console.error(`Firestore 刪除失敗 (${collection.name}, ${response.status}):`, errorText)
        results.failed.push({
          collection: collection.name,
          error: `${response.status}: ${errorText}`,
        })
      } else {
        console.log(`✅ Firestore 文檔已刪除: ${collection.name}/${bookingId}`)
        results.success.push(collection.name)
      }
    } catch (error) {
      console.error(`Firestore 刪除異常 (${collection.name}):`, error)
      results.failed.push({
        collection: collection.name,
        error: error.message,
      })
    }
  }

  // 檢查結果
  if (results.failed.length > 0) {
    const errorMsg = `部分集合刪除失敗: ${results.failed.map(f => `${f.collection} (${f.error})`).join(', ')}`
    console.error(errorMsg)

    // 如果兩個都失敗，拋出錯誤
    if (results.success.length === 0) {
      throw new Error(`所有集合刪除失敗: ${errorMsg}`)
    }

    // 如果只有一個失敗，記錄警告但不拋出錯誤
    console.warn(`⚠️ 雙刪部分成功: 成功 [${results.success.join(', ')}], 失敗 [${results.failed.map(f => f.collection).join(', ')}]`)
  } else {
    console.log(`✅ 雙刪成功: orders_rt/${bookingId} 和 bookings/${bookingId}`)
  }
}

/**
 * 轉換為 Firestore 欄位格式
 */
function convertToFirestoreFields(data: any): any {
  const fields: any = {}

  for (const [key, value] of Object.entries(data)) {
    if (value === null || value === undefined) {
      fields[key] = { nullValue: null }
    } else if (typeof value === 'string') {
      fields[key] = { stringValue: value }
    } else if (typeof value === 'number') {
      // 檢查是否是整數
      if (Number.isInteger(value)) {
        fields[key] = { integerValue: value.toString() }
      } else {
        fields[key] = { doubleValue: value }
      }
    } else if (typeof value === 'boolean') {
      fields[key] = { booleanValue: value }
    } else if (typeof value === 'object') {
      // 檢查是否是 GeoPoint 格式（包含 _latitude 和 _longitude）
      if ('_latitude' in value && '_longitude' in value) {
        fields[key] = {
          geoPointValue: {
            latitude: value._latitude,
            longitude: value._longitude,
          }
        }
      }
      // 檢查是否是 Timestamp 格式（包含 _timestamp）
      else if ('_timestamp' in value) {
        const timestampStr = value._timestamp as string
        // 將 ISO 8601 字串轉換為 Firestore Timestamp
        const date = new Date(timestampStr)
        fields[key] = {
          timestampValue: date.toISOString()
        }
      }
      // 檢查是否是整數格式（包含 _integer）
      else if ('_integer' in value) {
        const intValue = value._integer as number
        fields[key] = {
          integerValue: intValue.toString()
        }
      }
      // 處理其他嵌套對象
      else {
        fields[key] = { mapValue: { fields: convertToFirestoreFields(value) } }
      }
    }
  }

  return fields
}

/**
 * 同步聊天訊息到 Firestore
 */
async function syncChatMessageToFirestore(event: OutboxEvent): Promise<void> {
  const messageId = event.aggregate_id
  const messageData = event.payload

  console.log(`同步聊天訊息到 Firestore: ${messageId}`, messageData)

  // 根據事件類型執行不同操作
  if (event.event_type === 'deleted') {
    // 刪除 Firestore 文檔
    await deleteChatMessageFromFirestore(messageData.bookingId, messageId)
  } else {
    // 創建或更新 Firestore 文檔
    await upsertChatMessageToFirestore(messageData)
  }
}

/**
 * 創建或更新聊天訊息到 Firestore
 */
async function upsertChatMessageToFirestore(messageData: any): Promise<void> {
  const bookingId = messageData.bookingId
  const messageId = messageData.id

  console.log(`準備更新 Firestore 聊天訊息: chat_rooms/${bookingId}/messages/${messageId}`)

  // 獲取 Access Token
  const token = await getAccessToken()

  // 轉換訊息資料為 Firestore 格式
  const messageFields = convertToFirestoreFields({
    id: messageId,
    senderId: messageData.senderId,
    receiverId: messageData.receiverId,
    senderName: messageData.senderName || '',
    receiverName: messageData.receiverName || '',
    messageText: messageData.messageText,
    translatedText: messageData.translatedText || null,
    createdAt: {
      _timestamp: messageData.createdAt,
    },
    readAt: messageData.readAt ? {
      _timestamp: messageData.readAt,
    } : null,
  })

  // 更新訊息文檔
  const messageUrl = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/chat_rooms/${bookingId}/messages/${messageId}`

  const messageResponse = await fetch(messageUrl, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({
      fields: messageFields,
    }),
  })

  if (!messageResponse.ok) {
    const errorText = await messageResponse.text()
    console.error(`Firestore 訊息更新失敗 (${messageResponse.status}):`, errorText)
    throw new Error(`Firestore 訊息更新失敗: ${errorText}`)
  }

  console.log(`✅ Firestore 訊息文檔已更新: chat_rooms/${bookingId}/messages/${messageId}`)

  // 更新聊天室資訊（最後訊息、未讀數量等）
  await updateChatRoomInfo(bookingId, messageData, token)
}

/**
 * 更新聊天室資訊
 */
async function updateChatRoomInfo(bookingId: string, messageData: any, token: string): Promise<void> {
  console.log(`更新聊天室資訊: chat_rooms/${bookingId}`)

  const bookingData = messageData.bookingData || {}

  // 轉換聊天室資料為 Firestore 格式
  const roomFields = convertToFirestoreFields({
    bookingId: bookingId,
    customerId: bookingData.customerId || '',
    driverId: bookingData.driverId || '',
    customerName: bookingData.customerName || '',
    driverName: bookingData.driverName || '',
    pickupAddress: bookingData.pickupAddress || '',
    bookingTime: bookingData.bookingTime ? {
      _timestamp: bookingData.bookingTime,
    } : null,
    lastMessage: messageData.messageText || '',
    lastMessageTime: {
      _timestamp: messageData.createdAt,
    },
    updatedAt: {
      _timestamp: new Date().toISOString(),
    },
  })

  // 更新聊天室文檔
  const roomUrl = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/chat_rooms/${bookingId}`

  const roomResponse = await fetch(roomUrl, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({
      fields: roomFields,
    }),
  })

  if (!roomResponse.ok) {
    const errorText = await roomResponse.text()
    console.error(`Firestore 聊天室更新失敗 (${roomResponse.status}):`, errorText)
    // 不拋出錯誤，因為訊息已經成功同步
    console.warn(`⚠️ 聊天室資訊更新失敗，但訊息已同步`)
  } else {
    console.log(`✅ Firestore 聊天室文檔已更新: chat_rooms/${bookingId}`)
  }
}

/**
 * 從 Firestore 刪除聊天訊息
 */
async function deleteChatMessageFromFirestore(bookingId: string, messageId: string): Promise<void> {
  console.log(`準備刪除 Firestore 聊天訊息: chat_rooms/${bookingId}/messages/${messageId}`)

  // 獲取 Access Token
  const token = await getAccessToken()

  const messageUrl = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/chat_rooms/${bookingId}/messages/${messageId}`

  const response = await fetch(messageUrl, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  })

  if (!response.ok && response.status !== 404) {
    const errorText = await response.text()
    console.error(`Firestore 訊息刪除失敗 (${response.status}):`, errorText)
    throw new Error(`Firestore 訊息刪除失敗: ${errorText}`)
  }

  console.log(`✅ Firestore 訊息文檔已刪除: chat_rooms/${bookingId}/messages/${messageId}`)
}

