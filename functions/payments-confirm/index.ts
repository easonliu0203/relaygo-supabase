// Supabase Edge Function: 確認支付
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders, createCorsResponse, createErrorResponse, handleOptionsRequest } from '../_shared/utils/cors.ts';
import { validateConfirmPaymentRequest } from '../_shared/utils/validation.ts';
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
    console.log('[ConfirmPayment] 收到請求:', requestData);

    // 驗證請求資料
    const { transactionId } = validateConfirmPaymentRequest(requestData);

    // 建立支付服務
    const paymentService = new PaymentService({
      providerType: 'mock',
      isTestMode: true,
    });

    // 確認支付
    const confirmation = await paymentService.confirmPayment(transactionId);

    console.log('[ConfirmPayment] 支付確認結果:', confirmation);

    // 返回結果
    return createCorsResponse(confirmation, confirmation.success ? 200 : 400);

  } catch (error) {
    console.error('[ConfirmPayment] 處理失敗:', error);

    // 返回錯誤回應
    return createCorsResponse({
      success: false,
      transactionId: '',
      status: 'failed',
      confirmedAt: new Date().toISOString(),
      message: error.message || '支付確認失敗',
    }, 500);
  }
});

/* 
API 文檔:

POST /functions/v1/payments-confirm

請求格式:
{
  "transactionId": "string"   // 交易 ID (必填)
}

回應格式:
{
  "success": boolean,
  "transactionId": "string",
  "status": "string",
  "confirmedAt": "string",
  "message": "string"
}

錯誤回應:
{
  "success": false,
  "transactionId": "string",
  "status": "failed",
  "confirmedAt": "string",
  "message": "string"
}

使用範例:
curl -X POST https://your-project.supabase.co/functions/v1/payments-confirm \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "transactionId": "mock_1640995200000_abc123def"
  }'

支付確認流程:
1. 驗證 transactionId 是否存在
2. 檢查支付記錄狀態
3. 檢查支付是否過期
4. 更新支付狀態為 'completed'
5. 根據支付類型更新訂單狀態:
   - deposit: 訂單狀態 -> paid_deposit
   - balance: 訂單狀態 -> completed
   - tip: 不改變訂單狀態
6. 返回確認結果

注意事項:
- 只有狀態為 'pending' 或 'processing' 的支付可以被確認
- 已完成的支付會返回成功但不會重複處理
- 過期的支付會被標記為 'expired' 並返回錯誤
- 失敗或取消的支付無法被確認
*/
