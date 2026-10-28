// YT 댓글 어시스턴트 — 코어. YouTube Data API(fetch 직접) + OAuth + Gemini 초안 + 운영규칙.
//   DB=service_role(supa). 관리자 액션은 라우트에서 authenticate 로 게이팅.
import { supa } from './supa.mjs';
import { createHmac } from 'node:crypto';

const YT = 'https://www.googleapis.com/youtube/v3';
const OAUTH_SCOPE = 'https://www.googleapis.com/auth/youtube.force-ssl';

const env = (k) => (process.env[k] || '').trim();
function needApiKey() { const k = env('YT_API_KEY'); if (!k) throw Object.assign(new Error('YT_API_KEY 가 .env 에 없습니다. (Google Cloud → YouTube Data API v3 → API 키)'), { status: 412 }); return k; }

// ── 영상 불러오기 ───────────────────────────────────────────────
// q 있으면 검색, 없으면 인기(mostPopular). order=date|viewCount|relevance.
// 유튜브 링크/ID에서 videoId 추출 (watch?v= · youtu.be · shorts · embed · 11자 id).
function videoIdFromUrl(u) {
  if (!u) return '';
  u = String(u).trim();
  if (/^[\w-]{11}$/.test(u)) return u;
  try {
    const url = new URL(u.startsWith('http') ? u : 'https://' + u);
    if (url.hostname.includes('youtu.be')) { const m = url.pathname.match(/[\w-]{11}/); if (m) return m[0]; }
    const v = url.searchParams.get('v'); if (v && /^[\w-]{11}/.test(v)) return v.slice(0, 11);
    const m = url.pathname.match(/\/(shorts|embed|v|live)\/([\w-]{11})/); if (m) return m[2];
  } catch { /* */ }
  const m = u.match(/[\w-]{11}/); return m ? m[0] : '';
}

// 링크로 직접 영상 추가(한 개) → 캐시에 upsert. 사용자가 고른 링크라 카테고리/댓글꺼짐 필터 안 함.
export async function addVideoByUrl(url) {
  const key = needApiKey();
  const id = videoIdFromUrl(url);
  if (!id) throw Object.assign(new Error('유효한 유튜브 링크가 아니에요. (watch?v=… / youtu.be/… / shorts/…)'), { status: 422 });
  const [v] = await hydrateVideos([id], key);
  if (!v) throw Object.assign(new Error('영상을 찾을 수 없어요 (비공개·삭제·잘못된 링크).'), { status: 404 });
  try { await supa.from('yt_video').upsert(stripForCache(v), { onConflict: 'id' }); } catch { /* */ }
  return v;
}

export async function searchVideos({ q = '', order = 'date', max = 24, regionCode = 'KR', minViews = 0, maxViews = 0, minVph = 0, pageToken = '' } = {}) {
  const key = needApiKey();
  let ids = []; let nextPageToken = '';
  if (q) {
    const u = new URL(YT + '/search');
    const sp = { part: 'snippet', q, type: 'video', order, maxResults: String(Math.min(max, 50)), regionCode, relevanceLanguage: 'ko', key };
    if (pageToken) sp.pageToken = pageToken;
    u.search = new URLSearchParams(sp).toString();
    const j = await getJson(u, 'search');
    ids = (j.items || []).map((it) => it.id?.videoId).filter(Boolean);
    nextPageToken = j.nextPageToken || '';
  } else {
    const u = new URL(YT + '/videos');
    const sp = { part: 'id', chart: 'mostPopular', regionCode, videoCategoryId: '0', maxResults: String(Math.min(max, 50)), key };
    if (pageToken) sp.pageToken = pageToken;
    u.search = new URLSearchParams(sp).toString();
    const j = await getJson(u, 'videos');
    ids = (j.items || []).map((it) => it.id).filter(Boolean);
    nextPageToken = j.nextPageToken || '';
  }
  if (!ids.length) return { items: [], nextPageToken };
  const rows = await hydrateVideos(ids, key);
  const lo = +minViews || 0, hi = +maxViews || 0, vph = +minVph || 0;
  const now = Date.now();
  // 시간당 조회수(뜨는 영상 판별): 조회수 / 업로드 후 경과시간(h).
  const vphOf = (v) => { const ms = v.published_at ? (now - new Date(v.published_at).getTime()) : 0; const h = Math.max(ms / 3600000, 0.5); return v.view_count / h; };
  // 댓글 꺼진 영상·관련 없는 카테고리(음악10·게임20·뉴스정치25) 애초에 제외.
  const EXCLUDE_CATS = new Set(['10', '20', '25']);
  const filtered = rows.filter((v) => !v.comments_disabled && !EXCLUDE_CATS.has(v.category_id)
    && (lo ? v.view_count >= lo : true) && (hi ? v.view_count <= hi : true)
    && (vph ? vphOf(v) >= vph : true));
  // 뜨는 영상 모드면 시간당 조회수 높은 순으로.
  if (vph) filtered.sort((a, b) => vphOf(b) - vphOf(a));
  // 캐시(선택) — 나중 상세/로그에서 제목 참조용.
  try { if (filtered.length) await supa.from('yt_video').upsert(filtered.map(stripForCache), { onConflict: 'id' }); } catch { /* best-effort */ }
  return { items: filtered, nextPageToken };
}

