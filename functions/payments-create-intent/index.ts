// Supabase Edge Function: 建立支付意圖
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/utils/cors.ts';
import { validatePaymentIntentRequest } from '../_shared/utils/validation.ts';
import { PaymentService, PaymentProviderFactory } from '../_shared/providers/PaymentProvider.ts';
import { MockProvider } from '../_shared/providers/MockProvider.ts';

// 初始化支付提供者
PaymentProviderFactory.registerProvider('mock', new MockProvider());

serve(async (req) => {
  // 處理 CORS 預檢請求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // 只允許 POST 請求
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: '只允許 POST 請求' 
        }),
        { 
          status: 405, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }

    // 解析請求資料
    const requestData = await req.json();
    console.log('[CreateIntent] 收到請求:', requestData);

    // 驗證請求資料
    const validatedRequest = validatePaymentIntentRequest(requestData);

    // 建立支付服務
    const paymentService = new PaymentService({
      providerType: 'mock',
      isTestMode: true,
    });

    // 處理支付意圖建立
    const response = await paymentService.processPayment(validatedRequest);

    console.log('[CreateIntent] 支付意圖建立結果:', response);

    // 返回結果
    return new Response(
      JSON.stringify(response),
      {
        status: response.success ? 200 : 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );

  } catch (error) {
    console.error('[CreateIntent] 處理失敗:', error);

    // 返回錯誤回應
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message || '建立支付意圖失敗',
        transactionId: '',
        externalTransactionId: '',
        status: 'failed',
        expiresAt: '',
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }
});

/* 
API 文檔:

POST /functions/v1/payments-create-intent

請求格式:
{
  "bookingId": "string",      // 訂單 ID (必填)
  "customerId": "string",     // 客戶 ID (必填)
  "amount": number,           // 支付金額 (必填)
  "currency": "string",       // 貨幣代碼 (必填，如 "TWD")
  "paymentType": "string",    // 支付類型 (必填: "deposit", "balance", "tip", "refund")
  "description": "string",    // 支付描述 (可選)
  "metadata": object          // 額外資料 (可選)
}

回應格式:
{
  "success": boolean,
  "transactionId": "string",
  "externalTransactionId": "string",
  "paymentUrl": "string",
  "instructions": "string",
  "expiresAt": "string",
  "status": "string",
  "message": "string"
}

錯誤回應:
{
  "success": false,
  "error": "string",
  "transactionId": "",
  "externalTransactionId": "",
  "status": "failed",
  "expiresAt": ""
}

使用範例:
curl -X POST https://your-project.supabase.co/functions/v1/payments-create-intent \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "bookingId": "123e4567-e89b-12d3-a456-426614174000",
    "customerId": "987fcdeb-51a2-43d7-8f9e-123456789abc",
    "amount": 1500.00,
    "currency": "TWD",
    "paymentType": "deposit",
    "description": "包車服務訂金"
  }'
*/
