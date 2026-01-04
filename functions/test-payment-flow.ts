// 支付流程測試腳本
// 使用方法: deno run --allow-net --allow-env test-payment-flow.ts

const SUPABASE_URL = 'https://vlyhwegpvpnjyocqmfqc.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZseWh3ZWdwdnBuanlvY3FtZnFjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg5Nzc5OTYsImV4cCI6MjA3NDU1Mzk5Nn0.qnQBjvLm3IoXvJ0IptfMvPYRni1_7Den3iE9hFj-FYY';

interface TestResult {
  step: string;
  success: boolean;
  data?: any;
  error?: string;
}

class PaymentFlowTester {
  private baseUrl: string;
  private headers: Record<string, string>;
  private results: TestResult[] = [];

  constructor() {
    this.baseUrl = `${SUPABASE_URL}/functions/v1`;
    this.headers = {
      'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
      'Content-Type': 'application/json',
    };
  }

  private async makeRequest(endpoint: string, data: any): Promise<any> {
    const response = await fetch(`${this.baseUrl}/${endpoint}`, {
      method: 'POST',
      headers: this.headers,
      body: JSON.stringify(data),
    });

    const result = await response.json();
    return { status: response.status, data: result };
  }

  private logResult(step: string, success: boolean, data?: any, error?: string) {
    const result: TestResult = { step, success, data, error };
    this.results.push(result);
    
    const status = success ? '✅' : '❌';
    console.log(`${status} ${step}`);
    if (data) console.log('   Data:', JSON.stringify(data, null, 2));
    if (error) console.log('   Error:', error);
    console.log('');
  }

  async testCreatePaymentIntent(): Promise<string | null> {
    try {
      const requestData = {
        bookingId: '123e4567-e89b-12d3-a456-426614174000',
        customerId: '987fcdeb-51a2-43d7-8f9e-123456789abc',
        amount: 1500.00,
        currency: 'TWD',
        paymentType: 'deposit',
        description: '包車服務訂金測試',
      };

      const { status, data } = await this.makeRequest('payments-create-intent', requestData);
      
      if (status === 200 && data.success) {
        this.logResult('建立支付意圖', true, data);
        return data.transactionId;
      } else {
        this.logResult('建立支付意圖', false, data, `HTTP ${status}`);
        return null;
      }
    } catch (error) {
      this.logResult('建立支付意圖', false, null, error.message);
      return null;
    }
  }

  async testConfirmPayment(transactionId: string): Promise<boolean> {
    try {
      const requestData = {
        transactionId,
      };

      const { status, data } = await this.makeRequest('payments-confirm', requestData);
      
      if (status === 200 && data.success) {
        this.logResult('確認支付', true, data);
        return true;
      } else {
        this.logResult('確認支付', false, data, `HTTP ${status}`);
        return false;
      }
    } catch (error) {
      this.logResult('確認支付', false, null, error.message);
      return false;
    }
  }

  async testWebhook(transactionId: string): Promise<boolean> {
    try {
      const requestData = {
        transactionId,
        externalTransactionId: `ext_${Date.now()}_test`,
        status: 'completed',
        amount: 1500.00,
        currency: 'TWD',
        timestamp: new Date().toISOString(),
      };

      const { status, data } = await this.makeRequest('payments-webhook', requestData);
      
      if (status === 200 && data.success) {
        this.logResult('Webhook 處理', true, data);
        return true;
      } else {
        this.logResult('Webhook 處理', false, data, `HTTP ${status}`);
        return false;
      }
    } catch (error) {
      this.logResult('Webhook 處理', false, null, error.message);
      return false;
    }
  }

  async testErrorHandling(): Promise<void> {
    console.log('🧪 測試錯誤處理...\n');

    // 測試無效的支付意圖請求
    try {
      const { status, data } = await this.makeRequest('payments-create-intent', {
        bookingId: '', // 無效的 bookingId
        amount: -100,  // 無效的金額
      });
      
      this.logResult('無效支付意圖請求', !data.success, data);
    } catch (error) {
      this.logResult('無效支付意圖請求', true, null, '正確拋出錯誤');
    }

    // 測試確認不存在的支付
    try {
      const { status, data } = await this.makeRequest('payments-confirm', {
        transactionId: 'non-existent-transaction',
      });
      
      this.logResult('確認不存在的支付', !data.success, data);
    } catch (error) {
      this.logResult('確認不存在的支付', true, null, '正確拋出錯誤');
    }

    // 測試無效的 Webhook 資料
    try {
      const { status, data } = await this.makeRequest('payments-webhook', {
        transactionId: '', // 無效的 transactionId
        status: 'invalid-status', // 無效的狀態
      });
      
      this.logResult('無效 Webhook 資料', !data.success, data);
    } catch (error) {
      this.logResult('無效 Webhook 資料', true, null, '正確拋出錯誤');
    }
  }

  async runFullTest(): Promise<void> {
    console.log('🚀 開始支付流程完整測試...\n');

    // 步驟 1: 建立支付意圖
    const transactionId = await this.testCreatePaymentIntent();
    if (!transactionId) {
      console.log('❌ 測試失敗：無法建立支付意圖');
      return;
    }

    // 步驟 2: 確認支付
    const confirmSuccess = await this.testConfirmPayment(transactionId);
    if (!confirmSuccess) {
      console.log('❌ 測試失敗：無法確認支付');
      return;
    }

    // 步驟 3: 測試 Webhook
    const webhookSuccess = await this.testWebhook(transactionId);
    if (!webhookSuccess) {
      console.log('❌ 測試失敗：Webhook 處理失敗');
      return;
    }

    // 步驟 4: 測試錯誤處理
    await this.testErrorHandling();

    // 總結
    this.printSummary();
  }

  private printSummary(): void {
    console.log('📊 測試總結:');
    console.log('='.repeat(50));
    
    const totalTests = this.results.length;
    const passedTests = this.results.filter(r => r.success).length;
    const failedTests = totalTests - passedTests;

    console.log(`總測試數: ${totalTests}`);
    console.log(`通過: ${passedTests} ✅`);
    console.log(`失敗: ${failedTests} ❌`);
    console.log(`成功率: ${((passedTests / totalTests) * 100).toFixed(1)}%`);

    if (failedTests > 0) {
      console.log('\n失敗的測試:');
      this.results
        .filter(r => !r.success)
        .forEach(r => console.log(`- ${r.step}: ${r.error || '未知錯誤'}`));
    }

    console.log('\n🎉 支付流程測試完成！');
  }
}

// 執行測試
if (import.meta.main) {
  const tester = new PaymentFlowTester();
  await tester.runFullTest();
}
