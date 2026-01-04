import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { PaymentRecord, BookingRecord, PaymentStatus, BookingStatus } from '../types/payment.ts';

// 建立 Supabase 客戶端
export function createSupabaseClient() {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  
  return createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

// 資料庫操作類
export class DatabaseService {
  private supabase;

  constructor() {
    this.supabase = createSupabaseClient();
  }

  // 建立支付記錄
  async createPaymentRecord(data: Partial<PaymentRecord>): Promise<PaymentRecord> {
    const { data: payment, error } = await this.supabase
      .from('payments')
      .insert([{
        ...data,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }])
      .select()
      .single();

    if (error) {
      throw new Error(`建立支付記錄失敗: ${error.message}`);
    }

    return payment;
  }

  // 更新支付記錄
  async updatePaymentRecord(transactionId: string, updates: Partial<PaymentRecord>): Promise<PaymentRecord> {
    const { data: payment, error } = await this.supabase
      .from('payments')
      .update({
        ...updates,
        updated_at: new Date().toISOString(),
      })
      .eq('transaction_id', transactionId)
      .select()
      .single();

    if (error) {
      throw new Error(`更新支付記錄失敗: ${error.message}`);
    }

    return payment;
  }

  // 根據交易 ID 獲取支付記錄
  async getPaymentByTransactionId(transactionId: string): Promise<PaymentRecord | null> {
    const { data: payment, error } = await this.supabase
      .from('payments')
      .select('*')
      .eq('transaction_id', transactionId)
      .single();

    if (error && error.code !== 'PGRST116') { // PGRST116 = no rows returned
      throw new Error(`獲取支付記錄失敗: ${error.message}`);
    }

    return payment;
  }

  // 獲取訂單記錄
  async getBookingById(bookingId: string): Promise<BookingRecord | null> {
    const { data: booking, error } = await this.supabase
      .from('bookings')
      .select('*')
      .eq('id', bookingId)
      .single();

    if (error && error.code !== 'PGRST116') {
      throw new Error(`獲取訂單記錄失敗: ${error.message}`);
    }

    return booking;
  }

  // 更新訂單狀態
  async updateBookingStatus(bookingId: string, status: BookingStatus): Promise<BookingRecord> {
    const { data: booking, error } = await this.supabase
      .from('bookings')
      .update({
        status,
        updated_at: new Date().toISOString(),
      })
      .eq('id', bookingId)
      .select()
      .single();

    if (error) {
      throw new Error(`更新訂單狀態失敗: ${error.message}`);
    }

    return booking;
  }

  // 檢查支付記錄是否存在
  async paymentExists(bookingId: string, paymentType: string): Promise<boolean> {
    const { data, error } = await this.supabase
      .from('payments')
      .select('id')
      .eq('booking_id', bookingId)
      .eq('type', paymentType)
      .eq('status', 'completed');

    if (error) {
      throw new Error(`檢查支付記錄失敗: ${error.message}`);
    }

    return data && data.length > 0;
  }
}
