// 模擬支付提供者實作
import { PaymentProvider } from './PaymentProvider.ts';
import { 
  PaymentIntentRequest, 
  PaymentIntentResponse, 
  PaymentConfirmation, 
  WebhookPayload, 
  WebhookResult,
  PaymentStatus,
  BookingStatus
} from '../types/payment.ts';
import { DatabaseService } from '../utils/database.ts';
import { 
  generateTransactionId, 
  generateExternalTransactionId, 
  calculateExpiryTime 
} from '../utils/validation.ts';

export class MockProvider extends PaymentProvider {
  readonly name = 'Mock Payment Provider';
  readonly type = 'mock';
  readonly isTestMode = true;

  private db: DatabaseService;

  constructor() {
    super();
    this.db = new DatabaseService();
  }

  /**
   * 建立支付意圖
   */
  async createPaymentIntent(request: PaymentIntentRequest): Promise<PaymentIntentResponse> {
    try {
      console.log(`[MockProvider] 建立支付意圖: ${request.bookingId}`);

      // 檢查訂單是否存在
      const booking = await this.db.getBookingById(request.bookingId);
      if (!booking) {
        throw new Error(`訂單不存在: ${request.bookingId}`);
      }

      // 檢查是否已有相同類型的已完成支付
      const existingPayment = await this.db.paymentExists(request.bookingId, request.paymentType);
      if (existingPayment) {
        throw new Error(`此訂單的 ${request.paymentType} 已經支付完成`);
      }

      // 生成交易 ID
      const transactionId = generateTransactionId();
      const externalTransactionId = generateExternalTransactionId();
      const expiresAt = calculateExpiryTime(30); // 30 分鐘過期

      // 建立支付記錄
      const paymentRecord = await this.db.createPaymentRecord({
        transaction_id: transactionId,
        booking_id: request.bookingId,
        customer_id: request.customerId,
        type: request.paymentType,
        amount: request.amount,
        currency: request.currency,
        status: 'pending',
        payment_provider: 'mock',
        payment_method: 'mock',
        is_test_mode: true,
        external_transaction_id: externalTransactionId,
        payment_url: `https://mock-payment.example.com/pay/${transactionId}`,
        instructions: `模擬支付 - 金額: ${request.currency} ${request.amount}`,
        expires_at: expiresAt,
      });

      console.log(`[MockProvider] 支付意圖建立成功: ${transactionId}`);

      return {
        success: true,
        transactionId,
        externalTransactionId,
        paymentUrl: `https://mock-payment.example.com/pay/${transactionId}`,
        instructions: `這是模擬支付環境。請使用測試用的支付確認 API 來完成支付。`,
        expiresAt,
        status: 'pending',
        message: '支付意圖建立成功',
      };

    } catch (error) {
      console.error('[MockProvider] 建立支付意圖失敗:', error);
      return {
        success: false,
        transactionId: '',
        externalTransactionId: '',
        status: 'failed',
        expiresAt: '',
        message: error.message,
      };
    }
  }

  /**
   * 確認支付
   */
  async confirmPayment(transactionId: string): Promise<PaymentConfirmation> {
    try {
      console.log(`[MockProvider] 確認支付: ${transactionId}`);

      // 獲取支付記錄
      const payment = await this.db.getPaymentByTransactionId(transactionId);
      if (!payment) {
        throw new Error(`支付記錄不存在: ${transactionId}`);
      }

      // 檢查支付狀態
      if (payment.status === 'completed') {
        return {
          success: true,
          transactionId,
          status: 'completed',
          confirmedAt: payment.confirmed_at || new Date().toISOString(),
          message: '支付已經完成',
        };
      }

      if (payment.status === 'failed' || payment.status === 'cancelled') {
        throw new Error(`支付狀態不允許確認: ${payment.status}`);
      }

      // 檢查是否過期
      if (payment.expires_at && new Date() > new Date(payment.expires_at)) {
        await this.db.updatePaymentRecord(transactionId, { status: 'expired' });
        throw new Error('支付已過期');
      }

      const confirmedAt = new Date().toISOString();

      // 更新支付記錄為已完成
      await this.db.updatePaymentRecord(transactionId, {
        status: 'completed',
        confirmed_at: confirmedAt,
      });

      // 更新訂單狀態
      await this.updateBookingStatusAfterPayment(payment.booking_id, payment.type);

      console.log(`[MockProvider] 支付確認成功: ${transactionId}`);

      return {
        success: true,
        transactionId,
        status: 'completed',
        confirmedAt,
        message: '支付確認成功',
      };

    } catch (error) {
      console.error('[MockProvider] 支付確認失敗:', error);
      return {
        success: false,
        transactionId,
        status: 'failed',
        confirmedAt: new Date().toISOString(),
        message: error.message,
      };
    }
  }

  /**
   * 處理 Webhook
   */
  async handleWebhook(payload: WebhookPayload): Promise<WebhookResult> {
    try {
      console.log(`[MockProvider] 處理 Webhook: ${payload.transactionId}`);

      // 獲取支付記錄
      const payment = await this.db.getPaymentByTransactionId(payload.transactionId);
      if (!payment) {
        console.warn(`[MockProvider] Webhook 中的支付記錄不存在: ${payload.transactionId}`);
        return {
          success: false,
          processed: false,
          message: '支付記錄不存在',
        };
      }

      // 檢查狀態是否需要更新
      if (payment.status === payload.status) {
        console.log(`[MockProvider] 支付狀態未變更: ${payload.status}`);
        return {
          success: true,
          processed: false,
          message: '狀態未變更',
        };
      }

      // 更新支付記錄
      const updates: any = {
        status: payload.status,
      };

      if (payload.status === 'completed') {
        updates.confirmed_at = payload.timestamp;
      }

      await this.db.updatePaymentRecord(payload.transactionId, updates);

      // 如果支付完成，更新訂單狀態
      if (payload.status === 'completed') {
        await this.updateBookingStatusAfterPayment(payment.booking_id, payment.type);
      }

      console.log(`[MockProvider] Webhook 處理成功: ${payload.transactionId}`);

      return {
        success: true,
        processed: true,
        message: 'Webhook 處理成功',
      };

    } catch (error) {
      console.error('[MockProvider] Webhook 處理失敗:', error);
      return {
        success: false,
        processed: false,
        message: error.message,
      };
    }
  }

  /**
   * 根據支付類型更新訂單狀態
   */
  private async updateBookingStatusAfterPayment(bookingId: string, paymentType: string): Promise<void> {
    const booking = await this.db.getBookingById(bookingId);
    if (!booking) {
      throw new Error(`訂單不存在: ${bookingId}`);
    }

    let newStatus: BookingStatus;

    switch (paymentType) {
      case 'deposit':
        newStatus = 'paid_deposit';
        break;
      case 'balance':
        newStatus = 'completed';
        break;
      case 'tip':
        // 小費不改變訂單狀態
        return;
      default:
        console.warn(`[MockProvider] 未知的支付類型: ${paymentType}`);
        return;
    }

    await this.db.updateBookingStatus(bookingId, newStatus);
    console.log(`[MockProvider] 訂單狀態已更新: ${bookingId} -> ${newStatus}`);
  }
}
