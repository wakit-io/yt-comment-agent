// Supabase 클라이언트 (서비스 롤). 로컬=.env, Netlify=함수 환경변수.
import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

try {
  const envPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../.env');
  for (const line of readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
} catch (e) { /* no .env (e.g. Netlify) → use real env */ }

// 배포 환경에 따라 env 변수명이 다를 수 있어 둘 다 허용(배포 마법사는 PUBLIC_* 를 세팅).
const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
if (!URL || !KEY) console.error('[fl] SUPABASE_URL(또는 PUBLIC_SUPABASE_URL) / SUPABASE_SERVICE_ROLE_KEY 필요');

export const supa = createClient(URL || 'http://127.0.0.1:54351', KEY || 'missing', {
  auth: { persistSession: false, autoRefreshToken: false }
});

export function userClient(token) {
  return createClient(URL || 'http://127.0.0.1:54351', ANON || KEY || 'missing', {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
}
export function authClient() {
  return createClient(URL || 'http://127.0.0.1:54351', ANON || KEY || 'missing', {
    auth: { persistSession: false, autoRefreshToken: false }
  });
}
