// 크롬 타이핑 시연 모드 — Playwright로 전용 프로필 크롬을 띄워, 선택한 영상의 댓글창에
// 한 글자씩 타이핑하고 게시한다. (본인 계정 1개, 다계정·탐지우회 없음 / 데모·검증용)
// 과제 요구: "프로필 폴더를 지정해 여는 방식(launchPersistentContext, --user-data-dir)".
import path from 'node:path';
import fs from 'node:fs';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { supa } from './supa.mjs';

const __dir = path.dirname(fileURLToPath(import.meta.url));
const USER_DATA_DIR = path.resolve(__dir, '../.pw-profile'); // 평소 쓰는 기본 프로필 아님(전용 폴더)

// 이 전용 프로필을 쓰는 잔존 크롬만 정밀 종료 + 잠금파일 정리.
// (user-data-dir 경로로만 매칭 → 사용자의 일반 크롬은 건드리지 않음)
function releaseProfile() {
  try { execSync(`pkill -f "user-data-dir=${USER_DATA_DIR}"`, { stdio: 'ignore' }); } catch { /* 없으면 무시 */ }
  for (const f of ['SingletonLock', 'SingletonCookie', 'SingletonSocket']) {
    try { fs.rmSync(path.join(USER_DATA_DIR, f), { force: true }); } catch { /* */ }
  }
}

const jobs = new Map();   // jobId -> job
let currentCtx = null;    // 직전 브라우저 컨텍스트(새 실행 전 닫기)

export function getTypingJob(id) {
  const j = jobs.get(id);
  if (!j) return null;
  const { ctx, ...pub } = j; // 내부 핸들 제외
  return pub;
}

export function startTypingPost({ videoId, text }) {
  const jobId = 'tj_' + Math.random().toString(36).slice(2, 10);
  const job = { jobId, status: 'running', step: 'launching', stepLabel: '크롬 프로필 여는 중…', error: '', commentLink: '', screenshot: '', videoId };
  jobs.set(jobId, job);
  runTyping(job, videoId, String(text || '')).catch((e) => {
    job.status = 'failed'; job.step = 'failed'; job.stepLabel = '실패'; job.error = String(e?.message || e);
  });
  return { jobId };
}

async function runTyping(job, videoId, text) {
  const { chromium } = await import('playwright');
  const url = 'https://www.youtube.com/watch?v=' + videoId;
  let ctx, page;
  const set = (step, label) => { job.step = step; job.stepLabel = label; };
  try {
    // 직전 창 닫기 + 잔존 프로필 크롬/잠금 정리(HMR로 핸들 유실 대비)
    try { if (currentCtx) await currentCtx.close(); } catch { /* */ }
    currentCtx = null;
    releaseProfile();
    await new Promise((r) => setTimeout(r, 500));
    set('launching', '크롬 프로필 여는 중…');
    const opts = { headless: false, viewport: { width: 1280, height: 900 }, args: ['--start-maximized', '--disable-blink-features=AutomationControlled'] };
    try {
      ctx = await chromium.launchPersistentContext(USER_DATA_DIR, { ...opts, channel: 'chrome' });
    } catch (e) {
      // 시스템 크롬(channel:'chrome') 실행 실패 → 번들 크로미움은 설치 안 돼 있을 수 있으니 원인을 그대로 알림
      throw new Error('크롬 실행 실패 — 같은 전용 프로필(.pw-profile) 크롬 창이 이미 열려 있으면 닫고 다시 시도하세요. (원인: ' + String(e?.message || e).slice(0, 160) + ')');
    }
    currentCtx = ctx; job.ctx = ctx;
    page = ctx.pages()[0] || await ctx.newPage();

    set('navigating', '영상 여는 중…');
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(2500);

    // 로그인 확인(아바타 버튼). 로그인돼 있으면 그냥 통과, 안 돼 있으면 창을 열어둔 채 대기→로그인되면 자동 재개.
    const isSignedIn = async () =>
      (await page.locator('#avatar-btn, ytd-topbar-menu-button-renderer #avatar-btn').first().count().catch(() => 0)) > 0;
    if (!(await isSignedIn())) {
      set('login', '유튜브 로그인이 필요해요 — 열린 크롬 창에서 로그인하면 자동으로 이어집니다…');
      const deadline = Date.now() + 180000; // 최대 3분 대기
      let ok = false;
      while (Date.now() < deadline) {
        await page.waitForTimeout(2000);
        if (await isSignedIn().catch(() => false)) { ok = true; break; }
      }
      if (!ok) {
        job.status = 'failed'; job.step = 'login'; job.stepLabel = '로그인 대기 시간 초과';
        job.error = '로그인 대기 시간이 초과됐어요(3분). 열린 크롬 창에서 로그인한 뒤 다시 실행하세요. (전용 프로필이라 한 번만 로그인하면 유지됩니다)';
        return;
      }
      // 로그인 과정에서 다른 페이지로 이동했을 수 있으니 영상으로 복귀
      set('navigating', '로그인 확인 — 영상으로 돌아가는 중…');
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
      await page.waitForTimeout(2500);
    }

    // 댓글 영역까지 스크롤(지연 로드)
    set('navigating', '댓글 영역 여는 중…');
    for (let i = 0; i < 6; i++) { await page.mouse.wheel(0, 700); await page.waitForTimeout(500); }
    await page.waitForTimeout(1500);

    // 댓글 입력창 열기
    set('typing', '댓글 입력 중…');
    const placeholder = page.locator('#simplebox-placeholder, ytd-comment-simplebox-renderer #placeholder-area, #placeholder-area').first();
    await placeholder.click({ timeout: 25000 });
    const editable = page.locator('#contenteditable-root, ytd-comment-simplebox-renderer #contenteditable-root').first();
    await editable.click({ timeout: 10000 });
    // ★ 한 글자씩 타이핑
    await editable.pressSequentially(text, { delay: 55 });
    await page.waitForTimeout(700);

    // 게시
    set('posting', '게시 중…');
    const submit = page.locator('#submit-button button, ytd-button-renderer#submit-button button, #submit-button').first();
    await submit.click({ timeout: 10000 });
    await page.waitForTimeout(3500);

    set('posting', '게시 기록 저장 중…');
    job.commentLink = url;
    // ★ 게시 기록 남기기 → '게시됨' 배지 반영 (API 게시와 동일하게 yt_log에 기록). status='done'은 기록 후 설정(프론트 레이스 방지)
    try {
      const { count: dup } = await supa.from('yt_log').select('id', { count: 'exact', head: true }).eq('video_id', videoId).eq('success', true);
      if (!dup) {
        const { data: vid } = await supa.from('yt_video').select('title').eq('id', videoId).maybeSingle();
        await supa.from('yt_log').insert({ video_id: videoId, video_title: vid?.title || '', video_link: url, profile: '크롬 타이핑', body: text, status: 'posted', success: true, comment_link: url });
      }
    } catch (e) { /* 로그 실패는 게시 성공에 영향 없음 */ }
    set('done', '게시 완료');
    job.status = 'done';
    // 데모용으로 창은 열어둠(게시된 댓글 확인). 사용자가 닫거나 다음 실행 때 닫힘.
  } catch (e) {
    job.status = 'failed'; job.step = 'failed'; job.stepLabel = '실패'; job.error = String(e?.message || e).slice(0, 300);
    try { if (page) { const buf = await page.screenshot({ type: 'png' }); job.screenshot = 'data:image/png;base64,' + buf.toString('base64'); } } catch { /* */ }
  }
}
