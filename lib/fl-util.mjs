// 공통 유틸 — 에러/검증/응답/금액.
export function fail(message, status = 400) { const e = new Error(message); e.status = status; return e; }

export function txt(v, max = 500, label = '값', required = false) {
  const s = (v == null ? '' : String(v)).trim();
  if (required && !s) throw fail(label + '을(를) 입력해주세요', 422);
  if (s.length > max) throw fail(label + '이(가) 너무 깁니다(최대 ' + max + '자)', 422);
  return s;
}
export function int(v, def = 0) { const n = Math.trunc(Number(v)); return Number.isFinite(n) ? n : def; }
export function num(v, def = 0) { const n = Number(v); return Number.isFinite(n) ? n : def; }
export function bool(v) { return v === true || v === 'true' || v === 1 || v === '1'; }
export function email(v) { const s = txt(v, 200, '이메일'); if (s && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s)) throw fail('이메일 형식이 올바르지 않습니다', 422); return s; }

// KRW 정수(원) 포맷
export function won(n) { return (int(n)).toLocaleString('ko-KR') + '원'; }
export function slugify(s) {
  return String(s || '').toLowerCase().trim()
    .replace(/[^a-z0-9가-힣\s-]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '').slice(0, 60)
    || ('p-' + Date.now().toString(36));
}
export function fmtDate(x) { try { return new Date(x).toLocaleString('ko-KR', { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }); } catch { return ''; } }
