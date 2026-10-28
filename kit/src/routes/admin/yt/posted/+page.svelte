<script>
  // 작성한 댓글 — 게시 기록 리스트 + 운영 설정(글자수·하루 상한).
  import { api } from '$lib/client.js';
  import { onMount } from 'svelte';

  let log = $state([]);
  let setting = $state({ min_chars: 40, max_chars: 120, brand: '운명원', daily_max_comments: 10, provider: 'google' });
  let err = $state(''); let notice = $state('');
  let channel = $state('');   // 연결된 유튜브 채널명(크롬 타이핑 행에 실제 계정명 표시용)
  let filter = $state('all'); // all | posted | failed | featured
  let visible = $state(20);   // 스크롤로 늘어나는 표시 개수(집계·필터는 전체 기준 유지)
  let sentinel = $state(null);
  const STEP = 20;
  function setFilter(f) { filter = f; visible = STEP; }

  const todayCount = $derived(log.filter((l) => l.success && isToday(l.created_at)).length);
  const okCount = $derived(log.filter((l) => l.success).length);
  const failCount = $derived(log.filter((l) => l.success === false).length);
  const featCount = $derived(log.filter((l) => l.featured).length);
  const shown = $derived(log.filter((l) =>
    filter === 'all' ? true : filter === 'posted' ? l.success : filter === 'failed' ? l.success === false : l.featured));
  const shownWindow = $derived(shown.slice(0, visible));

  function isToday(ts) { try { return new Date(ts).toDateString() === new Date().toDateString(); } catch { return false; } }
  function statusKo(s) { return { posted: '게시됨', failed: '실패', posting: '게시 중' }[s] || s; }
  function fmtDate(ts) { try { return new Date(ts).toLocaleString('ko-KR', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }); } catch { return ''; } }
  // '크롬 타이핑'은 게시 방식일 뿐 → 실제 게시 계정(채널)명으로 표시
  function profileName(p) { return p === '크롬 타이핑' ? (channel || '내 계정') : (p || '프로필 미상'); }

  onMount(() => {
    let io;
    (async () => {
      await Promise.all([loadLog(), loadSetting(), loadOauth()]);
      io = new IntersectionObserver((e) => { if (e[0]?.isIntersecting && visible < shown.length) visible += STEP; }, { rootMargin: '300px' });
      if (sentinel) io.observe(sentinel);
    })();
    return () => io?.disconnect();
  });
  async function loadLog() { try { log = await api('/yt/log?limit=500'); } catch (e) { /* */ } }
  async function loadSetting() { try { setting = { ...setting, ...(await api('/yt/settings')) }; } catch (e) { /* */ } }
  async function loadOauth() { try { const o = await api('/yt/oauth/status'); channel = o.channel_title || ''; } catch (e) { /* */ } }
  async function toggleFeature(l) { try { await api('/yt/feature', 'POST', { id: l.id, featured: !l.featured }); l.featured = !l.featured; log = [...log]; } catch (e) { err = e.message; } }
</script>

<svelte:head><title>작성한 댓글 — 댓글 에이전트</title></svelte:head>

<div class="ph">
  <div><h1>작성한 댓글</h1><p class="sub">본인 계정으로 게시한 댓글 기록이에요. 오늘 {todayCount}/{setting.daily_max_comments}건 · 영상당 1댓글</p></div>
</div>

