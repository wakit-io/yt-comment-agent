<script>
  // 상세 — 추출한 영상 내용 + 댓글 초안(편집) + 게시.
  import { api } from '$lib/client.js';
  import { onMount } from 'svelte';
  import { page } from '$app/state';

  const id = $derived(page.params.id);
  // 데모(로컬)에선 크롬 타이핑 시연이 주 액션 → 공식 API 게시 UI는 숨김. (배포/실제 게시 시 true로)
  const SHOW_API_POST = false;
  let video = $state(null);
  let logs = $state([]);
  let comment = $state('');
  let setting = $state({ min_chars: 40, max_chars: 120 });
  let oauth = $state({ connected: false, configured: false, channel_title: '' });
  let profile = $state('유튜브1');
  let err = $state(''); let saved = $state(false);
  let postStatus = $state(''); let postLink = $state('');
  let loading = $state(true);
  let confirming = $state(false); // 게시 전 확인 모달

  const analysis = $derived(video?.analysis || {});
  const count = $derived([...(comment || '')].length);
  const lenOk = $derived(count >= setting.min_chars && count <= setting.max_chars);
  const hasLink = $derived(/https?:\/\//.test(comment) || /#[\p{L}\p{N}_]/u.test(comment));
  const alreadyPosted = $derived(logs.some((l) => l.success));

  function fmtViews(n) { n = +n || 0; return n >= 10000 ? (n / 10000).toFixed(1) + '만' : n.toLocaleString(); }

  onMount(async () => {
    try {
      const [r, s, o] = await Promise.all([api('/yt/extracted/one?id=' + encodeURIComponent(id)), api('/yt/settings'), api('/yt/oauth/status').catch(() => ({}))]);
      video = r.video; logs = r.logs || []; comment = r.video?.analysis?.comment || '';
      setting = { ...setting, ...s }; profile = (s.profiles || ['유튜브1'])[0]; oauth = { ...oauth, ...o };
    } catch (e) { err = e.message; }
    loading = false;
  });

  async function saveComment() { saved = false; err = ''; try { await api('/yt/analysis', 'POST', { videoId: id, comment }); saved = true; setTimeout(() => saved = false, 2000); } catch (e) { err = e.message; } }
  let regen = $state(false);
  async function regenerate() {
    regen = true; err = ''; saved = false;
    try { const r = await api('/yt/regenerate', 'POST', { videoId: id }); comment = r.comment; }
    catch (e) { err = e.message; }
    regen = false;
  }
  // 게시는 공개로 나가는 되돌리기 어려운 행동 → 확인 모달을 거쳐야만 실제 insert.
  function askPost() { if (!lenOk || hasLink || alreadyPosted) return; err = ''; confirming = true; }
  async function doPost() {
    confirming = false;
    postStatus = 'posting'; postLink = ''; err = '';
    try {
      await saveComment();
      const r = await api('/yt/post', 'POST', { videoId: id, text: comment, profile });
      postStatus = 'posted'; postLink = r.comment_link;
      const rr = await api('/yt/extracted/one?id=' + encodeURIComponent(id)); logs = rr.logs || [];
    } catch (e) { postStatus = 'failed'; err = e.message; }
  }
  async function connect() { try { const { url } = await api('/yt/oauth/url'); window.location.href = url; } catch (e) { err = e.message; } }

  // ── Mode B: 크롬 타이핑 시연 모드 ──
  // 본인 계정 1개로, 전용 크롬 프로필을 띄워 댓글창에 한 글자씩 타이핑→게시. (다계정·탐지우회 없음)
  let typing = $state(null); // { status, step, stepLabel, error, screenshot, commentLink }
  let typingBusy = $derived(typing && typing.status === 'running');
  let pollTimer = null;
  const TYPE_STEPS = [
    { key: 'launching', label: '크롬 프로필 열기' },
    { key: 'navigating', label: '영상 열기' },
    { key: 'typing', label: '댓글 타이핑' },
    { key: 'posting', label: '게시' },
    { key: 'done', label: '완료' }
  ];
  function stepIndex(step) {
    if (step === 'login') return 1; // 로그인 필요 = 영상 열기 단계에서 감지(프로필 열기는 성공)
    const i = TYPE_STEPS.findIndex((s) => s.key === step);
    return i < 0 ? 0 : i;
  }
  async function startTyping() {
    if (!lenOk || hasLink || typingBusy) return;
    err = ''; typing = { status: 'running', step: 'launching', stepLabel: '크롬 프로필 여는 중…', error: '', screenshot: '', commentLink: '' };
    try {
      await saveComment();
      const { jobId } = await api('/yt/type-post', 'POST', { videoId: id, text: comment });
      pollTyping(jobId);
    } catch (e) { typing = { status: 'failed', step: 'failed', stepLabel: '실패', error: e.message, screenshot: '', commentLink: '' }; }
  }
  function pollTyping(jobId) {
    clearTimeout(pollTimer);
    const tick = async () => {
      try {
        const j = await api('/yt/type-status?jobId=' + encodeURIComponent(jobId));
        typing = j;
        if (j.status === 'running') pollTimer = setTimeout(tick, 1000);
        else if (j.status === 'done') { const rr = await api('/yt/extracted/one?id=' + encodeURIComponent(id)); logs = rr.logs || []; }
      } catch (e) { typing = { status: 'failed', step: 'failed', stepLabel: '실패', error: e.message, screenshot: '', commentLink: '' }; }
    };
    pollTimer = setTimeout(tick, 900);
  }
</script>

<svelte:window onbeforeunload={() => clearTimeout(pollTimer)} />

<svelte:head><title>{video?.title || '상세'} — 영상 선택</title></svelte:head>

<a class="back" href="/admin/yt/comments">← 영상 선택</a>

{#if loading}
  <p class="muted">불러오는 중…</p>
{:else if !video}
  <p class="banner err">{err || '영상을 찾을 수 없습니다.'}</p>
{:else}
  <div class="detail">
    <div class="left">
      <img class="thumb" src={video.thumb} alt="" />
      <h1>{video.title}</h1>
      <p class="vsub">{video.channel_title} · 조회 {fmtViews(video.view_count)}</p>
      <a class="btn sm" href={'https://www.youtube.com/watch?v=' + video.id} target="_blank" rel="noopener">유튜브에서 열기 ↗</a>

      <div class="sec">
        <div class="sech">영상 내용 {#if analysis.source}<span class="srcbadge" class:video={analysis.source === 'video'}><i class="fi-rr-{analysis.source === 'video' ? 'film' : 'document'}"></i> {analysis.source === 'video' ? '영상 분석' : '메타데이터'}</span>{/if}</div>
        {#if analysis.worry_oneline}<div class="worry"><i class="fi-rr-comment-dots"></i> {analysis.worry_oneline}</div>{/if}
        <p class="summary">{analysis.summary || '요약 없음'}</p>
      </div>
    </div>

    <div class="rightcol">
      <div class="sec">
        <div class="sech">댓글 초안 <span class="hint">(수정 가능)</span></div>
        <textarea bind:value={comment} rows="5"></textarea>
        <div class="meta">
          <span class:bad={!lenOk}>{count}자 ({setting.min_chars}~{setting.max_chars})</span>
          {#if hasLink}<span class="bad">· 링크/해시태그 금지</span>{/if}
          <button class="btn xs" onclick={regenerate} disabled={regen}><i class="fi-rr-refresh"></i> {regen ? '생성 중…' : '다시 생성'}</button>
          <button class="btn xs" onclick={saveComment} disabled={regen}>{saved ? '저장됨' : '초안 저장'}</button>
        </div>
        {#if regen}<p class="regenhint">AI가 다른 버전으로 새 초안을 쓰는 중… (몇 초)</p>{/if}
      </div>

      <div class="postarea">
        <!-- Mode B: 크롬 타이핑 시연 (로컬 데모) — 데모 주 액션(상단) -->
        <div class="demobox">
          <div class="demohd"><i class="fi-rr-browser"></i> 크롬 타이핑 시연 <span class="demotag">로컬 데모</span></div>
          <p class="demodesc">전용 크롬 프로필 창을 띄워 댓글창에 <b>한 글자씩 직접 타이핑</b>한 뒤 게시하는 모습을 보여줍니다. (본인 계정 1개 · 처음 1회 그 창에서 유튜브 로그인 필요)</p>
          <button class="btn primary demobtn" onclick={startTyping} disabled={!lenOk || hasLink || typingBusy}>
            <i class="fi-rr-keyboard"></i> {typingBusy ? '진행 중…' : '댓글 게시'}
          </button>
          {#if typing}
            <div class="steps">
              {#each TYPE_STEPS as s, i}
                {@const cur = stepIndex(typing.step)}
                {@const state = typing.status === 'failed' ? (i < cur ? 'done' : i === cur ? 'fail' : 'todo') : (i < cur || typing.status === 'done' ? 'done' : i === cur ? 'now' : 'todo')}
                <div class="stepitem {state}">
                  <span class="dot">{#if state === 'done'}<i class="fi-rr-check"></i>{:else if state === 'fail'}<i class="fi-rr-cross-small"></i>{:else if state === 'now'}<i class="fi-rr-spinner"></i>{:else}{i + 1}{/if}</span>
                  <span class="slabel">{s.label}</span>
                </div>
              {/each}
            </div>
            {#if typing.status === 'running'}<p class="demostat"><i class="fi-rr-info"></i> {typing.stepLabel}</p>{/if}
            {#if typing.status === 'done'}<div class="result ok"><i class="fi-rr-check"></i> 타이핑 게시 완료{#if typing.commentLink} · <a href={typing.commentLink} target="_blank" rel="noopener">영상에서 보기 ↗</a>{/if}</div>{/if}
            {#if typing.status === 'failed'}
              <div class="result bad">{typing.error || '실패'}</div>
              {#if typing.screenshot}<img class="shot" src={typing.screenshot} alt="실패 시점 화면" />{/if}
            {/if}
          {/if}
        </div>

        {#if err}<p class="banner err">{err}</p>{/if}

        <!-- 공식 API 게시(배포/실제 게시용). 데모에선 숨김(SHOW_API_POST=false). -->
        {#if SHOW_API_POST}
          {#if !oauth.connected}
            <p class="hint">게시하려면 YouTube 계정 연결이 필요해요.</p>
            {#if oauth.configured}<button class="btn primary" onclick={connect}>YouTube 계정 연결</button>{:else}<span class="pill warn">OAuth 미설정(.env)</span>{/if}
          {:else}
            <div class="pfield"><label for="pf">게시 프로필</label>
              <select id="pf" class="inp" bind:value={profile}>{#each (setting.profiles || ['유튜브1']) as p}<option value={p}>{p}</option>{/each}</select>
            </div>
            <button class="btn primary big" onclick={askPost} disabled={!lenOk || hasLink || postStatus === 'posting' || alreadyPosted}>
              {alreadyPosted ? '이미 게시됨 (영상당 1개)' : postStatus === 'posting' ? '게시 중…' : '댓글 게시'}
            </button>
            <p class="posthint"><i class="fi-rr-info"></i> 누르면 확인 후 <b>실제 유튜브에 공개 댓글</b>로 올라갑니다.</p>
          {/if}
          {#if postStatus === 'posted'}<div class="result ok"><i class="fi-rr-check"></i> 게시 완료 · <a href={postLink} target="_blank" rel="noopener">댓글 보기 ↗</a></div>{/if}
          {#if postStatus === 'failed'}<div class="result bad">게시 실패 — 아래 메시지 확인</div>{/if}
        {/if}
      </div>

      {#if logs.length}
        <div class="sec">
          <div class="sech">이 영상 기록</div>
          {#each logs as l}<div class="logrow"><span class="lstatus {l.success ? 'ok' : 'bad'}">{l.status}</span><span class="ltext">{l.body}</span>{#if l.comment_link}<a href={l.comment_link} target="_blank" rel="noopener">보기↗</a>{/if}</div>{/each}
        </div>
      {/if}
    </div>
  </div>

  {#if confirming}
    <div class="modal-back" role="presentation" onclick={() => confirming = false}>
      <div class="modal" role="dialog" aria-modal="true" aria-label="게시 확인" onclick={(e) => e.stopPropagation()}>
        <div class="mhead"><i class="fi-rr-triangle-warning"></i> 실제로 게시할까요?</div>
        <p class="mdesc">아래 댓글이 <b>내 계정(충청도 꾸꾸지니 등)</b>으로 <b>실제 유튜브에 공개</b>로 올라갑니다. 되돌리려면 유튜브에서 직접 삭제해야 해요.</p>
        <div class="mvid">
          <img src={video?.thumb} alt="" />
          <div><div class="mvtitle">{video?.title}</div><div class="mvsub">{video?.channel_title}</div></div>
        </div>
        <div class="mcomment">{comment}</div>
        <div class="mmeta">{count}자 · 프로필 {profile} · 링크/해시태그 없음 확인됨</div>
        <div class="mbtns">
          <button class="btn" onclick={() => confirming = false}>취소</button>
          <button class="btn primary" onclick={doPost}>네, 게시합니다</button>
        </div>
      </div>
    </div>
  {/if}
{/if}

<style>
  .back { display:inline-block; margin-bottom:14px; color:var(--muted); text-decoration:none; font-size:13px; } .back:hover { color:var(--accent); }
  .muted { color:var(--muted); } .banner { padding:10px 13px; border-radius:10px; font-size:13.5px; } .banner.err { background:#fde8e8; color:#b42318; margin-top:10px; }
  .detail { display:grid; grid-template-columns:1fr 1fr; gap:20px; } @media(max-width:860px){ .detail { grid-template-columns:1fr; } }
  .thumb { width:100%; border-radius:12px; aspect-ratio:16/9; object-fit:cover; background:var(--line); }
  h1 { font-size:19px; margin:14px 0 4px; line-height:1.35; } .vsub { color:var(--muted); font-size:13px; margin:0 0 10px; }
  .sec { background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:14px; margin-top:14px; }
  .sech { font-weight:800; font-size:13.5px; margin-bottom:10px; display:flex; align-items:center; gap:8px; } .hint { font-weight:500; color:var(--muted); font-size:12px; }
  .srcbadge { font-size:11px; font-weight:700; padding:2px 8px; border-radius:999px; background:var(--badge-bg); color:var(--muted); } .srcbadge.video { background:var(--accent); color:var(--accent-fg); }
  .worry { font-size:13px; background:var(--badge-bg); padding:8px 10px; border-radius:8px; margin-bottom:10px; }
  .summary { font-size:13.5px; line-height:1.7; margin:0; white-space:pre-wrap; }
  textarea { width:100%; box-sizing:border-box; padding:11px; border:1px solid var(--line); border-radius:9px; background:var(--bg); color:var(--ink); font:inherit; font-size:14px; line-height:1.6; resize:vertical; }
  .meta { font-size:12px; color:var(--muted); margin-top:8px; display:flex; align-items:center; gap:8px; flex-wrap:wrap; } .bad { color:#b42318; font-weight:700; }
  .meta .btn { display:inline-flex; align-items:center; gap:4px; }
  .regenhint { font-size:12px; color:var(--accent); margin:8px 0 0; }
  .postarea { margin-top:14px; display:flex; flex-direction:column; gap:10px; }
  .pfield label { font-size:12px; color:var(--muted); display:block; margin-bottom:4px; } .inp { padding:9px 11px; border:1px solid var(--line); border-radius:9px; background:var(--bg); color:var(--ink); font:inherit; font-size:13.5px; }
  .btn.big { padding:13px; font-size:14.5px; } .pill.warn { background:#fdf0d5; color:#8a5a00; padding:6px 10px; border-radius:999px; font-size:12px; font-weight:700; }
  .result { font-size:13.5px; padding:9px 11px; border-radius:8px; } .result.ok { background:#e4f5ec; color:#13794a; } .result.bad { background:#fde8e8; color:#b42318; } .result a { color:inherit; font-weight:700; }
  .logrow { display:flex; align-items:center; gap:10px; padding:8px 0; border-top:1px solid var(--line); font-size:13px; } .logrow:first-of-type { border-top:0; }
  .lstatus { font-size:11px; font-weight:700; padding:2px 8px; border-radius:999px; flex:none; } .lstatus.ok { background:#e4f5ec; color:#13794a; } .lstatus.bad { background:#fde8e8; color:#b42318; }
  .ltext { flex:1; min-width:0; } .logrow a { color:var(--accent); }
  .posthint { font-size:11.5px; color:var(--muted); margin:2px 0 0; display:flex; align-items:center; gap:5px; }
  /* Mode B 데모 박스 */
  .demobox { margin-top:4px; border:1px dashed var(--line); border-radius:12px; padding:13px; background:var(--surface); }
  .demohd { font-weight:800; font-size:13px; display:flex; align-items:center; gap:7px; }
  .demotag { font-size:10.5px; font-weight:700; padding:2px 7px; border-radius:999px; background:var(--badge-bg); color:var(--muted); }
  .demodesc { font-size:12px; color:var(--muted); line-height:1.6; margin:8px 0 10px; }
  .demobtn { width:100%; display:inline-flex; align-items:center; justify-content:center; gap:6px; padding:13px; font-size:14.5px; font-weight:800; }
  .steps { display:flex; align-items:center; gap:4px; margin-top:12px; flex-wrap:wrap; }
  .stepitem { display:flex; align-items:center; gap:5px; font-size:11.5px; color:var(--muted); }
  .stepitem:not(:last-child)::after { content:""; width:12px; height:1px; background:var(--line); }
  .stepitem .dot { width:20px; height:20px; border-radius:50%; background:var(--line); color:var(--muted); display:inline-flex; align-items:center; justify-content:center; font-size:10px; font-weight:700; flex:none; }
  .stepitem.now .dot { background:var(--accent); color:var(--accent-fg); }
  .stepitem.now .slabel { color:var(--ink); font-weight:700; }
  .stepitem.done .dot { background:#13794a; color:#fff; }
  .stepitem.fail .dot { background:#b42318; color:#fff; }
  .stepitem.fail .slabel { color:#b42318; font-weight:700; }
  .stepitem .fi-rr-spinner { animation:spin 1s linear infinite; }
  @keyframes spin { to { transform:rotate(360deg); } }
  .demostat { font-size:12px; color:var(--accent); margin:10px 0 0; display:flex; align-items:center; gap:5px; }
  .shot { width:100%; border-radius:8px; margin-top:8px; border:1px solid var(--line); }
  /* 게시 확인 모달 */
  .modal-back { position:fixed; inset:0; background:rgba(0,0,0,.6); display:flex; align-items:center; justify-content:center; padding:18px; z-index:50; backdrop-filter:blur(5px); -webkit-backdrop-filter:blur(5px); }
  .modal { background:var(--bg); border:1px solid var(--line); border-radius:16px; padding:20px; max-width:440px; width:100%; box-shadow:0 20px 60px rgba(0,0,0,.3); }
  .mhead { font-size:16px; font-weight:800; display:flex; align-items:center; gap:8px; color:#b4540a; }
  .mhead i { color:#e08a2b; }
  .mdesc { font-size:13px; line-height:1.6; color:var(--muted); margin:10px 0 14px; }
  .mvid { display:flex; gap:10px; align-items:center; background:var(--surface); border:1px solid var(--line); border-radius:10px; padding:8px; }
  .mvid img { width:72px; height:40px; border-radius:6px; object-fit:cover; flex:none; background:var(--line); }
  .mvtitle { font-size:13px; font-weight:700; line-height:1.3; display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
  .mvsub { font-size:12px; color:var(--muted); margin-top:2px; }
  .mcomment { margin-top:12px; font-size:13.5px; line-height:1.65; background:var(--surface); border:1px solid var(--line); border-radius:10px; padding:11px; white-space:pre-wrap; }
  .mmeta { font-size:11.5px; color:var(--muted); margin-top:8px; }
  .mbtns { display:flex; justify-content:flex-end; gap:8px; margin-top:16px; }
</style>