async function hydrateVideos(ids, key) {
  const u = new URL(YT + '/videos');
  u.search = new URLSearchParams({ part: 'snippet,statistics,contentDetails', id: ids.join(','), key }).toString();
  const j = await getJson(u, 'videos');
  return (j.items || []).map((it) => ({
    id: it.id,
    title: it.snippet?.title || '',
    channel_id: it.snippet?.channelId || '',
    channel_title: it.snippet?.channelTitle || '',
    category_id: it.snippet?.categoryId || '',
    published_at: it.snippet?.publishedAt || null,
    thumb: it.snippet?.thumbnails?.medium?.url || it.snippet?.thumbnails?.default?.url || '',
    view_count: +(it.statistics?.viewCount || 0),
    like_count: +(it.statistics?.likeCount || 0),
    comment_count: +(it.statistics?.commentCount || 0),
    // 댓글 비활성화 감지: 꺼진 영상은 statistics.commentCount 필드 자체가 없음(0과 구분).
    comments_disabled: it.statistics?.commentCount == null,
    duration: it.contentDetails?.duration || '',
    description: it.snippet?.description || '',
  }));
}
function stripForCache(v) { const { context, category_id, ...rest } = v; return { ...rest, fetched_at: new Date().toISOString() }; }

// 저장(수집)해둔 영상 목록 — 재진입 시 리스트가 비지 않게. 최근 불러온 순. 무한스크롤용 offset 페이지네이션.
export async function listSavedVideos({ limit = 24, offset = 0 } = {}) {
  const lim = Math.min(Math.max(+limit || 24, 1), 60);
  const off = Math.max(+offset || 0, 0);
  const { data } = await supa.from('yt_video')
    .select('id,title,channel_id,channel_title,thumb,view_count,like_count,comment_count,comments_disabled,duration,published_at,fetched_at,extracted_at')
    .order('fetched_at', { ascending: false })
    .order('id', { ascending: true }) // 2차 키 — 동일 fetched_at에서 페이지 경계 중복/누락 방지
    .range(off, off + lim - 1);
  return data || [];
}

// ── 영상 맥락(선택 시) ───────────────────────────────────────────
// 제목·설명 + 인기 댓글(최대 N) 수집. (자막은 OAuth·권한 이슈로 제외 — 설명/댓글로 맥락 충분)
export async function videoContext(videoId, { commentMax = 15 } = {}) {
  const key = needApiKey();
  const [vid] = await hydrateVideos([String(videoId)], key);
  if (!vid) throw Object.assign(new Error('영상을 찾을 수 없습니다.'), { status: 404 });
  let top_comments = [];
  try {
    const u = new URL(YT + '/commentThreads');
    u.search = new URLSearchParams({ part: 'snippet', videoId: String(videoId), order: 'relevance', maxResults: String(Math.min(commentMax, 50)), textFormat: 'plainText', key }).toString();
    const j = await getJson(u, 'commentThreads');
    top_comments = (j.items || []).map((it) => {
      const s = it.snippet?.topLevelComment?.snippet || {};
      return { author: s.authorDisplayName || '', text: (s.textOriginal || '').slice(0, 500), likes: +(s.likeCount || 0) };
    });
  } catch (e) { /* 댓글 비공개 영상 등 — best-effort */ }
  const context = { top_comments };
  try { await supa.from('yt_video').upsert({ ...stripForCache(vid), context }, { onConflict: 'id' }); } catch { /* */ }
  return { video: vid, context };
}

// ── AI 댓글 초안(Gemini 기본) ────────────────────────────────────
const AI_DEFAULT_MODEL = { google: 'gemini-3.8-flash', anthropic: 'claude-haiku-5-5', openai: 'gpt-4o-mini' };
function aiKey(provider) {
  if (provider === 'anthropic') return env('ANTHROPIC_API_KEY');
  if (provider === 'openai') return env('OPENAI_API_KEY');
  return env('GEMINI_API_KEY') || env('GOOGLE_API_KEY');
}