{#if err}<p class="banner err">{err}</p>{/if}
{#if notice}<p class="banner ok">{notice}</p>{/if}

<div class="kpis">
  <button class="kpi" class:on={filter === 'all'} onclick={() => setFilter('all')}><b>{log.length}</b><span>전체</span></button>
  <button class="kpi" class:on={filter === 'posted'} onclick={() => setFilter('posted')}><b>{okCount}</b><span>게시됨</span></button>
  <button class="kpi" class:on={filter === 'failed'} onclick={() => setFilter('failed')}><b>{failCount}</b><span>실패</span></button>
  <button class="kpi" class:on={filter === 'featured'} onclick={() => setFilter('featured')}><b>{featCount}</b><span>랜딩노출</span></button>
</div>

<div class="logtable">
  {#if !shown.length}<p class="empty">{log.length ? '해당 조건의 기록이 없어요.' : '아직 게시한 댓글이 없어요.'}</p>{/if}
  {#each shownWindow as l (l.id)}
    <div class="logrow" class:fail={l.success === false}>
      <a class="lthumb" href={'https://www.youtube.com/watch?v=' + l.video_id} target="_blank" rel="noopener" title={l.video_title || l.video_id}>
        <img src={'https://i.ytimg.com/vi/' + l.video_id + '/mqdefault.jpg'} alt="" loading="lazy"
          onerror={(e) => e.currentTarget.parentElement.classList.add('noimg')}
          onload={(e) => { if (e.currentTarget.naturalWidth <= 120) e.currentTarget.parentElement.classList.add('noimg'); }} />
      </a>
      <div class="lbody">
        <div class="lhead">
          <span class="lstatus {l.success ? 'ok' : l.success === false ? 'bad' : ''}">{statusKo(l.status)}</span>
          <span class="lprofile" title="게시 계정"><i class="fi-rr-user"></i> {profileName(l.profile)}</span>
          <span class="ltitle">{l.video_title || l.video_id}</span>
          <span class="ldate">{fmtDate(l.created_at)}</span>
        </div>
        {#if l.success === false && l.error}
          <div class="errbox"><i class="fi-rr-cross-circle"></i> <span><b>게시 실패</b> · {l.error.replace(/^게시 실패:\s*/, '')}</span></div>
        {/if}
        <p class="ltext" class:dim={l.success === false}>{#if l.success === false}<span class="draftlbl">미게시 초안</span>{/if}{l.body}</p>
        {#if l.success}
          <div class="lfoot">
            <button class="feat" class:on={l.featured} onclick={() => toggleFeature(l)} aria-pressed={l.featured}>
              <i class="fi-rr-{l.featured ? 'check' : 'eye'}"></i> 랜딩 노출{l.featured ? ' 중' : ''}
            </button>
            {#if l.comment_link}<a class="viewlink" href={l.comment_link} target="_blank" rel="noopener">유튜브에서 보기 ↗</a>{/if}
          </div>
        {/if}
      </div>
    </div>
  {/each}
  {#if shownWindow.length < shown.length}<div bind:this={sentinel} class="scroll-sentinel"></div><p class="loadmore">더 불러오는 중…</p>{/if}
  {#if shown.length > STEP && shownWindow.length >= shown.length}<p class="loadmore end">모든 기록을 불러왔어요 ({shown.length}개)</p>{/if}
</div>

<style>
  .ph { display:flex; justify-content:space-between; align-items:flex-start; gap:12px; flex-wrap:wrap; }
  .ph h1 { margin:0; font-size:22px; } .sub { margin:4px 0 0; color:var(--muted); font-size:13px; }
  .banner { padding:10px 13px; border-radius:10px; font-size:13.5px; margin:12px 0 0; } .banner.err { background:#fde8e8; color:#b42318; } .banner.ok { background:#e4f5ec; color:#13794a; }

  .kpis { display:grid; grid-template-columns:repeat(4, 1fr); gap:12px; margin-top:16px; }
  @media(max-width:620px){ .kpis{ grid-template-columns:repeat(2,1fr); } }
  .kpi { background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:14px 16px; text-align:left; cursor:pointer; display:flex; flex-direction:column; gap:2px; }
  .kpi:hover { border-color:var(--accent); }
  .kpi.on { border-color:var(--accent); box-shadow:0 0 0 1px var(--accent) inset; }
  .kpi b { font-size:22px; font-weight:850; color:var(--ink); } .kpi span { font-size:12.5px; color:var(--muted); }

  .inp { padding:8px 10px; border:1px solid var(--line); border-radius:8px; background:var(--bg); color:var(--ink); font:inherit; font-size:13.5px; }

  .logtable { margin-top:16px; display:flex; flex-direction:column; gap:12px; }
  .empty { color:var(--muted); font-size:13px; text-align:center; padding:40px 0; } .empty a { color:var(--accent); }
  .scroll-sentinel { height:1px; }
  .loadmore { text-align:center; color:var(--muted); font-size:12.5px; padding:8px 0 2px; } .loadmore.end { padding:14px 0; }
  .logrow { display:flex; gap:14px; padding:16px 18px; border:1px solid var(--line); border-radius:12px; background:var(--surface); } .logrow.fail { border-color:#f3c0bb; }
  .lthumb { flex:none; align-self:center; height:108px; border-radius:9px; overflow:hidden; background:var(--line); display:block; line-height:0; }
  .lthumb img { height:100%; width:auto; display:block; transition:transform .35s ease; }
  .lthumb:hover img { transform:scale(1.06); }
  .lthumb.noimg { display:none; }
  .lbody { flex:1; min-width:0; }
  @media(max-width:620px){
    .logrow { flex-direction:column; align-items:stretch; gap:10px; }
    .lthumb { align-self:flex-start; height:auto; width:100%; max-width:100%; border-radius:8px; }
    .lthumb img { width:100%; height:auto; }
  }
  .lhead { display:flex; align-items:center; gap:10px; flex-wrap:wrap; }
  .lprofile { flex:none; display:inline-flex; align-items:center; gap:4px; font-size:11.5px; font-weight:700; color:var(--ink); background:var(--badge-bg); padding:3px 9px; border-radius:999px; }
  .lprofile i { font-size:11px; color:var(--muted); }
  .lstatus { font-size:11px; font-weight:700; padding:3px 9px; border-radius:999px; background:var(--badge-bg); color:var(--muted); flex:none; }
  .lstatus.ok { background:#e4f5ec; color:#13794a; } .lstatus.bad { background:#fde8e8; color:#b42318; }
  /* 다크 모드 — 밝은 배지가 어두운 배경에 묻혀 안 보이던 문제 해결(반투명 배경 + 밝은 글씨) */
  :global(html[data-appearance="dark"]) .lstatus { background:rgba(255,255,255,.08); color:#cdd3de; }
  :global(html[data-appearance="dark"]) .lstatus.ok { background:rgba(29,185,84,.22); color:#4ee08a; }
  :global(html[data-appearance="dark"]) .lstatus.bad { background:rgba(240,72,60,.22); color:#ff9a90; }
  .ltitle { flex:1; min-width:0; font-size:13px; color:var(--muted); font-weight:600; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .ldate { flex:none; font-size:12px; color:var(--muted); }
  .ltext { font-size:15px; line-height:1.8; margin:11px 0 0; max-width:820px; color:var(--ink); }
  .ltext.dim { color:var(--muted); font-size:14px; }
  .draftlbl { display:inline-block; font-size:11px; font-weight:700; color:var(--muted); background:var(--badge-bg); padding:1px 7px; border-radius:6px; margin-right:7px; vertical-align:middle; }
  .errbox { display:flex; align-items:center; gap:7px; margin-top:11px; padding:10px 13px; background:var(--danger-bg); color:var(--danger-fg); border-radius:9px; font-size:13.5px; line-height:1.5; }
  .errbox i { font-size:15px; flex:none; }
  .lfoot { display:flex; align-items:center; gap:16px; margin-top:12px; padding-top:11px; border-top:1px solid var(--line); }
  .feat { display:inline-flex; align-items:center; gap:6px; cursor:pointer; font-size:12.5px; font-weight:700; padding:6px 13px; border-radius:999px; border:1px solid var(--line); background:transparent; color:var(--muted); transition:background .12s, border-color .12s, color .12s; }
  .feat i { font-size:12px; }
  .feat:hover { border-color:#1db954; color:#1db954; }
  .feat.on { background:#1db954; border-color:#1db954; color:#fff; }
  .viewlink { font-size:13px; font-weight:600; color:var(--accent); }
</style>
