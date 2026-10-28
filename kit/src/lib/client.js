// 클라이언트 세션·API 헬퍼 (web/app.js 포팅). Svelte가 이스케이프하므로 esc 불필요.
import { browser } from '$app/environment';
const KEY = 'fl-session';
// ★in-memory 폴백 — cross-origin iframe(메이커 안의 CMS 미리보기)에선 localStorage가 파티셔닝/차단될 수 있어
//   브리지 토큰·프로젝트를 모듈 변수에도 보관(SPA라 라우트 이동에도 유지).
let _memToken = null, _memProject = '';
// localStorage 사용(앱/PWA 재실행·탭 종료 후에도 로그인 유지). 토큰 만료는 refresh로 자동 갱신.
export function session() {
  if (!browser) return null;
  try { const s = JSON.parse(localStorage.getItem(KEY) || 'null'); if (s) return s; } catch { /* */ }
  return _memToken ? { access_token: _memToken } : null;
}
export function saveSession(s) { if (!browser) return; try { s ? localStorage.setItem(KEY, JSON.stringify(s)) : localStorage.removeItem(KEY); } catch { /* 프라이빗 모드 등 */ } }

// 메이커 → CMS 미리보기 인증 브리지: URL에 #token=<메이커 액세스토큰>&project=<프로젝트id> 로 진입하면
// 그 토큰을 세션으로, 프로젝트를 샌드박스 스코프로 주입(별도 로그인 없이 그 오너의 그 프로젝트 CMS로).
const PKEY = 'cms_project';
if (browser) {
  try {
    const h = new URLSearchParams(location.hash.slice(1));
    const tk = h.get('token'), pj = h.get('project');
    if (tk) { _memToken = tk; saveSession({ access_token: tk }); }
    if (pj) { _memProject = pj; try { localStorage.setItem(PKEY, pj); } catch { /* */ } }
    if (tk || pj) history.replaceState(null, '', location.pathname + location.search);
  } catch { /* */ }
}
export function cmsProject() { if (_memProject) return _memProject; if (!browser) return ''; try { return localStorage.getItem(PKEY) || ''; } catch { return ''; } }
let refreshing;
async function token() {
  let s = session();
  if (s && s.expires_at * 1000 < Date.now() + 60000) {
    refreshing ||= fetch('/api/auth/refresh', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ refresh_token: s.refresh_token }) })
      .then(async r => { const out = await r.json(); if (!r.ok) { saveSession(null); throw Error('다시 로그인해주세요'); } saveSession(out.session); return out.session; })
      .finally(() => refreshing = null);
    s = await refreshing;
  }
  return s?.access_token;
}
export async function api(path, method = 'GET', body) {
  const t = await token();
  const pj = cmsProject();
  const r = await fetch('/api' + path, { method, headers: { 'content-type': 'application/json', ...(t ? { authorization: 'Bearer ' + t } : {}), ...(pj ? { 'x-cms-project': pj } : {}) }, ...(body !== undefined ? { body: JSON.stringify(body) } : {}) });
  const data = await r.json();
  if (!r.ok) throw Object.assign(Error(data.error || '요청에 실패했습니다'), { status: r.status });
  return data;
}
export function imageUrl(s) { try { const u = new URL(s); const local = u.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(u.hostname) && u.pathname.startsWith('/storage/v1/object/public/fl-public/'); return u.protocol === 'https:' || local ? s : ''; } catch { return ''; } }
