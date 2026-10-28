// .vercel/output 의 서버리스 함수(catchall)를 esbuild 로 단일 파일 번들 → 파일수 ~548→~160.
//   Netlify 함수 10초 업로드 한도 대응(파일당 Vercel 왕복이 병목). VERCEL 빌드 후 실행.
//   adapter-vercel 이 추적한 node_modules·server 트리를 번들에 인라인 → 원본 파일들 제거.
import { build } from 'esbuild';
import { rmSync, existsSync, readdirSync, lstatSync, renameSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FUNCS = path.join(HERE, '.vercel/output/functions');
if (!existsSync(FUNCS)) { console.log('[bundle-fn] .vercel/output 없음 — 스킵(비 Vercel 빌드)'); process.exit(0); }

// 실제 함수 디렉토리(심링크 아님 + 핸들러 보유) 수집.
function findRealFuncs(dir, acc = []) {
  for (const name of readdirSync(dir)) {
    const full = path.join(dir, name);
    let st; try { st = lstatSync(full); } catch { continue; }
    if (st.isSymbolicLink()) continue;
    if (st.isDirectory()) {
      if (name.endsWith('.func') && existsSync(path.join(full, '.svelte-kit/vercel-tmp/index.js'))) acc.push(full);
      else findRealFuncs(full, acc);
    }
  }
  return acc;
}

const funcs = findRealFuncs(FUNCS);
if (!funcs.length) { console.log('[bundle-fn] 번들할 함수 없음'); process.exit(0); }

for (const func of funcs) {
  const entry = path.join(func, '.svelte-kit/vercel-tmp/index.js');
  const nm = path.join(func, 'node_modules');
  const nmBak = nm + '.__bak';
  // 추적된 부분 node_modules(tslib 등 불완전)를 치우고 전체 node_modules 로 resolve.
  if (existsSync(nm)) renameSync(nm, nmBak);
  try {
    await build({ entryPoints: [entry], bundle: true, platform: 'node', format: 'esm', target: 'node20', outfile: entry, allowOverwrite: true, logLevel: 'error', legalComments: 'none' });
  } finally {
    if (existsSync(nmBak)) rmSync(nmBak, { recursive: true, force: true });
  }
  // 번들 자체완결 → 서버 트리·개발 샌드박스 제거(파일수↓).
  rmSync(path.join(func, '.svelte-kit/output'), { recursive: true, force: true });
  rmSync(path.join(func, '.sandbox'), { recursive: true, force: true });
  console.log('[bundle-fn] 번들 완료:', path.relative(HERE, func));
}
