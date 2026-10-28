import { handleApi } from '../../../../../lib/fl-api.mjs';

async function run(event) {
  const { params, url, request } = event;
  const path = '/' + (params.path || '');
  const method = request.method;
  let body = {};
  if (method !== 'GET' && method !== 'DELETE') {
    try { body = await request.json(); } catch { body = {}; }
  }
  const query = Object.fromEntries(url.searchParams);
  try {
    const { status, data } = await handleApi(path, method, body, query, request.headers);
    return json(data, status);
  } catch (e) {
    return json({ error: e.message || '요청 처리 중 오류가 발생했습니다' }, e.status || 500);
  }
}
function json(data, status) {
  return new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
}

export const GET = run;
export const POST = run;
export const PATCH = run;
export const DELETE = run;
export const PUT = run;
