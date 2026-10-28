// API 라우터 — 관리자/공개 랜딩이 호출. 서버 서비스 계층 단일 진입.
import { authClient, supa } from './supa.mjs';
import { fail } from './fl-util.mjs';
import * as YT from './yt.mjs';
import * as Typing from './yt-typing.mjs';
import { authenticate } from './fl-auth.mjs';

const ok = (data, status = 200) => ({ status, data });

// Supabase 인증 passthrough(비밀번호 로그인/가입/갱신). 단일 운영자 모델.
async function auth(path, body) {
  const sb = authClient();
  if (path === '/auth/login') {
    const { data, error } = await sb.auth.signInWithPassword({ email: body.email, password: body.password });
    if (error) throw fail(error.message || '로그인 실패', 401);
    return ok({ session: data.session });
  }
  if (path === '/auth/signup') {
    // 주인이 이미 있으면 공개 가입 차단(단일 운영자). MASTER_EMAILS 설정 시 허용.
    if (!process.env.MASTER_EMAILS) {
      const { data: site } = await supa.from('fl_site').select('owner_user_id').eq('id', 1).maybeSingle();
      if (site?.owner_user_id) throw fail('이미 운영자가 등록되어 있습니다. 로그인해 주세요.', 403);
    }
    const { data, error } = await sb.auth.signUp({ email: body.email, password: body.password });
    if (error) throw fail(error.message || '가입 실패', 400);
    if (data.user) { try { await supa.from('fl_site').update({ owner_user_id: data.user.id }).eq('id', 1).is('owner_user_id', null); } catch { /* best-effort */ } }
    return ok({ session: data.session, requires_confirmation: !data.session });
  }
  if (path === '/auth/refresh') {
    const { data, error } = await sb.auth.refreshSession({ refresh_token: body.refresh_token });
    if (error) throw fail('다시 로그인해주세요', 401);
    return ok({ session: data.session });
  }
  return null;
}

export async function handleApi(path, method, body, query, headers) {
  // ── 인증 ──
  if (path.startsWith('/auth/') && method === 'POST') { const r = await auth(path, body); if (r) return r; }

  // ── 공개(랜딩·조회) ──
  if (path === '/yt/featured' && method === 'GET') return ok(await YT.featuredComments({ limit: +query.limit || 12 }));
  if (path === '/yt/videos' && method === 'GET') return ok(await YT.searchVideos({ q: query.q, order: query.order, max: +query.max || 50, minViews: +query.minViews || 0, maxViews: +query.maxViews || 0, minVph: +query.minVph || 0, pageToken: query.pageToken || '' }));
  if (path === '/yt/video-add' && method === 'GET') return ok(await YT.addVideoByUrl(query.url));
  if (path === '/yt/videos/saved' && method === 'GET') return ok(await YT.listSavedVideos({ limit: +query.limit || 24, offset: +query.offset || 0 }));
  if (path === '/yt/context' && method === 'GET') return ok(await YT.videoContext(query.id));
  if (path === '/yt/draft' && method === 'POST') return ok(await YT.makeDraft({ videoId: body.videoId, video: body.video, context: body.context }));
  if (path === '/yt/extracted' && method === 'GET') return ok(await YT.listExtracted({ limit: +query.limit || 24, offset: +query.offset || 0 }));
  if (path === '/yt/extracted/one' && method === 'GET') return ok(await YT.getExtracted(query.id));
  if (path === '/yt/settings' && method === 'GET') return ok(await YT.getSetting());
  if (path === '/yt/ai-status' && method === 'GET') return ok(await YT.aiStatus());
  if (path === '/yt/log' && method === 'GET') return ok(await YT.listLog({ limit: +query.limit || 100 }));

  // ── 운영자 인증 필요(저장·게시·OAuth) ──
  if (path === '/yt/extract' && method === 'POST') { await authenticate(headers); return ok(await YT.extractVideo(body.videoId)); }
  if (path === '/yt/analysis' && method === 'POST') { await authenticate(headers); return ok(await YT.updateAnalysisComment(body.videoId, body.comment)); }
  if (path === '/yt/regenerate' && method === 'POST') { await authenticate(headers); return ok(await YT.regenerateComment(body.videoId)); }
  if (path === '/yt/settings' && method === 'POST') { await authenticate(headers); return ok(await YT.updateSetting(body)); }
  if (path === '/yt/post' && method === 'POST') { const { user } = await authenticate(headers); return ok(await YT.postComment({ ownerId: user.id, videoId: body.videoId, text: body.text, profile: body.profile })); }
  // 크롬 타이핑 시연 모드(로컬 전용)
  if (path === '/yt/type-post' && method === 'POST') { await authenticate(headers); return ok(Typing.startTypingPost({ videoId: body.videoId, text: body.text })); }
  if (path === '/yt/type-status' && method === 'GET') { await authenticate(headers); const j = Typing.getTypingJob(query.jobId); return ok(j || { status: 'notfound' }); }
  if (path === '/yt/feature' && method === 'POST') { await authenticate(headers); return ok(await YT.featureLog(body.id, body.featured)); }
  if (path === '/yt/export' && method === 'GET') { await authenticate(headers); return ok(await YT.exportCsv(query.kind)); }
  if (path === '/yt/stats' && method === 'GET') { const { user } = await authenticate(headers); return ok(await YT.stats(user.id)); }
  if (path === '/yt/oauth/status' && method === 'GET') { const { user } = await authenticate(headers); return ok(await YT.oauthStatus(user.id)); }
  if (path === '/yt/oauth/url' && method === 'GET') { const { user } = await authenticate(headers); return ok({ url: YT.authUrl(YT.signState(user.id)) }); }
  if (path === '/yt/oauth/disconnect' && method === 'POST') { const { user } = await authenticate(headers); return ok(await YT.disconnect(user.id)); }

  throw fail('알 수 없는 요청입니다: ' + method + ' ' + path, 404);
}
