<script>
  // 영상 선택 — 추출된 영상 리스트. 썸네일/제목=상세, 댓글영역=빠른 모달(보기·다시생성·바로게시).
  import { api } from '$lib/client.js';
  import { onMount, untrack } from 'svelte';

  let allItems = $state([]);    // 추출된 영상 전체(클라이언트 필터/정렬)
  let log = $state([]);
  let setting = $state({ min_chars: 40, max_chars: 120, brand: '운명원', daily_max_comments: 10, provider: 'google', profiles: ['유튜브1'] });
  let err = $state('');

  const todayCount = $derived(log.filter((l) => l.success && isToday(l.created_at)).length);
  function isToday(ts) { try { return new Date(ts).toDateString() === new Date().toDateString(); } catch { return false; } }
  function fmtViews(n) { n = +n || 0; return n >= 10000 ? (n / 10000).toFixed(1) + '만' : n.toLocaleString(); }

  // ── 필터/정렬(모달) ──
  let filterOpen = $state(false);
  let query = $state('');
  let dateRange = $state('all');  // all | today | yesterday | 7d | 30d
  let statusF = $state('all');    // all | posted | unposted
  let sortBy = $state('recent');  // recent | oldest | views
  const activeFilterCount = $derived((dateRange !== 'all' ? 1 : 0) + (statusF !== 'all' ? 1 : 0) + (sortBy !== 'recent' ? 1 : 0) + (query.trim() ? 1 : 0));
  function startOfDay(d) { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
  function inRange(ts) {
    if (dateRange === 'all') return true;
    if (!ts) return false;
    const t = new Date(ts); const today0 = startOfDay(new Date());
    if (dateRange === 'today') return t >= today0;
    if (dateRange === 'yesterday') { const y0 = new Date(today0); y0.setDate(y0.getDate() - 1); return t >= y0 && t < today0; }
    if (dateRange === '7d') { const d = new Date(today0); d.setDate(d.getDate() - 6); return t >= d; }
    if (dateRange === '30d') { const d = new Date(today0); d.setDate(d.getDate() - 29); return t >= d; }
    return true;
  }
  const filtered = $derived.by(() => {
    const q = query.trim().toLowerCase();
    let arr = allItems.filter((v) => {
      if (q && !(v.title || '').toLowerCase().includes(q)) return false;
      if (statusF === 'posted' && !v.posted) return false;
      if (statusF === 'unposted' && v.posted) return false;
      if (!inRange(v.extracted_at)) return false;
      return true;
    });
    if (sortBy === 'oldest') arr = [...arr].sort((a, b) => new Date(a.extracted_at) - new Date(b.extracted_at));
    else if (sortBy === 'views') arr = [...arr].sort((a, b) => (b.view_count || 0) - (a.view_count || 0));
    else arr = [...arr].sort((a, b) => new Date(b.extracted_at) - new Date(a.extracted_at));
    return arr;
  });

  function resetFilter() { query = ''; dateRange = 'all'; statusF = 'all'; sortBy = 'recent'; visible = STEP; }
  function applyFilter() { filterOpen = false; visible = STEP; }

  // ── 윈도잉 스크롤(필터 결과 기준) ──
  const STEP = 24;
  let visible = $state(STEP);
  let booting = $state(true);
  let sentinel = $state(null);
  const items = $derived(filtered.slice(0, visible));

  onMount(() => {
    let io;
    (async () => {
      await Promise.all([loadLog(), loadSetting(), loadAll()]);
      booting = false;
      io = new IntersectionObserver((e) => { if (e[0]?.isIntersecting && visible < filtered.length) visible += STEP; }, { rootMargin: '300px' });
      if (sentinel) io.observe(sentinel);
    })();
    return () => io?.disconnect();
  });
  async function loadLog() { try { log = await api('/yt/log'); } catch (e) { /* */ } }
  async function loadSetting() { try { setting = { ...setting, ...(await api('/yt/settings')) }; } catch (e) { /* */ } }
  async function loadAll() { try { allItems = await api('/yt/extracted?limit=300&offset=0'); } catch (e) { /* */ } }

  // ── 다중 선택 + 순차 일괄 타이핑 게시 ──
  const MAX_SELECT = 10;        // 스팸 감지 방지 — 한 번에 최대 10개
  const BATCH_GAP = 3000;       // 게시 간 간격(ms)
  let selected = $state(new Set());
  let limitMsg = $state('');
  const atLimit = $derived(selected.size >= MAX_SELECT);
  function flashLimit() { limitMsg = `한 번에 최대 ${MAX_SELECT}개까지 선택할 수 있어요 (유튜브 스팸 감지 방지).`; clearTimeout(flashLimit._t); flashLimit._t = setTimeout(() => limitMsg = '', 3500); }
  function toggleSel(id) {
    const s = new Set(selected);
    if (s.has(id)) { s.delete(id); limitMsg = ''; }
    else { if (s.size >= MAX_SELECT) { flashLimit(); return; } s.add(id); }
    selected = s;
  }
  function selectAll() {
    // 현재 필터/정렬 결과에서 앞에서부터 — 이미 게시된 영상은 제외(영상당 1댓글)
    const ids = filtered.filter((v) => !v.posted).map((v) => v.id);
    selected = new Set(ids.slice(0, MAX_SELECT));
    if (ids.length > MAX_SELECT) flashLimit();
  }
  function clearSel() { selected = new Set(); limitMsg = ''; }

  let batchOpen = $state(false); let batchRunning = $state(false);
  let batchResults = $state([]); let batchIdx = $state(0); let batchStep = $state('');
  const batchTotal = $derived(batchResults.length);
  const batchDone = $derived(batchResults.filter((r) => r.status === 'done').length);
  const batchFail = $derived(batchResults.filter((r) => r.status === 'failed' || r.status === 'skipped').length);
  const batchPct = $derived(batchTotal ? Math.round((batchDone + batchFail) / batchTotal * 100) : 0);

  function startBatch() {
    const queue = [...selected].map((id) => allItems.find((v) => v.id === id)).filter((v) => v && !v.posted);
    if (!queue.length || batchRunning) return;
    batchOpen = true;
    runBatch(queue);
  }
  async function runBatch(queue) {
    batchRunning = true; batchIdx = 0; batchStep = '시작하는 중…';
    batchResults = queue.map((v) => ({ id: v.id, title: v.title, status: 'pending' }));
    for (let i = 0; i < queue.length; i++) {
      const v = queue[i]; batchIdx = i;
      batchResults[i].status = 'running'; batchResults = [...batchResults];
      const text = v.analysis?.comment || '';
      if (!text) { batchResults[i].status = 'skipped'; batchResults = [...batchResults]; continue; }
      try {
        const { jobId } = await api('/yt/type-post', 'POST', { videoId: v.id, text });
        const ok = await pollJob(jobId, (l) => { batchStep = l; });
        if (ok) { batchResults[i].status = 'done'; const it = allItems.find((x) => x.id === v.id); if (it) it.posted = true; allItems = [...allItems]; }
        else { batchResults[i].status = 'failed'; }
      } catch (e) { batchResults[i].status = 'failed'; batchResults[i].error = e.message; }
      batchResults = [...batchResults];
      if (i < queue.length - 1) { batchStep = `다음 영상까지 잠시 대기 중… (${Math.round(BATCH_GAP / 1000)}초)`; await new Promise((r) => setTimeout(r, BATCH_GAP)); }
    }
    batchStep = '완료'; batchRunning = false;
    await loadLog(); clearSel();
  }
  function pollJob(jobId, onStep) {
    return new Promise((resolve) => {
      const tick = async () => {
        try {
          const j = await api('/yt/type-status?jobId=' + encodeURIComponent(jobId));
          if (j.stepLabel) onStep(j.stepLabel);
          if (j.status === 'done') return resolve(true);
          if (j.status === 'failed') { onStep(j.error || '실패'); return resolve(false); }
          setTimeout(tick, 1000);
        } catch (e) { resolve(false); }
      };
      setTimeout(tick, 900);
    });
  }
  function closeBatch() { if (batchRunning) return; batchOpen = false; batchResults = []; batchIdx = 0; batchStep = ''; }

  // ── 빠른 모달(댓글 보기·다시생성·바로게시) ──
  let qv = $state(null);        // 선택된 영상
  let qcomment = $state('');
  let qregen = $state(false); let qsaving = $state(false); let qsaved = $state(false);
  let qerr = $state('');
  const qcount = $derived([...(qcomment || '')].length);
  const qlenOk = $derived(qcount >= setting.min_chars && qcount <= setting.max_chars);
  const qhasLink = $derived(/https?:\/\//.test(qcomment) || /#[\p{L}\p{N}_]/u.test(qcomment));

  function openQuick(v) { qv = v; qcomment = v.analysis?.comment || ''; qerr = ''; qsaved = false; }
  function closeQuick() { qv = null; }
  // 모달에서 초안 편집/재생성 시 목록 카드 미리보기에 즉시 반영(저장과 별개의 화면 동기화)
  $effect(() => {
    const c = qcomment; const v = qv;
    if (!v) return;
    untrack(() => {
      const it = allItems.find((x) => x.id === v.id);
      if (it && (it.analysis?.comment || '') !== c) { it.analysis = { ...(it.analysis || {}), comment: c }; allItems = [...allItems]; }
    });
  });
  async function qRegen() {
    qregen = true; qerr = ''; qsaved = false;
    try { const r = await api('/yt/regenerate', 'POST', { videoId: qv.id }); qcomment = r.comment; } catch (e) { qerr = e.message; }
    qregen = false;
  }
  // 저장 = 이 내용을 해당 영상의 지정 댓글로 저장(일괄 타이핑 게시에 사용)
  async function qSaveClick() {
    if (qsaving) return; qsaving = true; qerr = '';
    try {
      await api('/yt/analysis', 'POST', { videoId: qv.id, comment: qcomment });
      const it = allItems.find((x) => x.id === qv.id);
      if (it) { it.analysis = { ...(it.analysis || {}), comment: qcomment }; allItems = [...allItems]; }
      if (qv.analysis) qv.analysis.comment = qcomment; else qv.analysis = { comment: qcomment };
      qsaved = true; setTimeout(() => qsaved = false, 2000);
    } catch (e) { qerr = e.message; }
    qsaving = false;
  }
</script>

<svelte:head><title>영상 선택 — 댓글 에이전트</title></svelte:head>

<div class="ph">
  <div><h1>영상 선택</h1><p class="sub">영상을 고르고 댓글을 바로 확인·게시하세요. 오늘 {todayCount}/{setting.daily_max_comments}건</p></div>
  <button class="fbtn" class:on={activeFilterCount > 0} onclick={() => filterOpen = true} title="기간·상태·정렬 필터">
    <i class="fi-rr-settings-sliders"></i> 필터{#if activeFilterCount > 0}<span class="fcount">{activeFilterCount}</span>{/if}
  </button>
</div>

{#if err}<p class="banner err">{err}</p>{/if}

<section class="block">
  <h3>추출된 영상 ({filtered.length}{#if activeFilterCount > 0} / 전체 {allItems.length}{/if})</h3>

  {#if selected.size > 0}
    <div class="selbar">
      <span class="selcount"><i class="fi-rr-check"></i> {selected.size}/{MAX_SELECT}개 선택{#if atLimit} <em class="selmax">· 최대</em>{/if}</span>
      <div class="selactions">
        <button class="btn xs" onclick={selectAll} disabled={batchRunning || atLimit}>전체 선택</button>
        <button class="btn xs" onclick={clearSel} disabled={batchRunning}>선택 해제</button>
        <button class="btn primary sm" onclick={startBatch} disabled={batchRunning}><i class="fi-rr-keyboard"></i> 선택한 {selected.size}개 순서대로 타이핑 게시</button>
      </div>
    </div>
  {/if}
  {#if limitMsg}<p class="limitmsg"><i class="fi-rr-info"></i> {limitMsg}</p>{/if}

  <div class="grid">
    {#each items as v (v.id)}
      <div class="card" class:done={v.posted} class:sel={selected.has(v.id)}>
        {#if !v.posted}
          <button class="selbox" class:on={selected.has(v.id)} class:lock={atLimit && !selected.has(v.id)} onclick={() => toggleSel(v.id)} aria-label="선택" title={atLimit && !selected.has(v.id) ? `최대 ${MAX_SELECT}개까지 선택 가능` : '선택'}>
            {#if selected.has(v.id)}<i class="fi-rr-check"></i>{:else if atLimit}<i class="fi-rr-lock"></i>{/if}
          </button>
        {/if}
        <a class="clink" href={'/admin/yt/comments/' + v.id} title="상세에서 편집">
          <div class="thumb"><img src={v.thumb} alt="" loading="lazy" />{#if v.posted}<span class="posted"><i class="fi-rr-check"></i> 게시됨</span>{/if}</div>
          <div class="meta">
            <div class="title">{v.title}</div>
            <div class="sub2">{v.channel_title} · 조회 {fmtViews(v.view_count)}</div>
          </div>
        </a>
        <button class="cmtprev" onclick={() => openQuick(v)}>
          <div class="cmtlabel"><i class="fi-rr-comment-dots"></i> 댓글 초안 <span class="cmtcta">댓글초안 자세히보기 →</span></div>
          <div class="cmttext">{v.analysis?.comment || v.analysis?.worry_oneline || '내용 없음'}</div>
        </button>
      </div>
    {/each}
    {#if !items.length && !booting}
      {#if allItems.length}<p class="empty">필터 조건에 맞는 영상이 없어요. <button class="linkbtn" onclick={resetFilter}>필터 초기화</button></p>
      {:else}<p class="empty">아직 추출된 영상이 없어요. <a href="/admin/yt">영상 불러오기</a>에서 "내용 추출"을 먼저 하세요.</p>{/if}
    {/if}
  </div>
  <div class="sentinel" bind:this={sentinel}></div>
  {#if items.length < filtered.length}<p class="loadmore">더 불러오는 중…</p>{/if}
  {#if filtered.length > STEP && items.length >= filtered.length && !booting}<p class="loadmore end">모든 영상을 불러왔어요 ({filtered.length}개)</p>{/if}
</section>

<p class="postedlink"><a href="/admin/yt/posted"><i class="fi-rr-comment-dots"></i> 작성한 댓글 기록 보기 →</a></p>

{#if filterOpen}
  <div class="qback" role="presentation" onclick={() => filterOpen = false}>
    <div class="filtermodal" role="dialog" aria-modal="true" aria-label="영상 필터" onclick={(e) => e.stopPropagation()}>
      <div class="fmhead"><span class="fmtitle"><i class="fi-rr-settings-sliders"></i> 필터 · 정렬</span><button class="fmclose" onclick={() => filterOpen = false} aria-label="닫기" title="닫기"><i class="fi-rr-cross-small"></i></button></div>

      <div class="fprow">
        <span class="flabel">제목 검색</span>
        <input class="finput" bind:value={query} placeholder="영상 제목으로 검색" />
      </div>

      <div class="fprow">
        <span class="flabel">추출 기간</span>
        <div class="fchips">
          {#each [['all','전체'],['today','오늘'],['yesterday','어제'],['7d','최근 7일'],['30d','최근 30일']] as [v, label]}
            <button class="fchip" class:on={dateRange === v} onclick={() => dateRange = v}>{label}</button>
          {/each}
        </div>
      </div>

      <div class="fprow">
        <span class="flabel">게시 상태</span>
        <div class="fchips">
          {#each [['all','전체'],['posted','게시됨'],['unposted','미게시']] as [v, label]}
            <button class="fchip" class:on={statusF === v} onclick={() => statusF = v}>{label}</button>
          {/each}
        </div>
      </div>

      <div class="fprow">
        <span class="flabel">정렬</span>
        <div class="fchips">
          {#each [['recent','최신 추출순'],['oldest','오래된순'],['views','조회수 높은순']] as [v, label]}
            <button class="fchip" class:on={sortBy === v} onclick={() => sortBy = v}>{label}</button>
          {/each}
        </div>
      </div>

      <div class="fpbtns">
        <button class="btn" onclick={resetFilter} disabled={activeFilterCount === 0}>초기화</button>
        <button class="btn primary" onclick={applyFilter}>적용 ({filtered.length})</button>
      </div>
    </div>
  </div>
{/if}

{#if batchOpen}
  <div class="qback" role="presentation">
    <div class="batchmodal" role="dialog" aria-modal="true">
      <div class="fmhead"><span class="fmtitle"><i class="fi-rr-keyboard"></i> 순서대로 타이핑 게시</span>{#if !batchRunning}<button class="fmclose" onclick={closeBatch} aria-label="닫기" title="닫기"><i class="fi-rr-cross-small"></i></button>{/if}</div>
      <div class="bprog">
        <div class="bprogtop"><span>{batchDone + batchFail}/{batchTotal} 진행</span><span>{batchPct}%</span></div>
        <div class="bbar"><div class="bfill" style="width:{batchPct}%"></div></div>
      </div>
      {#if batchRunning}<p class="bstep"><span class="spin"></span> {batchStep}</p>{/if}
      <div class="blist">
        {#each batchResults as r, i}
          <div class="brow {r.status}">
            <span class="bstat">
              {#if r.status === 'done'}<i class="fi-rr-check"></i>
              {:else if r.status === 'failed'}<i class="fi-rr-cross-small"></i>
              {:else if r.status === 'skipped'}<i class="fi-rr-ban"></i>
              {:else if r.status === 'running'}<span class="spin sm"></span>
              {:else}{i + 1}{/if}
            </span>
            <span class="btitle2">{r.title}</span>
          </div>
        {/each}
      </div>
      {#if !batchRunning}
        <div class="fpbtns">
          <span class="bsummary">완료 {batchDone} · 실패/건너뜀 {batchFail}</span>
          <button class="btn primary" onclick={closeBatch}>닫기</button>
        </div>
      {:else}
        <p class="bnote"><i class="fi-rr-info"></i> 크롬 창이 순서대로 열려 댓글을 타이핑합니다. 완료까지 창을 닫지 마세요.</p>
      {/if}
    </div>
  </div>
{/if}

{#if qv}
  <div class="qback" role="presentation" onclick={closeQuick}>
    <div class="qmodal" role="dialog" aria-modal="true" onclick={(e) => e.stopPropagation()}>
      <div class="qhead">
        <div class="qtitle">{qv.title}</div>
        <button class="qx" onclick={closeQuick} aria-label="닫기"><i class="fi-rr-cross-small"></i></button>
      </div>
      <div class="qsub">{qv.channel_title} · 조회 {fmtViews(qv.view_count)}</div>

      <label class="qlbl" for="qc">댓글 초안 <em>(수정 가능)</em></label>
      <textarea id="qc" bind:value={qcomment} rows="4"></textarea>
      <div class="qmeta">
        <span class:bad={!qlenOk}>{qcount}자 ({setting.min_chars}~{setting.max_chars})</span>
        {#if qhasLink}<span class="bad">· 링크/해시태그 금지</span>{/if}
        {#if qsaved}<span class="qsavedlbl"><i class="fi-rr-check"></i> 저장됨</span>{/if}
      </div>
      {#if qerr}<p class="qerr">{qerr}</p>{/if}
      <p class="qhint"><i class="fi-rr-info"></i> <span>저장하면 이 내용이 <b>해당 영상의 지정 댓글</b>로 저장돼, 「순서대로 타이핑 게시」에 그대로 사용됩니다.</span></p>
      <div class="qbtns">
        <button class="btn sm" onclick={qRegen} disabled={qregen || qsaving}><i class="fi-rr-refresh"></i> {qregen ? '생성 중…' : '다시 생성'}</button>
        <div class="qsp"></div>
        <button class="btn primary" onclick={qSaveClick} disabled={qsaving || qregen}>{qsaving ? '저장 중…' : '댓글 저장'}</button>
      </div>
    </div>
  </div>
{/if}

<style>
  .ph { display:flex; justify-content:space-between; align-items:flex-start; gap:12px; flex-wrap:wrap; }
  .ph h1 { margin:0; font-size:22px; } .sub { margin:4px 0 0; color:var(--muted); font-size:13px; }
  .fbtn { display:inline-flex; align-items:center; gap:6px; border:1px solid var(--line); background:var(--surface); color:var(--muted); border-radius:9px; padding:9px 14px; font-size:13.5px; font-weight:700; cursor:pointer; white-space:nowrap; }
  .fbtn:hover { border-color:var(--accent); color:var(--accent); }
  .fbtn.on { border-color:var(--accent); color:var(--accent); }
  .fcount { display:inline-flex; align-items:center; justify-content:center; min-width:17px; height:17px; padding:0 4px; border-radius:999px; background:var(--accent); color:var(--accent-fg); font-size:11px; font-weight:800; }
  .linkbtn { background:none; border:0; color:var(--accent); font:inherit; font-weight:700; cursor:pointer; padding:0; }
  .banner { padding:10px 13px; border-radius:10px; font-size:13.5px; margin:12px 0 0; } .banner.err { background:#fde8e8; color:#b42318; }

  .block { margin-top:20px; }
  .block h3 { margin:0 0 14px; font-size:16px; }
  .grid { display:grid; grid-template-columns:repeat(3, 1fr); gap:18px; }
  @media(max-width:900px){ .grid{ grid-template-columns:repeat(2, 1fr); } }
  @media(max-width:560px){ .grid{ grid-template-columns:1fr; } }
  .card { position:relative; display:flex; flex-direction:column; border:1px solid var(--line); border-radius:12px; overflow:hidden; background:var(--surface); padding:0; transition:background .12s; }
  .card:hover { background:var(--surface-alt); }
  .card.done { opacity:.92; }
  .card.sel { border-color:var(--accent); box-shadow:0 0 0 2px var(--accent) inset; }
  .selbox { position:absolute; top:8px; left:8px; z-index:4; width:24px; height:24px; border-radius:7px; border:1.5px solid #fff; background:rgba(0,0,0,.45); cursor:pointer; display:flex; align-items:center; justify-content:center; color:#fff; padding:0; opacity:0; transition:opacity .12s; box-shadow:0 1px 4px rgba(0,0,0,.3); }
  .card:hover .selbox, .selbox.on, .selbox:focus-visible { opacity:1; }
  .selbox.on { background:var(--accent); border-color:var(--accent); color:var(--accent-fg); }
  .selbox.lock { background:rgba(0,0,0,.55); border-color:rgba(255,255,255,.5); cursor:not-allowed; }
  .selbox i { font-size:13px; }
  .selbar { display:flex; align-items:center; justify-content:space-between; gap:10px; flex-wrap:wrap; margin:0 0 14px; padding:10px 14px; background:var(--badge-bg); border:1px solid var(--line); border-radius:11px; }
  .selcount { font-size:13px; font-weight:800; color:var(--accent); display:inline-flex; align-items:center; gap:6px; }
  .selmax { font-style:normal; font-weight:700; color:var(--muted); }
  .selactions { display:flex; gap:8px; flex-wrap:wrap; } .selactions .btn :global(i) { font-size:13px; margin-right:3px; }
  .limitmsg { display:flex; align-items:center; gap:6px; margin:0 0 14px; font-size:12.5px; color:#b9770b; background:#fff4e0; border:1px solid #f3d9a6; padding:8px 12px; border-radius:9px; }
  .clink { display:block; text-decoration:none; color:inherit; }
  .thumb { position:relative; } .thumb img { width:100%; aspect-ratio:16/9; object-fit:cover; background:var(--line); display:block; transition:transform .35s ease; }
  .card:hover .thumb img { transform:scale(1.06); }
  .posted { position:absolute; top:8px; left:8px; background:#13794a; color:#fff; font-size:11px; font-weight:700; padding:3px 8px; border-radius:999px; }
  .meta { padding:12px 14px 12px; } .title { font-size:15px; font-weight:700; line-height:1.4; display:-webkit-box; -webkit-line-clamp:2; line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
  .sub2 { font-size:12.5px; color:var(--muted); margin-top:5px; }
  /* 댓글 미리보기: 중첩 박스 대신 카드 하단 플랫 영역(구분선 하나) */
  .cmtprev { margin:0; padding:12px 14px 14px; border:0; border-top:1px solid var(--line); background:transparent; cursor:pointer; text-align:left; display:block; width:100%; transition:background .12s; }
  .cmtprev:hover { background:var(--surface-alt); }
  .cmtlabel { font-size:11.5px; font-weight:700; color:var(--muted); display:flex; align-items:center; gap:5px; margin-bottom:6px; }
  .cmtcta { margin-left:auto; color:var(--accent); font-weight:700; }
  .cmttext { font-size:13px; line-height:1.55; color:var(--ink); display:-webkit-box; -webkit-line-clamp:2; line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
  .empty { color:var(--muted); font-size:13px; text-align:center; padding:28px 0; grid-column:1/-1; } .empty a { color:var(--accent); }
  .sentinel { height:1px; }
  .loadmore { text-align:center; color:var(--muted); font-size:12.5px; padding:16px 0 0; } .loadmore.end { opacity:.7; }
  .postedlink { margin-top:16px; text-align:center; } .postedlink a { color:var(--accent); font-weight:700; font-size:14px; display:inline-flex; align-items:center; gap:7px; }

  /* 빠른 모달 */
  .qback { position:fixed; inset:0; background:rgba(0,0,0,.6); backdrop-filter:blur(5px); -webkit-backdrop-filter:blur(5px); display:flex; align-items:center; justify-content:center; padding:18px; z-index:80; }
  .qmodal { background:var(--surface); border:1px solid var(--line); border-radius:16px; padding:20px; max-width:480px; width:100%; box-shadow:0 24px 70px rgba(0,0,0,.5); }
  .qhead { display:flex; align-items:flex-start; gap:10px; }
  .qtitle { flex:1; font-size:15.5px; font-weight:800; line-height:1.4; display:-webkit-box; -webkit-line-clamp:2; line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
  .qx { flex:none; background:none; border:0; color:var(--muted); font-size:18px; cursor:pointer; padding:2px; }
  .qsub { font-size:12.5px; color:var(--muted); margin-top:3px; }
  .qlbl { display:block; font-size:12.5px; font-weight:700; margin:16px 0 7px; } .qlbl em { font-style:normal; font-weight:500; color:var(--muted); font-size:11.5px; }
  textarea { width:100%; box-sizing:border-box; padding:11px; border:1px solid var(--line); border-radius:9px; background:var(--bg); color:var(--ink); font:inherit; font-size:14px; line-height:1.7; resize:vertical; }
  .qmeta { font-size:12px; color:var(--muted); margin-top:8px; display:flex; align-items:center; gap:8px; } .bad { color:#d9534f; font-weight:700; }
  .qsavedlbl { margin-left:auto; color:#13794a; font-weight:700; display:inline-flex; align-items:center; gap:4px; } .qsavedlbl :global(i) { font-size:12px; }
  .qerr { font-size:13px; color:#d9534f; margin:10px 0 0; }
  .qhint { font-size:11.5px; color:var(--muted); margin:10px 0 0; display:flex; align-items:flex-start; gap:6px; background:var(--badge-bg); padding:8px 10px; border-radius:8px; line-height:1.55; }
  .qhint i { flex:none; margin-top:1px; }
  .qbtns { display:flex; align-items:center; gap:8px; margin-top:16px; } .qsp { flex:1; }
  .btn.primary :global(i), .btn :global(i) { font-size:13px; }

  /* 필터 모달 */
  .filtermodal { background:var(--surface); border:1px solid var(--line); border-radius:16px; padding:20px; width:400px; max-width:100%; box-shadow:0 24px 70px rgba(0,0,0,.5); display:flex; flex-direction:column; gap:15px; }
  .fmhead { font-size:16px; font-weight:800; display:flex; align-items:center; justify-content:space-between; gap:8px; }
  .fmtitle { display:inline-flex; align-items:center; gap:8px; } .fmtitle i { color:var(--accent); }
  .fmclose { flex:none; width:30px; height:30px; border:0; background:transparent; color:var(--muted); border-radius:8px; cursor:pointer; display:flex; align-items:center; justify-content:center; font-size:18px; }
  .fmclose:hover { background:var(--badge-bg); color:var(--ink); }
  .fprow { display:flex; flex-direction:column; gap:8px; }
  .flabel { font-size:12.5px; font-weight:700; color:var(--muted); }
  .finput { padding:10px 12px; border:1px solid var(--line); border-radius:9px; background:var(--bg); color:var(--ink); font:inherit; font-size:14px; }
  .fchips { display:flex; flex-wrap:wrap; gap:7px; }
  .fchip { border:1px solid var(--line); background:var(--bg); color:var(--muted); border-radius:999px; padding:7px 13px; font-size:12.5px; font-weight:700; cursor:pointer; }
  .fchip:hover { border-color:var(--accent); }
  .fchip.on { background:var(--accent); border-color:var(--accent); color:var(--accent-fg); }
  .fpbtns { display:flex; justify-content:flex-end; align-items:center; gap:8px; margin-top:4px; border-top:1px solid var(--line); padding-top:15px; }

  /* 일괄 타이핑 진행 모달 */
  .batchmodal { background:var(--surface); border:1px solid var(--line); border-radius:16px; padding:20px; width:440px; max-width:100%; box-shadow:0 24px 70px rgba(0,0,0,.5); display:flex; flex-direction:column; gap:14px; }
  .bprog { display:flex; flex-direction:column; gap:7px; }
  .bprogtop { display:flex; justify-content:space-between; font-size:12.5px; font-weight:700; color:var(--muted); }
  .bbar { height:8px; border-radius:999px; background:var(--badge-bg); overflow:hidden; }
  .bfill { height:100%; background:var(--accent); border-radius:999px; transition:width .3s ease; }
  .bstep { font-size:12.5px; color:var(--accent); margin:0; display:flex; align-items:center; gap:7px; }
  .blist { display:flex; flex-direction:column; gap:6px; max-height:230px; overflow:auto; }
  .brow { display:flex; align-items:center; gap:9px; font-size:13px; padding:7px 9px; border-radius:8px; background:var(--bg); }
  .brow.running { background:var(--badge-bg); }
  .bstat { flex:none; width:20px; height:20px; border-radius:50%; display:inline-flex; align-items:center; justify-content:center; font-size:10px; font-weight:700; background:var(--line); color:var(--muted); }
  .brow.done .bstat { background:#1db954; color:#fff; } .brow.failed .bstat { background:#b42318; color:#fff; } .brow.skipped .bstat { background:#8a6d3b; color:#fff; }
  .brow.running .bstat { background:var(--accent); color:var(--accent-fg); }
  .bstat :global(i) { font-size:11px; }
  .btitle2 { flex:1; min-width:0; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; color:var(--ink); }
  .brow.done .btitle2, .brow.failed .btitle2, .brow.skipped .btitle2 { color:var(--muted); }
  .bsummary { flex:1; font-size:12.5px; color:var(--muted); font-weight:700; }
  .bnote { font-size:11.5px; color:var(--muted); margin:0; display:flex; align-items:flex-start; gap:6px; background:var(--badge-bg); padding:9px 11px; border-radius:8px; line-height:1.5; }
  .bnote i { flex:none; margin-top:1px; }
  .spin { width:15px; height:15px; border-radius:50%; border:2px solid var(--line); border-top-color:var(--accent); display:inline-block; animation:bspin .8s linear infinite; flex:none; }
  .spin.sm { width:11px; height:11px; border-width:2px; }
  @keyframes bspin { to { transform:rotate(360deg); } }
</style>
