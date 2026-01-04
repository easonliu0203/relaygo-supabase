// 支付提供者抽象介面
import { 
  PaymentIntentRequest, 
  PaymentIntentResponse, 
  PaymentConfirmation, 
  WebhookPayload, 
  WebhookResult 
} from '../types/payment.ts';

export abstract class PaymentProvider {
  abstract readonly name: string;
  abstract readonly type: string;
  abstract readonly isTestMode: boolean;

  /**
   * 建立支付意圖
   * @param request 支付請求資料
   * @returns 支付意圖回應
   */
  abstract createPaymentIntent(request: PaymentIntentRequest): Promise<PaymentIntentResponse>;

  /**
   * 確認支付
   * @param transactionId 交易 ID
   * @returns 支付確認結果
   */
  abstract confirmPayment(transactionId: string): Promise<PaymentConfirmation>;

  /**
   * 處理 Webhook 回調
   * @param payload Webhook 資料
   * @returns 處理結果
   */
  abstract handleWebhook(payload: WebhookPayload): Promise<WebhookResult>;

  /**
   * 取消支付
   * @param transactionId 交易 ID
   * @returns 取消結果
   */
  abstract cancelPayment?(transactionId: string): Promise<{ success: boolean; message?: string }>;

  /**
   * 退款
   * @param transactionId 交易 ID
   * @param amount 退款金額（可選，預設全額退款）
   * @returns 退款結果
   */
  abstract refundPayment?(transactionId: string, amount?: number): Promise<{ success: boolean; message?: string }>;

  /**
   * 查詢支付狀態
   * @param transactionId 交易 ID
   * @returns 支付狀態
   */
  abstract getPaymentStatus?(transactionId: string): Promise<{ status: string; message?: string }>;
}

// 支付提供者工廠
export class PaymentProviderFactory {
  private static providers: Map<string, PaymentProvider> = new Map();

  /**
   * 註冊支付提供者
   * @param type 提供者類型
   * @param provider 提供者實例
   */
  static registerProvider(type: string, provider: PaymentProvider): void {
    this.providers.set(type, provider);
  }

  /**
   * 獲取支付提供者
   * @param type 提供者類型
   * @returns 支付提供者實例
   */
  static getProvider(type: string): PaymentProvider {
    const provider = this.providers.get(type);
    if (!provider) {
      throw new Error(`未找到支付提供者: ${type}`);
    }
    return provider;
  }

  /**
   * 獲取所有可用的提供者類型
   * @returns 提供者類型列表
   */
  static getAvailableProviders(): string[] {
    return Array.from(this.providers.keys());
  }

  /**
   * 檢查提供者是否已註冊
   * @param type 提供者類型
   * @returns 是否已註冊
   */
  static hasProvider(type: string): boolean {
    return this.providers.has(type);
  }
}

// 支付配置介面
export interface PaymentConfig {
  providerType: string;
  isTestMode: boolean;
  apiKey?: string;
  secretKey?: string;
  webhookSecret?: string;
  baseUrl?: string;
  timeout?: number;
  retryAttempts?: number;
}

// 支付服務類
export class PaymentService {
  private provider: PaymentProvider;
  private config: PaymentConfig;

  constructor(config: PaymentConfig) {
    this.config = config;
    this.provider = PaymentProviderFactory.getProvider(config.providerType);
  }

  /**
   * 處理支付請求
   * @param request 支付請求
   * @returns 支付回應
   */
  async processPayment(request: PaymentIntentRequest): Promise<PaymentIntentResponse> {
    try {
      console.log(`[PaymentService] 處理支付請求: ${request.bookingId}`);
      const response = await this.provider.createPaymentIntent(request);
      console.log(`[PaymentService] 支付請求處理完成: ${response.transactionId}`);
      return response;
    } catch (error) {
      console.error('[PaymentService] 支付處理失敗:', error);
      throw error;
    }
  }

  /**
   * 確認支付
   * @param transactionId 交易 ID
   * @returns 確認結果
   */
  async confirmPayment(transactionId: string): Promise<PaymentConfirmation> {
    try {
      console.log(`[PaymentService] 確認支付: ${transactionId}`);
      const confirmation = await this.provider.confirmPayment(transactionId);
      console.log(`[PaymentService] 支付確認完成: ${transactionId}`);
      return confirmation;
    } catch (error) {
      console.error('[PaymentService] 支付確認失敗:', error);
      throw error;
    }
  }

  /**
   * 處理 Webhook
   * @param payload Webhook 資料
   * @returns 處理結果
   */
  async handleWebhook(payload: WebhookPayload): Promise<WebhookResult> {
    try {
      console.log(`[PaymentService] 處理 Webhook: ${payload.transactionId}`);
      const result = await this.provider.handleWebhook(payload);
      console.log(`[PaymentService] Webhook 處理完成: ${payload.transactionId}`);
      return result;
    } catch (error) {
      console.error('[PaymentService] Webhook 處理失敗:', error);
      throw error;
    }
  }

  /**
   * 獲取提供者資訊
   * @returns 提供者資訊
   */
  getProviderInfo(): { name: string; type: string; isTestMode: boolean } {
    return {
      name: this.provider.name,
      type: this.provider.type,
      isTestMode: this.provider.isTestMode,
    };
  }
}
