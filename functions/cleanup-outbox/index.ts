/**
 * Supabase Edge Function: cleanup-outbox
 * 
 * 功能：清理舊的 outbox 事件（保留最近 7 天的已處理事件）
 * 執行頻率：每天凌晨 2 點
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

serve(async (req) => {
  try {
    console.log('開始清理舊的 outbox 事件...')

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    // 計算 7 天前的時間
    const sevenDaysAgo = new Date()
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7)

    // 刪除 7 天前的已處理事件
    const { data, error } = await supabase
      .from('outbox')
      .delete()
      .not('processed_at', 'is', null)
      .lt('processed_at', sevenDaysAgo.toISOString())

    if (error) {
      throw new Error(`清理失敗: ${error.message}`)
    }

    const deletedCount = data?.length || 0
    console.log(`清理完成，刪除了 ${deletedCount} 個舊事件`)

    return new Response(
      JSON.stringify({
        message: '清理完成',
        deleted: deletedCount,
        cutoffDate: sevenDaysAgo.toISOString(),
      }),
      { headers: { 'Content-Type': 'application/json' }, status: 200 }
    )
  } catch (error) {
    console.error('清理錯誤:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})

