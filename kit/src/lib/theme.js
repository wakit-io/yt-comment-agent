// 테마(라이트/다크/시스템) 컨트롤러. app.html 인라인 스크립트가 최초 적용하고, 여기서 전환·OS변경 반영.
import { browser } from '$app/environment';
const KEY = 'fl-appearance';

export function getPref() {
  if (!browser) return 'system';
  try { return localStorage.getItem(KEY) || 'system'; } catch { return 'system'; }
}
export function effective(pref = getPref()) {
  if (pref === 'system') { try { return matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'; } catch { return 'light'; } }
  return pref === 'dark' ? 'dark' : 'light';
}
export function apply(pref = getPref()) {
  if (!browser) return;
  document.documentElement.dataset.appearance = effective(pref);
}
export function setPref(v) {
  if (!browser) return;
  try { localStorage.setItem(KEY, v); } catch {}
  apply(v);
}
// 'system'일 때 OS 다크/라이트 변경을 실시간 반영. 정리 함수 반환.
export function watchSystem() {
  if (!browser) return () => {};
  try {
    const mq = matchMedia('(prefers-color-scheme: dark)');
    const fn = () => { if (getPref() === 'system') apply('system'); };
    mq.addEventListener('change', fn);
    return () => mq.removeEventListener('change', fn);
  } catch { return () => {}; }
}
