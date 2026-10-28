// CMS 배포 패키지 생성 — Vercel 빌드본(.vercel/output 전체=config+functions+static)을
// 배포 마법사 포맷(__wakit/vercel-manifest.json.gz)으로 + 스키마(__wakit/schema.sql·manifest.json.schema·cms-schema.json).
// ★앱 번들은 모든 CMS 공통(제네릭 엔진). 프로젝트별로 다른 건 스키마뿐 → schema.sql(Supabase DDL+시드) + enriched 스키마.
//   enriched 스키마는 manifest.json.schema 에 넣어 마법사가 CMS_SCHEMA_JSON env 로 주입(런타임, 견고). cms-schema.json 은 파일폴백.
// 사용법:
//   node package-cms-deploy.mjs [--schema-sql <file>] [--schema-json <file>] [--out <zip>] [--name <표시명>]
//     인자 없으면 샘플 스키마(_cms_sample_schema.*) + deploy/wakit-cms-deploy.zip (하위호환)
// 재사용: import { buildCmsDeployZip } from './package-cms-deploy.mjs'  (엔진 MCP가 프로젝트 스키마로 호출)
import { readdirSync, readFileSync, lstatSync, readlinkSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import JSZip from 'jszip';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, '.vercel/output');

const sha1 = (buf) => createHash('sha1').update(buf).digest('hex');
// ★제품 번들서 제외 — 개발 전용 찌꺼기. .sandbox=미리보기 SQLite+업로드이미지(제품모드는 유저 Supabase 사용, 불필요). 넣으면 수MB 폭증→마법사 6MB 한도 초과.
const BUNDLE_SKIP = new Set(['.sandbox', '.DS_Store']);
function walk(dir, base, acc = []) {
  for (const name of readdirSync(dir)) {
    if (BUNDLE_SKIP.has(name)) continue;
    const full = path.join(dir, name);
    const st = lstatSync(full);
    // ★심링크는 따라가지 않고(lstat) 심링크로 기록 — split:false 는 함수 1개 + 라우트별 심링크라, 따라가면 중복. Vercel prebuilt 는 심링크(mode 40960) 지원.
    if (st.isSymbolicLink()) acc.push({ rel: path.relative(base, full), symlink: readlinkSync(full) });
    else if (st.isDirectory()) walk(full, base, acc);
    else acc.push({ rel: path.relative(base, full), data: readFileSync(full) });
  }
  return acc;
}

// 제네릭 앱 빌드본(.vercel/output) → gzip 리프 매니페스트. ★config.json mtime 으로 캐시 무효화(재빌드 후 stale 방지).
let _appGz = null, _appGzMtime = 0;
function appManifestGz() {
  if (!existsSync(path.join(OUT, 'config.json'))) throw new Error('빌드본 없음 — 먼저 `VERCEL=1 npm run build` 하세요: ' + OUT);
  const mt = lstatSync(path.join(OUT, 'config.json')).mtimeMs;
  if (_appGz && _appGzMtime === mt) return _appGz;
  _appGzMtime = mt;
  const entries = walk(OUT, OUT);
  const leaves = entries.map((e) => e.symlink !== undefined
    ? (() => { const b = Buffer.from(e.symlink, 'utf8'); return { rel: e.rel, mode: 40960, sha: sha1(b), d: b.toString('base64') }; })()
    : { rel: e.rel, mode: 33188, sha: sha1(e.data), d: e.data.toString('base64') });
  _appGz = { gz: gzipSync(Buffer.from(JSON.stringify(leaves), 'utf8'), { level: 9 }), count: leaves.length };
  return _appGz;
}

// ★핵심: (제네릭 앱 빌드본) + (프로젝트 schema.sql + enriched 스키마) → 배포 마법사용 zip 버퍼.
export async function buildCmsDeployZip({ schemaSql = '', schemaJson = null, frontJson = null, name = 'wakit-cms' } = {}) {
  const { gz, count } = appManifestGz();
  const enriched = typeof schemaJson === 'string' ? JSON.parse(schemaJson) : schemaJson;
  const front = typeof frontJson === 'string' ? JSON.parse(frontJson) : frontJson; // 프론트 웹템플릿 {html,css,config} → 마법사가 CMS_FRONT_JSON env 로 주입
  const zip = new JSZip();
  zip.file('__wakit/vercel-manifest.json.gz', gz);
  if (schemaSql) zip.file('__wakit/schema.sql', schemaSql); // 마법사 supabase-setup 이 유저 Supabase 에 적용(RLS강제)
  zip.file('__wakit/manifest.json', JSON.stringify({
    product: name, schema: enriched || undefined, front: front || undefined, dbSchema: 'public', host: 'vercel', region: 'icn1',
    prebuilt: true, files: count, hasSchema: !!schemaSql, hasFront: !!front,
  }));
  if (enriched) zip.file('cms-schema.json', JSON.stringify(enriched)); // 제품모드 pgSchema 파일폴백(env 우선, 이건 보조)
  zip.file('README.txt', 'wakit CMS 배포 패키지\n\n- 배포 마법사에 이 ZIP을 올리고 본인 Supabase를 연결하면,\n  앱(Vercel) + 스키마(Supabase, RLS강제) 가 함께 설치되어 "내 소유 CMS" 가 됩니다.\n- 앱 번들은 CMS 공통 엔진, schema.sql/스키마 매니페스트가 내 커스텀 기능.\n');
  return { buf: await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }), files: count };
}

// CLI
if (import.meta.url === `file://${process.argv[1]}`) {
  const argv = process.argv.slice(2);
  const argVal = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
  const sqlPath = argVal('--schema-sql', path.join(HERE, '../_cms_sample_schema.sql'));
  const jsonPath = argVal('--schema-json', path.join(HERE, '../_cms_sample_schema.json'));
  const frontPath = argVal('--front-json', null);
  const outZip = argVal('--out', path.join(HERE, 'deploy/wakit-cms-deploy.zip'));
  const name = argVal('--name', 'wakit-cms');
  const schemaSql = existsSync(sqlPath) ? readFileSync(sqlPath, 'utf8') : '';
  const schemaJson = existsSync(jsonPath) ? readFileSync(jsonPath, 'utf8') : null;
  const frontJson = frontPath && existsSync(frontPath) ? readFileSync(frontPath, 'utf8') : null;
  const { buf, files } = await buildCmsDeployZip({ schemaSql, schemaJson, frontJson, name });
  const dir = path.dirname(outZip); if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(outZip, buf);
  const nt = schemaJson ? (JSON.parse(schemaJson).tables || []).length : 0;
  console.log(`패키지: ${outZip}  (앱파일 ${files}개, ${(buf.length / 1048576).toFixed(1)}MB, 스키마 ${nt}테이블, DDL ${schemaSql ? (schemaSql.length / 1024).toFixed(0) + 'KB' : '없음'})`);
}