function aiEnvVar(provider) { return provider === 'openai' ? 'OPENAI_API_KEY' : provider === 'anthropic' ? 'ANTHROPIC_API_KEY' : 'GEMINI_API_KEY'; }
// 설정 화면용: 현재 provider/model + 해당 env 키가 꽂혔는지.
export async function aiStatus() {
  const s = await getSetting();
  const provider = s.provider || 'google';
  return { provider, model: s.model || '', env_var: aiEnvVar(provider), configured: !!aiKey(provider) };
}

// 댓글 생성 시스템 프롬프트(브랜드 공개 모드/일반 시청자 모드 분기). draftComment·regenerateComment 공용.
function buildCommentSys(s) {
  const lenRule = `반드시 공백 포함 ${s.max_chars}자 이내(절대 넘기지 말 것), 최소 ${s.min_chars}자 이상. 영상 속 구체적 장면이나 말을 하나 이상 언급. 영상마다 달라야 함.`;
  const jsonRule = '출력은 JSON: {"summary":"이 영상이 무슨 내용인지·어떤 연애 상황/고민인지·핵심 장면이나 대사를 2~3문장으로","worry_oneline":"영상 속 연애 고민 한 줄","comment":"실제 댓글 본문"}';
  return s.brand_open ? [
    `너는 "${s.brand}"(연애 사주/운세 서비스)의 공식 계정 운영자로서 유튜브 영상에 공개 댓글을 단다. 신분을 숨기지 말고 브랜드 입장에서 친근하게 쓴다.`,
    s.persona ? `[톤 참고] ${s.persona}` : '',
    `규칙: ${lenRule}`,
    `브랜드 공개: 영상 속 상황과 연결해 "${s.brand}"를 문장 안에 자연스럽게 녹여, 어떤 도움(연애 사주로 인연·흐름 봐주기 등)을 주는지 밝혀라. "— ${s.brand}" 같은 끝 서명/사인/따옴표는 절대 붙이지 말 것(댓글 본문 안에서 자연스럽게만). 과장·단정("무조건 맞힘" 등) 금지, 광고티 과하게 금지.`,
    '절대 금지: 링크, 해시태그, 타인인 척 지어낸 후기(공식 계정이니 "저희가"로 말하면 됨).',
    jsonRule,
  ].join('\n') : [
    '너는 유튜브 영상을 방금 본 시청자처럼 한국어 댓글을 쓰는 사람이다.',
    s.persona ? `[페르소나] 아래 인물의 목소리·말투로 써라: ${s.persona}` : '',
    `규칙: ${lenRule}`,
    '절대 금지: 링크, 해시태그, 광고 같은 말투, "직접 이용해봤다"는 지어낸 후기.',
    `목표: 자연스럽게 연애 고민에 공감하면서, 읽는 사람이 "${s.brand}" 같은 연애 사주를 한번 보고 싶어지도록 은근히 궁금증을 남길 것. ${s.brand} 를 직접 홍보하지 말고, 사주/운세가 궁금해지는 정서만 자연스럽게.`,
    jsonRule,
  ].join('\n');
}

