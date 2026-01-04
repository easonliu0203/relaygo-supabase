// CORS 設定
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS, PUT, DELETE',
};

// 建立 CORS 回應
export function createCorsResponse(data: any, status: number = 200): Response {
  return new Response(
    JSON.stringify(data),
    {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    }
  );
}

// 建立錯誤回應
export function createErrorResponse(error: string, status: number = 400): Response {
  return new Response(
    JSON.stringify({
      success: false,
      error,
    }),
    {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    }
  );
}

// 處理 OPTIONS 請求
export function handleOptionsRequest(): Response {
  return new Response('ok', { headers: corsHeaders });
}
