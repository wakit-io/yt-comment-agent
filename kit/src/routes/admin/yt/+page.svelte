<script>
  // 페이지 1 — 영상 리스트. 유튜브 영상 불러오기 → 각 영상 "내용 추출"(LLM 분석) → DB 저장 → 모달.
  import { api } from '$lib/client.js';
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';

  let q = $state('연애');
  let order = $state('date');
  let minViews = $state(''); let maxViews = $state('');
  let rising = $state(false);               // 뜨는 영상(시간당 조회수) 필터
  // 필터 드롭다운(정렬·조회수·뜨는영상을 한 버튼으로 묶음)
  let filterOpen = $state(false);
  const activeFilterCount = $derived((order !== 'date' ? 1 : 0) + (minViews ? 1 : 0) + (maxViews ? 1 : 0) + (rising ? 1 : 0));
  function applyFilter() { filterOpen = false; load(); }
  function resetFilter() { order = 'date'; minViews = ''; maxViews = ''; rising = false; }
  let linkUrl = $state(''); let adding = $state(false); let addMsg = $state(''); let linkModal = $state(false); let linkErr = $state(''); // 링크 직접 추가(모달)
  let videos = $state([]);
  let loading = $state(false);
  let err = $state('');
  let extractedIds = $state(new Set());     // 이미 추출된 영상 id
  let extracting = $state('');              // 추출 중인 videoId
  let modal = $state(null);                 // { title, analysis } 수집완료 모달

  // 이미 추출한 영상은 리스트에서 숨김(영상 선택으로 넘어감)
  const shown = $derived(videos.filter((v) => !extractedIds.has(v.id)));

  function fmtViews(n) { n = +n || 0; return n >= 10000 ? (n / 10000).toFixed(1) + '만' : n.toLocaleString(); }
  function fmtDate(ts) { try { return new Date(ts).toLocaleDateString('ko-KR', { month: 'short', day: 'numeric' }); } catch { return ''; } }

  // ── 무한 스크롤 ──
  const PAGE = 24;
  let booting = $state(true);   // 최초 로딩
  let offset = $state(0);       // DB 저장목록 모드 오프셋(재진입)
  let hasMore = $state(true);
  let loadingMore = $state(false);
  let sentinel = $state(null);  // 바닥 감지 요소
  // YouTube 페이지네이션 모드(불러오기 이후) — 스크롤/재불러오기 때 다음 페이지를 계속 가져온다
  let ytMode = $state(false);
  let ytToken = $state('');     // 다음 페이지 토큰
  let ytSig = $state('');       // 현재 검색 시그니처(바뀌면 처음부터)

  onMount(() => {
    let io;
    (async () => {
      await loadExtracted();
      await resetSaved();
      booting = false;
      // 저장된 영상이 하나도 없으면(최초 진입) 기본 검색으로 한 번 자동 불러오기 → 빈 화면 방지.
      // searchVideos가 결과를 yt_video에 저장하므로 다음 방문부턴 DB에서 바로 보인다.
      if (!videos.length) await load();
      // 초기 로드 후 바닥 감지 시작(레이스 방지). 바닥 근처 오면 다음 페이지 로드.
      io = new IntersectionObserver((entries) => { if (entries[0]?.isIntersecting) loadMore(); }, { rootMargin: '300px' });
      if (sentinel) io.observe(sentinel);
    })();
    return () => io?.disconnect();
  });

  async function loadExtracted() {
    try { const rows = await api('/yt/extracted?limit=300'); extractedIds = new Set(rows.map((r) => r.id)); } catch (e) { /* */ }
  }

  function searchParams(pageToken) {
    const o = { q, order, ...(minViews ? { minViews } : {}), ...(maxViews ? { maxViews } : {}), ...(rising ? { minVph: 150 } : {}) };
    if (pageToken) o.pageToken = pageToken;
    return new URLSearchParams(o);
  }
  const sigOf = () => JSON.stringify([q, order, minViews, maxViews, rising]);
  const dedupAppend = (rows) => { const seen = new Set(videos.map((v) => v.id)); videos = [...videos, ...rows.filter((r) => !seen.has(r.id))]; };

  // 재진입/링크추가: DB 저장목록 모드
  async function resetSaved() {
    ytMode = false; offset = 0; hasMore = true; videos = [];
    await loadMore();
  }
  async function loadMore() {
    if (loadingMore || !hasMore) return;
    loadingMore = true;
    try {
      if (ytMode) {
        // YouTube 다음 페이지를 이어붙임(스크롤할수록 새 영상)
        if (!ytToken) { hasMore = false; }
        else {
          const res = await api('/yt/videos?' + searchParams(ytToken).toString());
          ytToken = res.nextPageToken || ''; hasMore = !!ytToken;
          dedupAppend(res.items || []);
        }
      } else {
        const rows = await api(`/yt/videos/saved?limit=${PAGE}&offset=${offset}`);
        offset += rows.length; hasMore = rows.length === PAGE;
        dedupAppend(rows);
      }
    } catch (e) { /* */ }
    loadingMore = false;
  }

  // 불러오기(검색): YouTube 페이지 단위. 검색어·필터가 그대로면 다음 페이지를 이어붙여 새 영상이 나오고, 바뀌면 처음부터.
  let loadProgress = $state(0);
  const LOAD_DELAY = 2400; // 로딩 팝업 최소 노출(ms)
  async function load() {
    loading = true; loadProgress = 0; err = '';
    const timer = setInterval(() => { loadProgress = Math.min(loadProgress + Math.random() * 11 + 4, 92); }, 200);
    const minShow = new Promise((r) => setTimeout(r, LOAD_DELAY));
    try {
      const sig = sigOf();
      const fresh = !ytMode || sig !== ytSig || !ytToken; // 검색조건 변경 or 소진 시 처음부터
      if (fresh) { videos = []; ytToken = ''; ytSig = sig; }
      const res = await api('/yt/videos?' + searchParams(fresh ? '' : ytToken).toString());
      await minShow;
      ytMode = true; ytToken = res.nextPageToken || ''; hasMore = !!ytToken;
      await loadExtracted();
      if (fresh) videos = res.items || []; else dedupAppend(res.items || []);
      if (fresh && !(res.items || []).length) err = '결과가 없어요. 검색어·필터를 바꿔보세요.';
    } catch (e) { err = e.message; await minShow.catch(() => {}); }
    clearInterval(timer);
    loadProgress = 100;
    setTimeout(() => { loading = false; loadProgress = 0; }, 400); // 100% 잠깐 보여주고 닫기
  }

  // 링크 직접 추가 → 해당 영상 1개를 불러와 리스트 상단에.
  async function addByLink() {
    const url = linkUrl.trim();
    if (!url || adding) return;
    adding = true; linkErr = ''; addMsg = '';
    try {
      const v = await api('/yt/video-add?url=' + encodeURIComponent(url));
      await loadExtracted();
      await resetSaved();
      linkUrl = ''; linkModal = false;
      addMsg = `추가됨: ${v.title}`; setTimeout(() => addMsg = '', 4000);
    } catch (e) { linkErr = e.message; }
    adding = false;
  }

  async function extract(v) {
    extracting = v.id; err = '';
    try {
      const r = await api('/yt/extract', 'POST', { videoId: v.id });
      extractedIds = new Set([...extractedIds, v.id]);
      modal = { title: v.title, analysis: r.analysis };
    } catch (e) { err = e.message; }
    extracting = '';
  }

  // ── 배치 추출(선택 → 순차 처리) ──
  const MAX_SELECT = 10;        // AI 토큰 과소비 방지 — 한 번에 최대 10개까지만 추출
  let selected = $state(new Set());
  let batchRunning = $state(false);
  let batchTotal = $state(0); let batchDone = $state(0); let batchFail = $state(0); let batchCurrent = $state('');
  let toast = $state('');
  let limitMsg = $state('');    // 상한 도달 안내
  const atLimit = $derived(selected.size >= MAX_SELECT);
  const selectable = (v) => !v.comments_disabled;
  function flashLimit() { limitMsg = `한 번에 최대 ${MAX_SELECT}개까지만 선택할 수 있어요 (AI 분석 토큰 절약).`; clearTimeout(flashLimit._t); flashLimit._t = setTimeout(() => limitMsg = '', 3500); }
  function toggleSel(id) {
    const s = new Set(selected);
    if (s.has(id)) { s.delete(id); limitMsg = ''; }
    else { if (s.size >= MAX_SELECT) { flashLimit(); return; } s.add(id); }
    selected = s;
  }
  function selectAll() {
    // 화면에 보이는 목록(shown) 기준으로 앞에서부터 — 숨겨진(이미 추출된) 영상이 섞이지 않게
    const ids = shown.filter(selectable).map((v) => v.id);
    selected = new Set(ids.slice(0, MAX_SELECT));
    if (ids.length > MAX_SELECT) flashLimit();
  }
  function clearSel() { selected = new Set(); limitMsg = ''; }
  async function runBatch() {
    const ids = [...selected].filter((id) => { const v = videos.find((x) => x.id === id); return v && selectable(v); });
    if (!ids.length || batchRunning) return;
    batchRunning = true; batchTotal = ids.length; batchDone = 0; batchFail = 0; batchCurrent = ''; err = '';
    for (const id of ids) {
      const v = videos.find((x) => x.id === id);
      batchCurrent = v?.title || id;
      try { await api('/yt/extract', 'POST', { videoId: id }); extractedIds = new Set([...extractedIds, id]); }
      catch (e) { batchFail++; }
      batchDone++;
    }
    batchRunning = false;
    const okN = batchTotal - batchFail;
    toast = `내용 추출 완료 — 성공 ${okN}/${batchTotal}${batchFail ? `, 실패 ${batchFail}` : ''}`;
    clearSel();
    setTimeout(() => toast = '', 4500);
  }
