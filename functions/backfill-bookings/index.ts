/**
 * Supabase Edge Function: backfill-bookings
 *
 * 功能：補寫歷史資料，將 orders_rt 集合中的訂單複製到 bookings 集合
 * 用途：修復雙寫策略實施前的歷史訂單
 *
 * 使用方法：
 * 1. 手動觸發：https://supabase.com/dashboard/project/{project-ref}/functions
 * 2. 或使用 curl：
 *    curl -X POST https://{project-ref}.supabase.co/functions/v1/backfill-bookings \
 *      -H "Authorization: Bearer {anon-key}"
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

// Firebase Service Account（從環境變數讀取 JSON）
const FIREBASE_SERVICE_ACCOUNT = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!

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
  // 檢查緩存
  if (accessToken && Date.now() < tokenExpiry) {
    return accessToken
  }

  console.log('生成新的 Access Token...')

  // 生成 JWT
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

  // 編碼 Header 和 Payload
  const encoder = new TextEncoder()
  const headerB64 = btoa(JSON.stringify(header)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  const payloadB64 = btoa(JSON.stringify(payload)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  const signatureInput = `${headerB64}.${payloadB64}`

  // 導入私鑰
  const privateKey = serviceAccount.private_key
  const pemHeader = '-----BEGIN PRIVATE KEY-----'
  const pemFooter = '-----END PRIVATE KEY-----'
  const pemContents = privateKey.substring(
    pemHeader.length,
    privateKey.length - pemFooter.length
  ).replace(/\s/g, '')

  const binaryDer = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  )

  // 簽名
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    encoder.encode(signatureInput)
  )

  const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')

  const jwt = `${signatureInput}.${signatureB64}`

  // 交換 Access Token
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })

  if (!tokenResponse.ok) {
    const errorText = await tokenResponse.text()
    console.error('Token 交換失敗:', errorText)
    throw new Error(`Token 交換失敗: ${errorText}`)
  }

  const tokenData = await tokenResponse.json()
  accessToken = tokenData.access_token
  tokenExpiry = Date.now() + (tokenData.expires_in - 60) * 1000 // 提前 60 秒過期

  console.log('✅ Access Token 生成成功')
  return accessToken
}

/**
 * 列出 Firestore 集合中的所有文檔
 */
async function listDocuments(collection: string): Promise<any[]> {
  const token = await getAccessToken()
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}`

  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  })

  if (!response.ok) {
    const errorText = await response.text()
    console.error(`列出文檔失敗 (${collection}):`, errorText)
    throw new Error(`列出文檔失敗: ${errorText}`)
  }

  const data = await response.json()
  return data.documents || []
}

/**
 * 檢查文檔是否存在
 */
async function documentExists(collection: string, docId: string): Promise<boolean> {
  const token = await getAccessToken()
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}/${docId}`

  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  })

  return response.ok
}

/**
 * 複製文檔
 */
async function copyDocument(sourceCollection: string, targetCollection: string, docId: string, fields: any): Promise<void> {
  const token = await getAccessToken()
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${targetCollection}/${docId}`

  const response = await fetch(url, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({
      fields: fields,
    }),
  })

  if (!response.ok) {
    const errorText = await response.text()
    console.error(`複製文檔失敗 (${docId}):`, errorText)
    throw new Error(`複製文檔失敗: ${errorText}`)
  }

  console.log(`✅ 文檔已複製: ${sourceCollection}/${docId} → ${targetCollection}/${docId}`)
}

/**
 * 主函數：補寫歷史資料
 */
serve(async (req) => {
  try {
    console.log('開始補寫歷史資料...')

    // 列出 orders_rt 集合中的所有文檔
    console.log('列出 orders_rt 集合中的文檔...')
    const ordersRtDocs = await listDocuments('orders_rt')
    console.log(`找到 ${ordersRtDocs.length} 個訂單`)

    // 統計
    const stats = {
      total: ordersRtDocs.length,
      alreadyExists: 0,
      copied: 0,
      failed: 0,
      errors: [] as { docId: string; error: string }[],
    }

    // 逐個檢查並複製
    for (const doc of ordersRtDocs) {
      // 提取文檔 ID
      const docPath = doc.name
      const docId = docPath.split('/').pop()

      console.log(`處理訂單: ${docId}`)

      try {
        // 檢查 bookings 集合中是否已存在
        const exists = await documentExists('bookings', docId)

        if (exists) {
          console.log(`⏭️ 訂單已存在: ${docId}`)
          stats.alreadyExists++
          continue
        }

        // 複製到 bookings 集合
        await copyDocument('orders_rt', 'bookings', docId, doc.fields)
        stats.copied++
      } catch (error) {
        console.error(`處理訂單失敗 (${docId}):`, error)
        stats.failed++
        stats.errors.push({
          docId: docId,
          error: error.message,
        })
      }
    }

    console.log('補寫完成！')
    console.log('統計：', stats)

    return new Response(
      JSON.stringify({
        success: true,
        message: '補寫完成',
        stats: stats,
      }),
      {
        headers: { 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('補寫失敗:', error)
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    )
  }
})