// 댓글 본문 안전가드: 링크/해시태그 제거 + 끝 "— 브랜드" 서명 제거.
function cleanBody(body, brand) {
  body = String(body || '').replace(/https?:\/\/\S+/g, '').replace(/#[\p{L}\p{N}_]+/gu, '').replace(/\s{2,}/g, ' ').trim();
  if (brand) {
    const b = brand.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    body = body.replace(new RegExp('\\s*[—–\\-~]+\\s*["\'“”]?' + b + '["\'“”]?\\s*$'), '').trim();
  }
  return body;
}

export async function draftComment({ video, context, setting }) {
  const s = setting || await getSetting();
  const provider = s.provider || 'google';
  const model = s.model || AI_DEFAULT_MODEL[provider] || AI_DEFAULT_MODEL.google;
  const apiKey = aiKey(provider);
  if (!apiKey) throw Object.assign(new Error(`AI 키가 없습니다(${provider}). .env 에 넣어주세요.`), { status: 412 });

  const comments = (context?.top_comments || []).slice(0, 8).map((c) => `- ${c.text}`).join('\n');
  const sys = buildCommentSys(s);
  const prompt = [
    `[영상 제목] ${video?.title || ''}`,
    `[채널] ${video?.channel_title || ''}`,
    `[설명 일부] ${(video?.description || '').slice(0, 600)}`,
    comments ? `[인기 댓글]\n${comments}` : '',
    '',
    '위 영상 맥락을 읽고 worry_oneline 과 comment 를 JSON 으로만 출력해.',
  ].join('\n');

  // ★영상 분석: Gemini 는 유튜브 URL 을 직접 받아 영상(화면·대사)을 분석. 실패/비Gemini면 메타데이터 폴백.
  const videoUrl = video?.id ? ('https://www.youtube.com/watch?v=' + video.id) : '';
  let raw = '', source = 'metadata';
  if (provider === 'google' && videoUrl) {
    try {
      raw = await callLLM('google', apiKey, model, sys, prompt + '\n\n(위에 이 영상이 첨부돼 있어. 영상을 직접 보고, 실제 장면·대사를 근거로 써.)', { videoUrl, timeout: 110000 });
      source = 'video';
    } catch (e) {
      raw = await callLLM('google', apiKey, model, sys, prompt); // 영상 너무 길거나 미지원 → 폴백
      source = 'metadata';
    }
  } else {
    raw = await callLLM(provider, apiKey, model, sys, prompt);
  }
  const parsed = parseJsonLoose(raw);
  const body = cleanBody(parsed?.comment || raw || '', s.brand);
  const worry = String(parsed?.worry_oneline || '').trim();
  const summary = String(parsed?.summary || '').trim();
  return { summary, worry_oneline: worry, body, provider, model, source };
}

// ── 내용 추출(수집): 영상 분석 → DB 저장. "댓글 달기" 리스트의 재료. ──
export async function extractVideo(videoId) {
  const { video, context } = await videoContext(videoId);
  const d = await draftComment({ video, context });
  const analysis = { summary: d.summary, worry_oneline: d.worry_oneline, comment: d.body, source: d.source, provider: d.provider, model: d.model };
  await supa.from('yt_video').update({ analysis, extracted_at: new Date().toISOString() }).eq('id', videoId);
  try { await supa.from('yt_draft').insert({ video_id: videoId, worry_oneline: d.worry_oneline, body: d.body, provider: d.provider, model: d.model }); } catch { /* */ }
  return { video, analysis };
}
// 추출된 영상 목록("댓글 달기" 1페이지).
export async function listExtracted({ limit = 24, offset = 0 } = {}) {
  const lim = Math.min(Math.max(+limit || 24, 1), 300);
  const off = Math.max(+offset || 0, 0);
  const { data } = await supa.from('yt_video')
    .select('id,title,channel_title,thumb,view_count,published_at,analysis,extracted_at')
    .not('extracted_at', 'is', null)
    .order('extracted_at', { ascending: false })
    .order('id', { ascending: true }) // 2차 키 — 페이지 경계 중복/누락 방지
    .range(off, off + lim - 1);
  // 각 항목에 게시여부 표시
  const { data: posted } = await supa.from('yt_log').select('video_id').eq('success', true);
  const postedSet = new Set((posted || []).map((r) => r.video_id));
  return (data || []).map((v) => ({ ...v, posted: postedSet.has(v.id) }));
}
// 추출된 영상 1건(상세).
export async function getExtracted(videoId) {
  const { data: v } = await supa.from('yt_video').select('*').eq('id', videoId).maybeSingle();
  if (!v) throw Object.assign(new Error('영상을 찾을 수 없습니다.'), { status: 404 });
  const { data: lg } = await supa.from('yt_log').select('*').eq('video_id', videoId).order('created_at', { ascending: false });
  return { video: v, logs: lg || [] };
}
// 상세에서 댓글 초안 수정 저장.
export async function updateAnalysisComment(videoId, comment) {
  const { data: v } = await supa.from('yt_video').select('analysis').eq('id', videoId).maybeSingle();
  const analysis = { ...(v?.analysis || {}), comment: String(comment || '') };
  await supa.from('yt_video').update({ analysis }).eq('id', videoId);
  return { ok: true, analysis };
}

// 초안 생성 + yt_draft 저장(라우트용 래퍼). context 없으면 로드.
export async function makeDraft({ videoId, video, context }) {
  let v = video, c = context;
  if (!v || !c) { const r = await videoContext(videoId); v = r.video; c = r.context; }
  const d = await draftComment({ video: v, context: c });
  try { await supa.from('yt_draft').insert({ video_id: v.id, worry_oneline: d.worry_oneline, body: d.body, provider: d.provider, model: d.model }); } catch { /* */ }
  return { ...d, video: v };
}

// 댓글만 다시 생성(영상 재분석 X → 빠름). 저장된 요약/고민 재활용 + 변주(temperature)로 다른 버전 생성 → analysis.comment 갱신.
export async function regenerateComment(videoId) {
  const { data: v } = await supa.from('yt_video').select('*').eq('id', videoId).maybeSingle();
  if (!v) throw Object.assign(new Error('영상을 찾을 수 없습니다.'), { status: 404 });
  const s = await getSetting();
  const provider = s.provider || 'google';
  const model = s.model || AI_DEFAULT_MODEL[provider] || AI_DEFAULT_MODEL.google;
  const apiKey = aiKey(provider);
  if (!apiKey) throw Object.assign(new Error(`AI 키가 없습니다(${provider}). .env 에 넣어주세요.`), { status: 412 });

  const a = v.analysis || {};
  const sys = buildCommentSys(s);
  const prompt = [
    `[영상 제목] ${v.title || ''}`,
    `[채널] ${v.channel_title || ''}`,
    a.summary ? `[영상 요약] ${a.summary}` : '',
    a.worry_oneline ? `[영상 속 고민] ${a.worry_oneline}` : '',
    a.comment ? `[이전 초안 — 이것과는 다른 문장·표현·각도로] ${a.comment}` : '',
    '',
    'summary 와 worry_oneline 은 위 내용 그대로 간단히 채우고, comment 는 이전 초안과 확실히 다른 새 버전으로 하나만 써라. JSON 으로만 출력.',
  ].join('\n');
  // 텍스트 전용(영상 재첨부 없음) → 빠르고 저렴. temperature 높여 매번 다르게.
  const raw = await callLLM(provider, apiKey, model, sys, prompt, { temperature: 1.1, timeout: 30000 });
  const parsed = parseJsonLoose(raw);
  const body = cleanBody(parsed?.comment || raw || '', s.brand);
  if (!body) throw Object.assign(new Error('댓글 생성에 실패했어요. 다시 시도해 주세요.'), { status: 502 });
  const analysis = { ...a, comment: body, provider, model };
  await supa.from('yt_video').update({ analysis }).eq('id', videoId);
  try { await supa.from('yt_draft').insert({ video_id: videoId, worry_oneline: a.worry_oneline || '', body, provider, model }); } catch { /* */ }
  return { comment: body };
}

async function callLLM(provider, apiKey, model, system, prompt, opts = {}) {
  const ac = new AbortController(); const to = setTimeout(() => ac.abort(), opts.timeout || 25000);
  try {
    if (provider === 'openai') {
      const r = await fetch('https://api.openai.com/v1/chat/completions', { method: 'POST', signal: ac.signal, headers: { authorization: 'Bearer ' + apiKey, 'content-type': 'application/json' }, body: JSON.stringify({ model, max_tokens: 400, messages: [{ role: 'system', content: system }, { role: 'user', content: prompt }] }) });
      const j = await r.json(); if (!r.ok) throw new Error(j?.error?.message || ('OpenAI ' + r.status));
      return String(j?.choices?.[0]?.message?.content || '');
    }
    if (provider === 'anthropic') {
      const r = await fetch('https://api.anthropic.com/v1/messages', { method: 'POST', signal: ac.signal, headers: { 'x-api-key': apiKey, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' }, body: JSON.stringify({ model, max_tokens: 400, system, messages: [{ role: 'user', content: prompt }] }) });
      const j = await r.json(); if (!r.ok) throw new Error(j?.error?.message || ('Anthropic ' + r.status));
      return (j?.content || []).map((c) => c?.text || '').join('');
    }
    // Gemini. opts.videoUrl 있으면 유튜브 영상을 fileData 로 첨부(영상 직접 분석).
    const parts = [];
    if (opts.videoUrl) parts.push({ fileData: { fileUri: opts.videoUrl } });
    parts.push({ text: prompt });
    const url = 'https://generativelanguage.googleapis.com/v1beta/models/' + encodeURIComponent(model) + ':generateContent?key=' + encodeURIComponent(apiKey);
    // gemini-3.x 는 thinking 모델 → thinkingBudget:0 로 사고 억제하고 출력 토큰 넉넉히(안 그러면 답이 사고에 잠식돼 빈 응답).
    const genCfg = { maxOutputTokens: 2048, thinkingConfig: { thinkingBudget: 0 } };
    if (opts.temperature != null) genCfg.temperature = opts.temperature; // 다시 생성 변주용
    const r = await fetch(url, { method: 'POST', signal: ac.signal, headers: { 'content-type': 'application/json' }, body: JSON.stringify({ contents: [{ role: 'user', parts }], systemInstruction: { parts: [{ text: system }] }, generationConfig: genCfg }) });
    const j = await r.json(); if (!r.ok) throw new Error(j?.error?.message || ('Gemini ' + r.status));
    return (j?.candidates?.[0]?.content?.parts || []).map((p) => p?.text || '').join('');
  } finally { clearTimeout(to); }
}

// ── OAuth(본인 계정 게시) ────────────────────────────────────────
export function oauthConfigured() { return !!(env('GOOGLE_CLIENT_ID') && env('GOOGLE_CLIENT_SECRET')); }
export function authUrl(state = '') {
  if (!oauthConfigured()) throw Object.assign(new Error('GOOGLE_CLIENT_ID/SECRET 가 .env 에 없습니다.'), { status: 412 });
  const u = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  // select_account → 다른 구글 계정으로 전환 가능(계정 선택창 표시). consent → refresh_token 재발급.
  u.search = new URLSearchParams({ client_id: env('GOOGLE_CLIENT_ID'), redirect_uri: env('GOOGLE_OAUTH_REDIRECT'), response_type: 'code', scope: OAUTH_SCOPE, access_type: 'offline', prompt: 'select_account consent', include_granted_scopes: 'true', state }).toString();
  return u.toString();
}
// OAuth state 서명(브라우저 리다이렉트엔 bearer가 없어 ownerId를 state로 실어 보냄).
function stateSecret() { return env('SUPABASE_SERVICE_ROLE_KEY') || 'yt-state'; }
export function signState(ownerId) {
  const p = Buffer.from(JSON.stringify({ o: ownerId, e: Date.now() + 600000 })).toString('base64url');
  const sig = createHmac('sha256', stateSecret()).update(p).digest('base64url').slice(0, 24);
  return p + '.' + sig;
}
export function verifyState(state) {
  const [p, sig] = String(state || '').split('.');
  if (!p || !sig) return null;
  if (createHmac('sha256', stateSecret()).update(p).digest('base64url').slice(0, 24) !== sig) return null;
  try { const j = JSON.parse(Buffer.from(p, 'base64url').toString()); return j.e < Date.now() ? null : j.o; } catch { return null; }
}
export async function exchangeCode(code, ownerId) {
  const body = new URLSearchParams({ code, client_id: env('GOOGLE_CLIENT_ID'), client_secret: env('GOOGLE_CLIENT_SECRET'), redirect_uri: env('GOOGLE_OAUTH_REDIRECT'), grant_type: 'authorization_code' });
  const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body });
  const j = await r.json(); if (!r.ok) throw Object.assign(new Error(j?.error_description || j?.error || 'OAuth 교환 실패'), { status: 400 });
  const expiry = new Date(Date.now() + (j.expires_in || 3500) * 1000).toISOString();
  let channel_id = '', channel_title = '';
  try { const ch = await channelOf(j.access_token); channel_id = ch.id; channel_title = ch.title; } catch { /* */ }
  await supa.from('yt_oauth').upsert({ owner_id: ownerId, access_token: j.access_token, refresh_token: j.refresh_token || null, expiry, scope: j.scope || OAUTH_SCOPE, channel_id, channel_title, updated_at: new Date().toISOString() }, { onConflict: 'owner_id' });
  return { channel_title, channel_id };
}
async function channelOf(accessToken) {
  const r = await fetch(YT + '/channels?part=snippet&mine=true', { headers: { authorization: 'Bearer ' + accessToken } });
  const j = await r.json(); if (!r.ok) throw new Error(j?.error?.message || 'channels 실패');
  const it = (j.items || [])[0] || {};
  return { id: it.id || '', title: it.snippet?.title || '' };
}
async function validAccessToken(ownerId) {
  const { data: row } = await supa.from('yt_oauth').select('*').eq('owner_id', ownerId).maybeSingle();
  if (!row?.access_token) throw Object.assign(new Error('먼저 YouTube 계정을 연결하세요(설정 → 계정 연결).'), { status: 412 });
  if (row.expiry && new Date(row.expiry).getTime() > Date.now() + 60000) return row.access_token;
  if (!row.refresh_token) return row.access_token; // 만료됐지만 갱신토큰 없음 → 일단 시도
  const body = new URLSearchParams({ client_id: env('GOOGLE_CLIENT_ID'), client_secret: env('GOOGLE_CLIENT_SECRET'), refresh_token: row.refresh_token, grant_type: 'refresh_token' });
  const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body });
  const j = await r.json(); if (!r.ok) throw Object.assign(new Error(j?.error_description || 'OAuth 갱신 실패'), { status: 401 });
  const expiry = new Date(Date.now() + (j.expires_in || 3500) * 1000).toISOString();
  await supa.from('yt_oauth').update({ access_token: j.access_token, expiry, updated_at: new Date().toISOString() }).eq('owner_id', ownerId);
  return j.access_token;
}
export async function oauthStatus(ownerId) {
  const { data: row } = await supa.from('yt_oauth').select('channel_title,channel_id,expiry').eq('owner_id', ownerId).maybeSingle();
  return { configured: oauthConfigured(), connected: !!row, channel_title: row?.channel_title || '', channel_id: row?.channel_id || '' };
}
export async function disconnect(ownerId) { await supa.from('yt_oauth').delete().eq('owner_id', ownerId); return { ok: true }; }

