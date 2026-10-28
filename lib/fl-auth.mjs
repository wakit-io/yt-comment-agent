// 관리자 인증 — Supabase 액세스 토큰(Bearer) 검증. 단일 설치본·관리자 1명.
// MASTER_EMAILS(쉼표구분)가 설정되면 그 이메일만 관리자. 비어있으면(로컬/초기) 인증된 사용자=관리자.
import { createClient } from '@supabase/supabase-js';
import { supa, authClient as supaAuthClient } from './supa.mjs';

// 인증 검증 클라이언트. 미리보기 모드 + MAKER_SUPABASE_URL 설정 시 → 메이커 Supabase로 토큰 검증
// (인증 브리지: 메이커에서 로그인한 신원이 그대로 CMS 미리보기의 오너가 됨). 미설정 시 자기 supa.
let _makerClient = null;
function authClient() {
  if (process.env.CMS_PREVIEW_MODE && process.env.MAKER_SUPABASE_URL) {
    _makerClient ||= createClient(process.env.MAKER_SUPABASE_URL, process.env.MAKER_SUPABASE_ANON_KEY || 'anon', { auth: { persistSession: false, autoRefreshToken: false } });
    return _makerClient;
  }
  return supa;
}

function masterEmails() {
  return (process.env.MASTER_EMAILS || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
}
function bearer(headers) {
  const h = headers.get ? headers.get('authorization') : (headers.authorization || headers.Authorization);
  const m = /^Bearer\s+(.+)$/i.exec(h || '');
  return m ? m[1] : '';
}

// 손님(일반 사용자) 신원 확인 — 토큰만 검증해 user 반환(★오너검사 없음, 관리자화 안 됨). 비로그인/무효 토큰=null(throw 안 함).
//   공개 제출(pubSubmit)에서 "로그인한 회원만" 게이트 + 신청자 member_id 각인에 사용.
export async function resolveUser(token) {
  if (!token) return null;
  // ★손님(일반 사용자)은 primary Supabase(supa.mjs authClient)에서 로그인/가입함(관리자 SSO=maker Supabase 와 다름).
  //   따라서 손님 토큰은 primary 로 검증해야 함(maker 로 하면 "User not found" → 항상 실패).
  try { const { data, error } = await supaAuthClient().auth.getUser(token); if (error || !data?.user) return null; return data.user; } catch { return null; }
}

// 관리자 인증. 실패 시 401/403 throw. 성공 시 {user}.
// 권한 판별: ① MASTER_EMAILS 설정 시 그 이메일만(폴백/오버라이드)
//           ② 아니면 소유자 모델 — fl_site.owner_user_id 가 주인. 없으면 이 사용자를 주인으로 등록(최초 1인).
export async function authenticate(headers) {
  const token = bearer(headers);
  if (!token) { const e = new Error('로그인이 필요합니다'); e.status = 401; throw e; }
  const { data, error } = await authClient().auth.getUser(token);
  if (error || !data?.user) { const e = new Error('세션이 만료되었습니다. 다시 로그인해주세요'); e.status = 401; throw e; }
  const user = data.user;

  // 미리보기 모드(멀티테넌트): 토큰만 유효하면 누구나 자기 샌드박스의 오너. 단일 소유자 모델 우회.
  if (process.env.CMS_PREVIEW_MODE) return { user, token };

  const allow = masterEmails();
  if (allow.length) {
    if (!allow.includes((user.email || '').toLowerCase())) { const e = new Error('관리자 권한이 없습니다'); e.status = 403; throw e; }
    return { user, token };
  }

  const { data: site } = await supa.from('fl_site').select('owner_user_id').eq('id', 1).maybeSingle();
  const owner = site?.owner_user_id;
  if (owner) {
    if (owner !== user.id) { const e = new Error('이 워크스페이스의 운영자가 아닙니다'); e.status = 403; throw e; }
  } else {
    // 주인 없음 → 이 사용자를 주인으로 등록(동시성 안전: owner_user_id 가 null 일 때만)
    try { await supa.from('fl_site').update({ owner_user_id: user.id }).eq('id', 1).is('owner_user_id', null); } catch { /* best-effort */ }
  }
  return { user, token };
}

// 선택적 인증(없어도 됨). 로그인 안했으면 null.
export async function optionalAuth(headers) {
  try { return await authenticate(headers); } catch { return null; }
}
