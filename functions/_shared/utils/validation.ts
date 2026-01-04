import { PaymentIntentRequest, WebhookPayload } from '../types/payment.ts';

// 驗證支付意圖請求
export function validatePaymentIntentRequest(data: any): PaymentIntentRequest {
  const errors: string[] = [];

  if (!data.bookingId || typeof data.bookingId !== 'string') {
    errors.push('bookingId 是必填欄位且必須是字串');
  }

  if (!data.customerId || typeof data.customerId !== 'string') {
    errors.push('customerId 是必填欄位且必須是字串');
  }

  if (!data.amount || typeof data.amount !== 'number' || data.amount <= 0) {
    errors.push('amount 是必填欄位且必須是大於 0 的數字');
  }

  if (!data.currency || typeof data.currency !== 'string') {
    errors.push('currency 是必填欄位且必須是字串');
  }

  if (!data.paymentType || !['deposit', 'balance', 'tip', 'refund'].includes(data.paymentType)) {
    errors.push('paymentType 必須是 deposit, balance, tip 或 refund 其中之一');
  }

  if (errors.length > 0) {
    throw new Error(`驗證失敗: ${errors.join(', ')}`);
  }

  return {
    bookingId: data.bookingId,
    customerId: data.customerId,
    amount: data.amount,
    currency: data.currency,
    paymentType: data.paymentType,
    description: data.description,
    metadata: data.metadata,
  };
}

// 驗證 Webhook 資料
export function validateWebhookPayload(data: any): WebhookPayload {
  const errors: string[] = [];

  if (!data.transactionId || typeof data.transactionId !== 'string') {
    errors.push('transactionId 是必填欄位且必須是字串');
  }

  if (!data.externalTransactionId || typeof data.externalTransactionId !== 'string') {
    errors.push('externalTransactionId 是必填欄位且必須是字串');
  }

  if (!data.status || !['pending', 'processing', 'completed', 'failed', 'cancelled', 'expired', 'refunded'].includes(data.status)) {
    errors.push('status 必須是有效的支付狀態');
  }

  if (!data.amount || typeof data.amount !== 'number' || data.amount <= 0) {
    errors.push('amount 是必填欄位且必須是大於 0 的數字');
  }

  if (!data.currency || typeof data.currency !== 'string') {
    errors.push('currency 是必填欄位且必須是字串');
  }

  if (!data.timestamp || typeof data.timestamp !== 'string') {
    errors.push('timestamp 是必填欄位且必須是字串');
  }

  if (errors.length > 0) {
    throw new Error(`Webhook 驗證失敗: ${errors.join(', ')}`);
  }

  return {
    transactionId: data.transactionId,
    externalTransactionId: data.externalTransactionId,
    status: data.status,
    amount: data.amount,
    currency: data.currency,
    timestamp: data.timestamp,
    signature: data.signature,
    metadata: data.metadata,
  };
}

// 驗證確認支付請求
export function validateConfirmPaymentRequest(data: any): { transactionId: string } {
  if (!data.transactionId || typeof data.transactionId !== 'string') {
    throw new Error('transactionId 是必填欄位且必須是字串');
  }

  return {
    transactionId: data.transactionId,
  };
}

// 生成唯一的交易 ID
export function generateTransactionId(): string {
  return `mock_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

// 生成外部交易 ID
export function generateExternalTransactionId(): string {
  return `ext_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

// 計算過期時間（預設 30 分鐘）
export function calculateExpiryTime(minutes: number = 30): string {
  const expiryTime = new Date();
  expiryTime.setMinutes(expiryTime.getMinutes() + minutes);
  return expiryTime.toISOString();
}

// 檢查是否已過期
export function isExpired(expiresAt: string): boolean {
  return new Date() > new Date(expiresAt);
}
