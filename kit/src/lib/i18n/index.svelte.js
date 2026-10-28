// 경량 i18n 파이프 — 반응형 런타임 전환(Svelte5 룬). 의존성 0.
//   t('nav.dashboard')  →  현재 로케일 문자열(미번역이면 한글로 폴백 → 최후엔 키).
//   setLocale('en')     →  t()를 쓰는 모든 컴포넌트가 자동 재렌더.
// SSR 결정성: 초기값은 항상 DEFAULT(ko) → 하이드레이션 후 LangToggle이 저장값 반영(테마 패턴과 동일).
import { browser } from '$app/environment';
import { env } from '$env/dynamic/public';
import { ko } from './ko.js';
import { en } from './en.js';

const DICTS = { ko, en };
export const LOCALES = [
  { code: 'ko', label: '한국어' },
  { code: 'en', label: 'English' }
];
const KEY = 'fl-locale';
// 설치 시 PUBLIC_LOCALE=en 으로 글로벌 인스턴스 기본값 지정 가능(미설정이면 ko).
const DEFAULT = env?.PUBLIC_LOCALE === 'en' ? 'en' : 'ko';
const norm = (v) => (v === 'en' ? 'en' : 'ko');

let _locale = $state(DEFAULT);

export function getLocale() { return _locale; }

// 저장된 사용자 선택을 반영(클라이언트). LangToggle onMount에서 1회 호출.
export function initLocale() {
  if (!browser) return;
  try { const v = localStorage.getItem(KEY); if (v) _locale = norm(v); } catch {}
  try { document.documentElement.lang = _locale; } catch {}
}

export function setLocale(v) {
  _locale = norm(v);
  if (!browser) return;
  try { localStorage.setItem(KEY, _locale); } catch {}
  try { document.documentElement.lang = _locale; } catch {}
}

const dig = (obj, key) => key.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);

// 번역 조회. 폴백 순서: 현재 로케일 → 한글(ko) → 키 그대로.
// vars: { name: '홍길동' } → "{name}" 치환.
export function t(key, vars) {
  let s = dig(DICTS[_locale], key);
  if (s == null && _locale !== 'ko') s = dig(DICTS.ko, key);
  if (s == null) s = key;
  if (vars && typeof s === 'string') {
    for (const [k, v] of Object.entries(vars)) s = s.replaceAll('{' + k + '}', v);
  }
  return s;
}
