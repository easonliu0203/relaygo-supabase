// 支付提供者模組匯出
export { PaymentProvider, PaymentProviderFactory, PaymentService } from './PaymentProvider.ts';
export { MockProvider } from './MockProvider.ts';
export type { PaymentConfig } from './PaymentProvider.ts';

// 初始化所有支付提供者
export function initializePaymentProviders(): void {
  // 註冊模擬支付提供者
  import('./MockProvider.ts').then(({ MockProvider }) => {
    PaymentProviderFactory.registerProvider('mock', new MockProvider());
    console.log('[PaymentProviders] 支付提供者初始化完成');
    console.log('[PaymentProviders] 可用提供者:', PaymentProviderFactory.getAvailableProviders());
  });
}

// 獲取預設配置
export function getDefaultPaymentConfig(): PaymentConfig {
  return {
    providerType: 'mock',
    isTestMode: true,
    timeout: 30000,
    retryAttempts: 3,
  };
}

// 根據環境獲取配置
export function getPaymentConfigFromEnv(): PaymentConfig {
  const providerType = Deno.env.get('PAYMENT_PROVIDER_TYPE') || 'mock';
  const isTestMode = Deno.env.get('PAYMENT_TEST_MODE') !== 'false';
  
  return {
    providerType,
    isTestMode,
    apiKey: Deno.env.get('PAYMENT_API_KEY'),
    secretKey: Deno.env.get('PAYMENT_SECRET_KEY'),
    webhookSecret: Deno.env.get('PAYMENT_WEBHOOK_SECRET'),
    baseUrl: Deno.env.get('PAYMENT_BASE_URL'),
    timeout: parseInt(Deno.env.get('PAYMENT_TIMEOUT') || '30000'),
    retryAttempts: parseInt(Deno.env.get('PAYMENT_RETRY_ATTEMPTS') || '3'),
  };
}