// ── 게시(운영규칙 집행) ──────────────────────────────────────────
export async function postComment({ ownerId, videoId, text, profile = '유튜브1' }) {
  const s = await getSetting();
  const body = String(text || '').trim();
  if (!body) throw Object.assign(new Error('댓글 내용이 비었습니다.'), { status: 422 });
  if (body.length < s.min_chars || body.length > s.max_chars) throw Object.assign(new Error(`댓글은 ${s.min_chars}~${s.max_chars}자여야 합니다(현재 ${body.length}자).`), { status: 422 });
  if (/https?:\/\//.test(body) || /#[\p{L}\p{N}_]/u.test(body)) throw Object.assign(new Error('링크/해시태그는 금지입니다(과제 규칙 + 스팸 방지).'), { status: 422 });

  // 규칙 1: 영상당 1댓글
  const { count: dup } = await supa.from('yt_log').select('id', { count: 'exact', head: true }).eq('video_id', videoId).eq('success', true);
  if ((dup || 0) > 0) throw Object.assign(new Error('이 영상에는 이미 댓글을 달았습니다(영상당 1개).'), { status: 409 });
  // 규칙 2: 하루 상한
  const since = new Date(); since.setHours(0, 0, 0, 0);
  const { count: today } = await supa.from('yt_log').select('id', { count: 'exact', head: true }).eq('success', true).gte('created_at', since.toISOString());
  if ((today || 0) >= s.daily_max_comments) throw Object.assign(new Error(`오늘 게시 상한(${s.daily_max_comments}개)에 도달했습니다.`), { status: 429 });

  const { data: vid } = await supa.from('yt_video').select('title').eq('id', videoId).maybeSingle();
  const link = 'https://www.youtube.com/watch?v=' + videoId;
  const logBase = { video_id: videoId, video_title: vid?.title || '', video_link: link, profile, body, status: 'posting' };
  const { data: logRow } = await supa.from('yt_log').insert(logBase).select('id').single();

  try {
    const accessToken = await validAccessToken(ownerId);
    const r = await fetch(YT + '/commentThreads?part=snippet', { method: 'POST', headers: { authorization: 'Bearer ' + accessToken, 'content-type': 'application/json' }, body: JSON.stringify({ snippet: { videoId, topLevelComment: { snippet: { textOriginal: body } } } }) });
    const j = await r.json(); if (!r.ok) throw new Error(j?.error?.message || ('게시 실패 ' + r.status));
    const commentId = j?.id || j?.snippet?.topLevelComment?.id || '';
    const commentLink = commentId ? `${link}&lc=${commentId}` : link;
    await supa.from('yt_log').update({ status: 'posted', success: true, comment_id: commentId, comment_link: commentLink }).eq('id', logRow.id);
    return { ok: true, status: 'posted', comment_id: commentId, comment_link: commentLink, log_id: logRow.id };
  } catch (e) {
    await supa.from('yt_log').update({ status: 'failed', success: false, error: String(e?.message || e).slice(0, 500) }).eq('id', logRow.id);
    throw Object.assign(new Error('게시 실패: ' + (e?.message || e)), { status: e?.status || 502 });
  }
}

// ── 로그 / 설정 ─────────────────────────────────────────────────
export async function listLog({ limit = 100 } = {}) {
  const { data } = await supa.from('yt_log').select('*').order('created_at', { ascending: false }).limit(Math.min(+limit || 100, 500));
  return data || [];
}
export async function getSetting() {
  const { data } = await supa.from('yt_setting').select('*').eq('id', 1).maybeSingle();
  return data || { min_chars: 40, max_chars: 120, brand: '운명원', daily_max_comments: 10, provider: 'google', model: '', profiles: ['유튜브1'], landing: {}, persona: '', brand_open: false };
}
export async function updateSetting(patch) {
  const allow = ['min_chars', 'max_chars', 'brand', 'daily_max_comments', 'provider', 'model', 'profiles', 'landing', 'persona', 'brand_open'];
  const up = {}; for (const k of allow) if (patch[k] !== undefined) up[k] = patch[k];
  up.updated_at = new Date().toISOString();
  const { data } = await supa.from('yt_setting').update(up).eq('id', 1).select('*').single();
  return data;
}
export async function featureLog(id, featured) { await supa.from('yt_log').update({ featured: !!featured }).eq('id', id); return { ok: true }; }

// ── 공개 랜딩용: 랜딩노출(featured) 체크한 게시 댓글 ──
export async function featuredComments({ limit = 12 } = {}) {
  const { data } = await supa.from('yt_log').select('video_title,video_link,body,comment_link,created_at').eq('featured', true).eq('success', true).order('created_at', { ascending: false }).limit(Math.min(+limit || 12, 50));
  return data || [];
}

// ── 대시보드 통계(한눈에) ──
export async function stats(ownerId) {
  const head = { count: 'exact', head: true };
  const since = new Date(); since.setHours(0, 0, 0, 0);
  const [ex, po, fa, td, oa, recent] = await Promise.all([
    supa.from('yt_video').select('id', head).not('extracted_at', 'is', null),
    supa.from('yt_log').select('id', head).eq('success', true),
    supa.from('yt_log').select('id', head).eq('success', false),
    supa.from('yt_log').select('id', head).eq('success', true).gte('created_at', since.toISOString()),
    oauthStatus(ownerId),
    supa.from('yt_log').select('video_title,video_link,body,status,success,created_at,comment_link').order('created_at', { ascending: false }).limit(6),
  ]);
  const s = await getSetting();
  return {
    extracted: ex.count || 0, posted: po.count || 0, failed: fa.count || 0,
    today: td.count || 0, daily_max: s.daily_max_comments, brand: s.brand,
    connected: oa.connected, configured: oa.configured, channel: oa.channel_title,
    recent: recent.data || [],
  };
}

// ── 엑셀(CSV) 내보내기 — 영상 리스트(추출본) / 댓글 기록 ──
function csvEscape(v) { v = v == null ? '' : String(v); return /[",\n\r]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; }
function toCsv(headers, rows) { return [headers.join(','), ...rows.map((r) => r.map(csvEscape).join(','))].join('\r\n'); }
function ymd() { return new Date().toISOString().slice(0, 10); }
export async function exportCsv(kind) {
  if (kind === 'comments') {
    const { data } = await supa.from('yt_log').select('*').order('created_at', { ascending: false });
    const headers = ['작성일시', '영상제목', '영상링크', '프로필', '댓글', '상태', '성공', '댓글링크', '오류'];
    const rows = (data || []).map((l) => [l.created_at, l.video_title, l.video_link, l.profile, l.body, l.status, l.success ? '성공' : (l.success === false ? '실패' : ''), l.comment_link, l.error]);
    return { csv: toCsv(headers, rows), filename: `댓글데이터_${ymd()}.csv`, count: rows.length };
  }
  const { data } = await supa.from('yt_video').select('*').not('extracted_at', 'is', null).order('extracted_at', { ascending: false });
  const headers = ['영상ID', '제목', '채널', '조회수', '게시일', '고민한줄', '요약', '댓글초안', '분석방식', '추출일시'];
  const rows = (data || []).map((v) => { const a = v.analysis || {}; return [v.id, v.title, v.channel_title, v.view_count, v.published_at, a.worry_oneline, a.summary, a.comment, a.source === 'video' ? '영상분석' : '메타데이터', v.extracted_at]; });
  return { csv: toCsv(headers, rows), filename: `영상데이터_${ymd()}.csv`, count: rows.length };
}

// ── helpers ─────────────────────────────────────────────────────
async function getJson(url, label) {
  const r = await fetch(url);
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw Object.assign(new Error(j?.error?.message || `YouTube ${label} ${r.status}`), { status: r.status === 403 ? 412 : r.status });
  return j;
}
function parseJsonLoose(s) {
  if (!s) return null;
  const m = String(s).match(/\{[\s\S]*\}/);
  if (!m) return null;
  try { return JSON.parse(m[0]); } catch { return null; }
}