</script>

<svelte:head><title>영상 불러오기 — 댓글 에이전트</title></svelte:head>

<div class="ph">
  <div><h1>영상 불러오기</h1><p class="sub">유튜브 영상을 불러와 <b>내용 추출</b>(AI 영상 분석)하면 「영상 선택」에 쌓입니다.</p></div>
</div>

<div class="bar">
  <input class="inp qinp" bind:value={q} placeholder="검색어 (예: 연애 고민)" onkeydown={(e) => e.key === 'Enter' && load()} />
  <button class="chip filterbtn" class:on={activeFilterCount > 0} onclick={() => filterOpen = true} title="정렬·조회수·뜨는 영상 필터">
    <i class="fi-rr-settings-sliders"></i> 필터{#if activeFilterCount > 0}<span class="fcount">{activeFilterCount}</span>{/if}
  </button>
  <button class="chip" onclick={() => { linkModal = true; linkErr = ''; addMsg = ''; }} title="유튜브 링크로 특정 영상 추가"><i class="fi-rr-link-alt"></i> 링크로 추가</button>
  <button class="btn primary" onclick={load} disabled={loading}>{loading ? '불러오는 중…' : '불러오기'}</button>
</div>
{#if addMsg}<p class="addmsg"><i class="fi-rr-check"></i> {addMsg}</p>{/if}

{#if err}<p class="banner err">{err}</p>{/if}

{#if selected.size > 0}
  <div class="selbar">
    <span class="selcount"><i class="fi-rr-check"></i> {selected.size}/{MAX_SELECT}개 선택됨{#if atLimit} <em class="selmax">· 최대</em>{/if}</span>
    <div class="selactions">
      <button class="btn xs" onclick={selectAll} disabled={batchRunning || atLimit}>전체 선택</button>
      <button class="btn xs" onclick={clearSel} disabled={batchRunning}>선택 해제</button>
      <button class="btn primary sm" onclick={runBatch} disabled={batchRunning}>선택한 {selected.size}개 추출</button>
    </div>
  </div>
{/if}
{#if limitMsg}<p class="limitmsg"><i class="fi-rr-info"></i> {limitMsg}</p>{/if}

<div class="grid">
  {#if loading || booting}
    {#each Array(8) as _}<div class="vskel"></div>{/each}
  {:else}
    {#each shown as v (v.id)}
      <div class="vcard" class:sel={selected.has(v.id)}>
        {#if selectable(v)}
          <button class="selbox" class:on={selected.has(v.id)} class:lock={atLimit && !selected.has(v.id)} onclick={() => toggleSel(v.id)} disabled={batchRunning} aria-label="선택" title={atLimit && !selected.has(v.id) ? `최대 ${MAX_SELECT}개까지 선택 가능` : '선택'}>
            {#if selected.has(v.id)}<i class="fi-rr-check"></i>{:else if atLimit}<i class="fi-rr-lock"></i>{/if}
          </button>
        {/if}
        <a class="thumb" href={'https://www.youtube.com/watch?v=' + v.id} target="_blank" rel="noopener">
          <img src={v.thumb} alt="" loading="lazy" />
          {#if extractedIds.has(v.id)}<span class="done"><i class="fi-rr-check"></i> 추출됨</span>{/if}
          {#if v.comments_disabled}<span class="cdis"><i class="fi-rr-comment-dots"></i> 댓글 꺼짐</span>{/if}
        </a>
        <div class="vmeta">
          <div class="vtitle">{v.title}</div>
          <div class="vsub">{v.channel_title} · 조회 {fmtViews(v.view_count)} · {fmtDate(v.published_at)}</div>
        </div>
        <button class="btn sm extract" class:ghost={extractedIds.has(v.id) || v.comments_disabled} onclick={() => extract(v)} disabled={extracting === v.id || v.comments_disabled || batchRunning}>
          {extracting === v.id ? 'AI 분석 중…' : v.comments_disabled ? '게시 불가 (댓글 꺼짐)' : extractedIds.has(v.id) ? '다시 추출' : '내용 추출'}
        </button>
      </div>
    {/each}
    {#if !shown.length && !err && !booting && !loadingMore}<p class="empty">{videos.length ? '표시할 영상이 없어요(모두 추출됨). 다른 검색어로 불러와 보세요.' : '아직 수집된 영상이 없어요. 검색어를 넣고 「불러오기」를 눌러보세요.'}</p>{/if}
  {/if}
</div>

<!-- 무한 스크롤: 바닥 감지 -->
<div class="sentinel" bind:this={sentinel}></div>
{#if loadingMore}<p class="loadmore">더 불러오는 중…</p>{/if}
{#if !hasMore && shown.length > 0 && !loading && !booting}<p class="loadmore end">모든 영상을 불러왔어요 ({shown.length}개)</p>{/if}

{#if loading}
  <div class="load-overlay" role="presentation">
    <div class="load-box">
      <div class="load-spin"></div>
      <div class="load-title">유튜브 영상 불러오는 중…</div>
      <div class="load-bar"><div class="load-fill" style="width:{loadProgress}%"></div></div>
      <div class="load-pct">{Math.round(loadProgress)}%</div>
    </div>
  </div>
{/if}

{#if filterOpen}
  <div class="load-overlay" role="presentation" onclick={() => filterOpen = false}>
    <div class="filtermodal" role="dialog" aria-modal="true" aria-label="검색 필터" onclick={(e) => e.stopPropagation()}>
      <div class="fmhead"><span class="fmtitle"><i class="fi-rr-settings-sliders"></i> 검색 필터</span><button class="fmclose" onclick={() => filterOpen = false} aria-label="닫기" title="닫기"><i class="fi-rr-cross-small"></i></button></div>
      <div class="fprow">
        <label class="flabel" for="fo">정렬</label>
        <select id="fo" class="inp sel" bind:value={order}>
          <option value="date">최신순</option>
          <option value="viewCount">조회수순</option>
          <option value="relevance">관련도순</option>
        </select>
      </div>
      <div class="fprow">
        <span class="flabel">조회수 범위</span>
        <div class="fvrow">
          <input class="inp vw" bind:value={minViews} placeholder="최소" inputmode="numeric" />
          <span class="fdash">~</span>
          <input class="inp vw" bind:value={maxViews} placeholder="최대" inputmode="numeric" />
        </div>
      </div>
      <div class="fprow">
        <span class="flabel">뜨는 영상</span>
        <button class="chip rise fulltoggle" class:on={rising} onclick={() => rising = !rising} title="업로드 후 시간당 조회수가 높은 '뜨는 중' 영상만">
          <i class="fi-rr-flame"></i> {rising ? '켜짐 (시간당 조회수 높은 영상)' : '꺼짐'}
        </button>
      </div>
      <div class="fpbtns">
        <button class="btn" onclick={resetFilter} disabled={activeFilterCount === 0}>초기화</button>
        <button class="btn primary" onclick={applyFilter}>적용</button>
      </div>
    </div>
  </div>
{/if}

{#if linkModal}
  <div class="load-overlay" role="presentation" onclick={() => linkModal = false}>
    <div class="linkmodal" role="dialog" aria-modal="true" onclick={(e) => e.stopPropagation()}>
      <div class="lmhead"><i class="fi-rr-link-alt"></i> 링크로 영상 추가</div>
      <p class="lmdesc">유튜브 영상 링크를 붙여넣으면 바로 목록에 추가됩니다. (카테고리·댓글꺼짐 필터 없이 그대로)</p>
      <input class="lminput" bind:value={linkUrl} placeholder="https://www.youtube.com/watch?v=…  ·  youtu.be/…  ·  shorts/…" onkeydown={(e) => e.key === 'Enter' && addByLink()} />
      {#if linkErr}<p class="lmerr"><i class="fi-rr-exclamation"></i> {linkErr}</p>{/if}
      <div class="lmbtns">
        <button class="btn" onclick={() => linkModal = false}>닫기</button>
        <button class="btn primary" onclick={addByLink} disabled={adding || !linkUrl.trim()}>{adding ? '추가 중…' : '추가'}</button>
      </div>
    </div>
  </div>
{/if}

{#if batchRunning}
  <div class="load-overlay" role="presentation">
    <div class="load-box">
      <div class="load-spin"></div>
      <div class="load-title">내용 추출 중… {batchDone}/{batchTotal}</div>
      <div class="load-sub">{batchCurrent}</div>
      <div class="load-bar"><div class="load-fill" style="width:{batchTotal ? (batchDone / batchTotal * 100) : 0}%"></div></div>
      <div class="load-pct">{batchTotal ? Math.round(batchDone / batchTotal * 100) : 0}%{batchFail ? ` · 실패 ${batchFail}` : ''}</div>
    </div>
  </div>
{/if}

{#if extracting && !batchRunning}
  <div class="load-overlay" role="presentation">
    <div class="load-box">
      <div class="load-spin"></div>
      <div class="load-title">내용 추출 중입니다</div>
      <div class="load-sub wrap">AI가 영상을 분석하고 있어요. 잠시만 기다려 주세요…</div>
    </div>
  </div>
{/if}

{#if toast}<div class="toast"><i class="fi-rr-check"></i> {toast}</div>{/if}

{#if modal}
  <div class="overlay" onclick={() => modal = null} role="presentation">
    <div class="box" onclick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
      <div class="bicon"><i class="fi-rr-check"></i></div>
      <h3>내용 수집 완료했습니다</h3>
      <p class="btitle">{modal.title}</p>
      {#if modal.analysis?.source}
        <span class="srcbadge" class:video={modal.analysis.source === 'video'}><i class="fi-rr-{modal.analysis.source === 'video' ? 'film' : 'document'}"></i> {modal.analysis.source === 'video' ? '영상 분석' : '메타데이터'}</span>
      {/if}
      {#if modal.analysis?.summary}<p class="bsum">{modal.analysis.summary}</p>{/if}
      {#if modal.analysis?.comment}<div class="bdraft"><span class="lbl">댓글 초안</span>{modal.analysis.comment}</div>{/if}
      <div class="bactions">
        <button class="btn" onclick={() => modal = null}>계속 추출</button>
        <button class="btn primary" onclick={() => goto('/admin/yt/comments')}>영상 선택으로 →</button>
      </div>
    </div>
  </div>
{/if}

<style>
  .ph { display:flex; justify-content:space-between; align-items:flex-start; gap:12px; flex-wrap:wrap; }
  .ph h1 { margin:0; font-size:22px; } .sub { margin:4px 0 0; color:var(--muted); font-size:13px; }
  .bar { display:flex; gap:8px; margin-top:16px; flex-wrap:wrap; }
  .chip { display:inline-flex; align-items:center; gap:5px; border:1px solid var(--line); background:var(--surface); color:var(--muted); border-radius:9px; padding:0 13px; font-size:13px; font-weight:700; cursor:pointer; white-space:nowrap; }
  .chip:hover { border-color:var(--accent); }
  .chip.rise.on { background:var(--accent); border-color:var(--accent); color:var(--accent-fg); }
  /* 필터 버튼 + 모달 */
  .filterbtn.on { border-color:var(--accent); color:var(--accent); }
  .fcount { display:inline-flex; align-items:center; justify-content:center; min-width:17px; height:17px; padding:0 4px; border-radius:999px; background:var(--accent); color:var(--accent-fg); font-size:11px; font-weight:800; margin-left:2px; }
  .filtermodal { background:var(--surface); border:1px solid var(--line); border-radius:16px; padding:20px; width:340px; max-width:100%; box-shadow:0 24px 70px rgba(0,0,0,.5); display:flex; flex-direction:column; gap:15px; }
  .fmhead { font-size:16px; font-weight:800; display:flex; align-items:center; justify-content:space-between; gap:8px; }
  .fmtitle { display:inline-flex; align-items:center; gap:8px; } .fmtitle i { color:var(--accent); }
  .fmclose { flex:none; width:30px; height:30px; border:0; background:transparent; color:var(--muted); border-radius:8px; cursor:pointer; display:flex; align-items:center; justify-content:center; font-size:18px; }
  .fmclose:hover { background:var(--badge-bg); color:var(--ink); }
  .fprow { display:flex; flex-direction:column; gap:7px; }
  .flabel { font-size:12.5px; font-weight:700; color:var(--muted); }
  .fvrow { display:flex; align-items:center; gap:8px; }
  .fvrow .vw { flex:1; width:auto; min-width:0; }
  .fdash { color:var(--muted); flex:none; }
  .fulltoggle { justify-content:flex-start; padding:10px 12px; border-radius:9px; }
  .fpbtns { display:flex; justify-content:flex-end; gap:8px; margin-top:4px; border-top:1px solid var(--line); padding-top:15px; }
  .addmsg { font-size:12.5px; color:var(--ok-fg); margin:8px 0 0; display:flex; align-items:center; gap:5px; }
  /* 링크 추가 모달 */
  .linkmodal { background:var(--surface); border:1px solid var(--line); border-radius:16px; padding:22px; max-width:460px; width:100%; box-shadow:0 24px 70px rgba(0,0,0,.5); }
  .lmhead { font-size:16px; font-weight:800; display:flex; align-items:center; gap:8px; } .lmhead i { color:var(--accent); }
  .lmdesc { font-size:13px; color:var(--muted); line-height:1.6; margin:10px 0 14px; }
  .lminput { width:100%; box-sizing:border-box; padding:11px 13px; border:1px solid var(--line); border-radius:10px; background:var(--bg); color:var(--ink); font:inherit; font-size:14px; }
  .lmerr { font-size:13px; color:#d9534f; margin:10px 0 0; display:flex; align-items:center; gap:5px; }
  .lmbtns { display:flex; justify-content:flex-end; gap:8px; margin-top:18px; }
  .inp { padding:9px 11px; border:1px solid var(--line); border-radius:9px; background:var(--bg); color:var(--ink); font:inherit; font-size:13.5px; }
  .inp:not(.sel):not(.vw) { flex:1; min-width:180px; } .sel { cursor:pointer; } .vw { width:110px; }
  /* 검색창은 페이지 배경과 구분되게 서피스 색(라이트=흰색, 다크=카드색) */
  .qinp { background:var(--surface); }
  .banner { padding:10px 13px; border-radius:10px; font-size:13.5px; margin:12px 0 0; } .banner.err { background:#fde8e8; color:#b42318; }

  .grid { display:grid; grid-template-columns:repeat(3, 1fr); gap:18px; margin-top:16px; }
  @media(max-width:900px){ .grid{ grid-template-columns:repeat(2, 1fr); } }
  @media(max-width:560px){ .grid{ grid-template-columns:1fr; } }
  .vcard { position:relative; background:var(--surface); border:1px solid var(--line); border-radius:12px; overflow:hidden; display:flex; flex-direction:column; transition:background .12s; }
  .vcard:hover { background:var(--surface-alt); }
  .vcard.sel { border-color:var(--accent); box-shadow:0 0 0 2px var(--accent) inset; }
  .selbox { position:absolute; top:8px; left:8px; z-index:3; width:24px; height:24px; border-radius:7px; border:1.5px solid #fff; background:rgba(0,0,0,.45); cursor:pointer; display:flex; align-items:center; justify-content:center; color:#fff; padding:0; opacity:0; transition:opacity .12s; box-shadow:0 1px 4px rgba(0,0,0,.3); }
  .vcard:hover .selbox, .selbox.on, .selbox:focus-visible { opacity:1; }
  .selbox.on { background:var(--accent); border-color:var(--accent); color:var(--accent-fg); }
  .selbox.lock { background:rgba(0,0,0,.55); border-color:rgba(255,255,255,.5); cursor:not-allowed; }
  .selbox.lock i { opacity:.85; }
  .selbox i { font-size:13px; }
  .selbar { display:flex; align-items:center; justify-content:space-between; gap:10px; flex-wrap:wrap; margin-top:12px; padding:10px 14px; background:var(--badge-bg); border:1px solid var(--line); border-radius:11px; }
  .selcount { font-size:13px; font-weight:800; color:var(--accent); display:inline-flex; align-items:center; gap:6px; }
  .selmax { font-style:normal; font-weight:700; color:var(--muted); }
  .limitmsg { display:flex; align-items:center; gap:6px; margin:8px 0 0; font-size:12.5px; color:#b9770b; background:#fff4e0; border:1px solid #f3d9a6; padding:8px 12px; border-radius:9px; }
  .selactions { display:flex; gap:8px; flex-wrap:wrap; }
  .toast { position:fixed; left:50%; bottom:26px; transform:translateX(-50%); background:#13794a; color:#fff; font-size:13.5px; font-weight:700; padding:11px 18px; border-radius:999px; box-shadow:0 10px 30px rgba(0,0,0,.25); z-index:70; display:inline-flex; align-items:center; gap:7px; }
  .load-sub { font-size:12px; color:var(--muted); margin:-6px 0 12px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .load-sub.wrap { white-space:normal; overflow:visible; line-height:1.6; margin:2px 0 0; }
  .thumb { position:relative; display:block; } .thumb img { width:100%; aspect-ratio:16/9; object-fit:cover; background:var(--line); display:block; transition:transform .35s ease; }
  .vcard:hover .thumb img { transform:scale(1.06); }
  .done { position:absolute; bottom:8px; left:8px; background:var(--accent); color:var(--accent-fg); font-size:11px; font-weight:700; padding:3px 8px; border-radius:999px; }
  .cdis { position:absolute; top:8px; right:8px; background:#b42318; color:#fff; font-size:11px; font-weight:700; padding:3px 8px; border-radius:999px; display:inline-flex; align-items:center; gap:4px; }
  .vmeta { padding:12px 13px 9px; flex:1; } .vtitle { font-size:15px; font-weight:700; line-height:1.4; display:-webkit-box; -webkit-line-clamp:2; line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
  .vsub { font-size:12.5px; color:var(--muted); margin-top:5px; }
  .extract { margin:0 13px 13px; font-size:13.5px; padding:10px; } .btn.ghost { background:transparent; border:1px solid var(--line); color:var(--muted); }
  .vskel { height:210px; border-radius:12px; background:linear-gradient(90deg,var(--line),var(--bg),var(--line)); background-size:200% 100%; animation:sh 1.2s infinite; }
  @keyframes sh { 0%{background-position:200% 0} 100%{background-position:-200% 0} }
  .empty { color:var(--muted); font-size:13px; text-align:center; padding:40px 0; grid-column:1/-1; }
  .sentinel { height:1px; }
  .loadmore { text-align:center; color:var(--muted); font-size:12.5px; padding:16px 0; }
  .loadmore.end { color:var(--muted); opacity:.7; }

  /* 로딩 게이지 팝업 */
  .load-overlay { position:fixed; inset:0; background:rgba(0,0,0,.6); display:flex; align-items:center; justify-content:center; z-index:60; padding:20px; backdrop-filter:blur(5px); -webkit-backdrop-filter:blur(5px); }
  .load-box { background:var(--bg); border:1px solid var(--line); border-radius:16px; padding:26px 28px; width:320px; max-width:100%; text-align:center; box-shadow:0 20px 60px rgba(0,0,0,.3); }
  .load-spin { width:34px; height:34px; border-radius:50%; border:3px solid var(--line); border-top-color:var(--accent); margin:0 auto 14px; animation:spin .8s linear infinite; }
  @keyframes spin { to { transform:rotate(360deg); } }
  .load-title { font-size:14px; font-weight:700; color:var(--ink); margin-bottom:14px; }
  .load-bar { height:8px; border-radius:999px; background:var(--badge-bg); overflow:hidden; }
  .load-fill { height:100%; background:var(--accent); border-radius:999px; transition:width .2s ease; }
  .load-pct { font-size:12px; font-weight:700; color:var(--accent); margin-top:8px; }
  .overlay { position:fixed; inset:0; background:rgba(0,0,0,.6); display:flex; align-items:center; justify-content:center; z-index:50; padding:20px; backdrop-filter:blur(5px); -webkit-backdrop-filter:blur(5px); }
  .box { background:var(--surface); border-radius:16px; padding:24px; max-width:440px; width:100%; text-align:center; }
  .bicon { width:48px; height:48px; border-radius:50%; background:#e4f5ec; color:#13794a; font-size:24px; display:flex; align-items:center; justify-content:center; margin:0 auto 12px; }
  .box h3 { margin:0 0 6px; font-size:18px; } .btitle { font-size:13px; color:var(--muted); margin:0 0 12px; }
  .srcbadge { display:inline-block; font-size:11px; font-weight:700; padding:3px 9px; border-radius:999px; background:var(--badge-bg); color:var(--muted); }
  .srcbadge.video { background:var(--accent); color:var(--accent-fg); }
  .bsum { font-size:13px; line-height:1.6; text-align:left; margin:12px 0; color:var(--ink); }
  .bdraft { text-align:left; background:var(--bg); border:1px solid var(--line); border-radius:9px; padding:10px; font-size:13.5px; line-height:1.6; }
  .bdraft .lbl { display:block; font-size:11px; color:var(--muted); font-weight:700; margin-bottom:4px; }
  .bactions { display:flex; gap:8px; margin-top:18px; } .bactions .btn { flex:1; }
</style>
