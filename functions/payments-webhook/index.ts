// Supabase Edge Function: 支付 Webhook
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders, createCorsResponse, createErrorResponse, handleOptionsRequest } from '../_shared/utils/cors.ts';
import { validateWebhookPayload } from '../_shared/utils/validation.ts';
import { PaymentService, PaymentProviderFactory } from '../_shared/providers/PaymentProvider.ts';
import { MockProvider } from '../_shared/providers/MockProvider.ts';

// 初始化支付提供者
PaymentProviderFactory.registerProvider('mock', new MockProvider());

serve(async (req) => {
  // 處理 CORS 預檢請求
  if (req.method === 'OPTIONS') {
    return handleOptionsRequest();
  }

  try {
    // 只允許 POST 請求
    if (req.method !== 'POST') {
      return createErrorResponse('只允許 POST 請求', 405);
    }

    // 解析請求資料
    const requestData = await req.json();
    console.log('[PaymentWebhook] 收到 Webhook:', requestData);

    // 驗證 Webhook 資料
    const webhookPayload = validateWebhookPayload(requestData);

    // 建立支付服務
    const paymentService = new PaymentService({
      providerType: 'mock',
      isTestMode: true,
    });

    // 處理 Webhook
    const result = await paymentService.handleWebhook(webhookPayload);

    console.log('[PaymentWebhook] Webhook 處理結果:', result);

    // 返回結果
    return createCorsResponse(result, result.success ? 200 : 400);

  } catch (error) {
    console.error('[PaymentWebhook] 處理失敗:', error);

    // 返回錯誤回應
    return createCorsResponse({
      success: false,
      processed: false,
      message: error.message || 'Webhook 處理失敗',
    }, 500);
  }
});

/* 
API 文檔:

POST /functions/v1/payments-webhook

請求格式:
{
  "transactionId": "string",          // 交易 ID (必填)
  "externalTransactionId": "string",  // 外部交易 ID (必填)
  "status": "string",                 // 支付狀態 (必填)
  "amount": number,                   // 支付金額 (必填)
  "currency": "string",               // 貨幣代碼 (必填)
  "timestamp": "string",              // 時間戳 (必填)
  "signature": "string",              // 簽名 (可選)
  "metadata": object                  // 額外資料 (可選)
}

回應格式:
{
  "success": boolean,
  "processed": boolean,
  "message": "string"
}

錯誤回應:
{
  "success": false,
  "processed": false,
  "message": "string"
}

支援的支付狀態:
- "pending": 待處理
- "processing": 處理中
- "completed": 已完成
- "failed": 失敗
- "cancelled": 已取消
- "expired": 已過期
- "refunded": 已退款

使用範例:
curl -X POST https://your-project.supabase.co/functions/v1/payments-webhook \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "transactionId": "mock_1640995200000_abc123def",
    "externalTransactionId": "ext_1640995200000_xyz789ghi",
    "status": "completed",
    "amount": 1500.00,
    "currency": "TWD",
    "timestamp": "2024-01-01T12:00:00.000Z"
  }'

Webhook 處理流程:
1. 驗證 Webhook 資料格式
2. 查找對應的支付記錄
3. 檢查狀態是否需要更新
4. 更新支付記錄狀態
5. 如果支付完成，更新對應的訂單狀態
6. 返回處理結果

注意事項:
- Webhook 具有冪等性，重複調用相同狀態不會產生副作用
- 如果支付記錄不存在，會返回錯誤但不會中斷處理
- 支付完成時會自動更新訂單狀態
- 所有 Webhook 調用都會被記錄以便追蹤
*/
