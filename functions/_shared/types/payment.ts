// 支付相關類型定義

export interface PaymentIntentRequest {
  bookingId: string;
  customerId: string;
  amount: number;
  currency: string;
  paymentType: 'deposit' | 'balance' | 'tip' | 'refund';
  description?: string;
  metadata?: Record<string, any>;
}

export interface PaymentIntentResponse {
  success: boolean;
  transactionId: string;
  externalTransactionId: string;
  paymentUrl?: string;
  qrCode?: string;
  instructions?: string;
  expiresAt: string;
  status: PaymentStatus;
  message?: string;
}

export interface PaymentConfirmation {
  success: boolean;
  transactionId: string;
  status: PaymentStatus;
  confirmedAt: string;
  message?: string;
}

export interface WebhookPayload {
  transactionId: string;
  externalTransactionId: string;
  status: PaymentStatus;
  amount: number;
  currency: string;
  timestamp: string;
  signature?: string;
  metadata?: Record<string, any>;
}

export interface WebhookResult {
  success: boolean;
  processed: boolean;
  message?: string;
}

export type PaymentStatus = 
  | 'pending' 
  | 'processing' 
  | 'completed' 
  | 'failed' 
  | 'cancelled' 
  | 'expired' 
  | 'refunded';

export type BookingStatus = 
  | 'draft'
  | 'pending_payment'
  | 'paid_deposit'
  | 'assigned'
  | 'driver_confirmed'
  | 'driver_departed'
  | 'driver_arrived'
  | 'trip_started'
  | 'trip_ended'
  | 'pending_balance'
  | 'completed'
  | 'cancelled'
  | 'refunded';

export interface PaymentRecord {
  id: string;
  transaction_id: string;
  booking_id: string;
  customer_id: string;
  type: 'deposit' | 'balance' | 'refund';
  amount: number;
  currency: string;
  status: PaymentStatus;
  payment_provider: string;
  payment_method?: string;
  is_test_mode: boolean;
  external_transaction_id?: string;
  payment_url?: string;
  instructions?: string;
  confirmed_by?: string;
  admin_notes?: string;
  created_at: string;
  updated_at: string;
  expires_at?: string;
}

export interface BookingRecord {
  id: string;
  booking_number: string;
  customer_id: string;
  driver_id?: string;
  vehicle_type: string;
  status: BookingStatus;
  total_amount: number;
  deposit_amount: number;
  balance_amount: number;
  created_at: string;
  updated_at: string;
}
