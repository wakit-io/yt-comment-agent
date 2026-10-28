<script>
  import { api } from '$lib/client.js';
  import { onMount } from 'svelte';

  let err = $state('');
  let loaded = $state(false);

  // ── YouTube 계정 연결 ──
  let oauth = $state({ configured: false, connected: false, channel_title: '', channel_id: '' });
  let connecting = $state(false); let disconnecting = $state(false);
  let notice = $state('');
  async function loadOauth() { try { oauth = { ...oauth, ...(await api('/yt/oauth/status')) }; } catch (e) { /* */ } }
  async function connect() {
    connecting = true; err = '';
    try { const { url } = await api('/yt/oauth/url'); window.location.href = url; }
    catch (e) { err = e.message; connecting = false; }
  }
  async function disconnect() {
    if (!confirm('연결을 해제할까요? 다시 연결하기 전에는 게시가 안 됩니다.')) return;
    disconnecting = true; err = '';
    try { await api('/yt/oauth/disconnect', 'POST', {}); await loadOauth(); notice = '연결을 해제했어요.'; setTimeout(() => notice = '', 3000); }
    catch (e) { err = e.message; }
    disconnecting = false;
  }

  // ── 댓글 생성 설정 (브랜드 + 공개모드 + 페르소나) ──
  let brand = $state('');
  let brandOpen = $state(false);
  let persona = $state('');
  let savingP = $state(false); let savedP = $state('');

  // ── 운영 규칙 (글자수 · 하루 상한) ──
  let ops = $state({ min_chars: 40, max_chars: 120, daily_max_comments: 10 });
  let savingOps = $state(false); let savedOps = $state('');

  onMount(async () => {
    try { const s = await api('/yt/settings'); brand = s.brand || ''; brandOpen = !!s.brand_open; persona = s.persona || ''; ops = { min_chars: s.min_chars ?? 40, max_chars: s.max_chars ?? 120, daily_max_comments: s.daily_max_comments ?? 10 }; } catch (e) { err = e.message; }
    await loadOauth();
    loaded = true;
    // OAuth 콜백 후 돌아온 경우 알림
    try {
      const p = new URLSearchParams(location.search);
      if (p.get('connected')) { notice = `YouTube 계정이 연결됐어요 (${decodeURIComponent(p.get('connected'))}).`; setTimeout(() => notice = '', 4000); }
      else if (p.get('error')) { err = '연결 실패: ' + decodeURIComponent(p.get('error')); }
      if (p.get('connected') || p.get('error')) history.replaceState(null, '', location.pathname);
    } catch (e) { /* */ }
  });
  async function savePersona() {
    savingP = true; savedP = ''; err = '';
    try { await api('/yt/settings', 'POST', { brand, brand_open: brandOpen, persona }); savedP = '저장됨'; setTimeout(() => savedP = '', 2500); }
    catch (e) { err = e.message; }
    savingP = false;
  }
  async function saveOps() {
    savingOps = true; savedOps = ''; err = '';
    try { await api('/yt/settings', 'POST', { min_chars: +ops.min_chars, max_chars: +ops.max_chars, daily_max_comments: +ops.daily_max_comments }); savedOps = '저장됨'; setTimeout(() => savedOps = '', 2500); }
    catch (e) { err = e.message; }
    savingOps = false;
  }
  const PRESETS = [
    { label: '지친 20~30대', text: '연애에 지친 20~30대 시청자. 공감 잘하고 솔직한 구어체(반말 섞어 편하게). 자기 연애도 잘 안 풀려서 ‘운명’이나 사주/인연에 은근히 관심이 생긴 사람의 말투.' },
    { label: '차분한 공감형', text: '30대 직장인. 차분하고 다정한 존댓말. 상대 고민을 깊이 읽고 위로하며, 인연의 때나 흐름을 궁금해하는 담담한 톤.' },
    { label: '유쾌한 친구', text: '20대 후반, 밝고 유쾌한 반말 친구 말투. 가볍게 공감하고 농담 섞되, 끝에 “나도 내 연애운 궁금하다”는 호기심을 자연스럽게 남김.' },
  ];

  // ── 데이터 내보내기 (영상/댓글 → 엑셀 CSV) ──
  let exporting = $state(''); let exportMsg = $state('');
  async function doExport(kind) {
    exporting = kind; exportMsg = ''; err = '';
    try {
      const r = await api('/yt/export?kind=' + kind);
      const blob = new Blob(['﻿' + r.csv], { type: 'text/csv;charset=utf-8' }); // BOM → 엑셀 한글 정상
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a'); a.href = url; a.download = r.filename; document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      exportMsg = `${r.filename} 내려받음 (${r.count}건)`; setTimeout(() => exportMsg = '', 4000);
    } catch (e) { err = e.message; }
    exporting = '';
  }
</script>

<svelte:head><title>설정 — 댓글 에이전트</title></svelte:head>

<div class="ph"><div><h1>설정</h1><p class="sub">댓글 생성 · 데이터 내보내기</p></div></div>

{#if err}<p class="err">{err}</p>{/if}
{#if notice}<p class="ok-banner"><i class="fi-rr-check"></i> {notice}</p>{/if}

<div class="card">
  <h3>YouTube 계정</h3>
  <p class="muted" style="margin-top:0">댓글을 <b>게시할 본인(브랜드) 계정</b>을 연결합니다. 게시는 이 계정으로 공식 YouTube API를 통해 올라가요.</p>
  {#if !loaded}
    <p class="muted">불러오는 중…</p>
  {:else if !oauth.configured}
    <p class="acc-warn"><i class="fi-rr-triangle-warning"></i> OAuth 미설정 — <code>.env</code>에 GOOGLE_CLIENT_ID/SECRET 를 넣고 서버를 재시작하세요.</p>
  {:else if oauth.connected}
    <div class="acc on">
      <div class="accinfo">
        <span class="dot"></span>
        <div>
          <div class="accname">{oauth.channel_title || '연결됨'}</div>
          <div class="accsub">연결됨 · 이 계정으로 게시돼요</div>
        </div>
      </div>
      <div class="accbtns">
        <button class="btn sm" onclick={connect} disabled={connecting}>{connecting ? '여는 중…' : '다른 계정으로 연결'}</button>
        <button class="btn sm danger" onclick={disconnect} disabled={disconnecting}>{disconnecting ? '해제 중…' : '연결 해제'}</button>
      </div>
    </div>
  {:else}
    <div class="acc off">
      <div class="accinfo"><span class="dot off"></span><div class="accname">연결 안 됨</div></div>
      <button class="btn primary sm" onclick={connect} disabled={connecting}>{connecting ? '여는 중…' : 'YouTube 계정 연결'}</button>
    </div>
  {/if}
</div>

<div class="card">
  <h3>댓글 생성 설정</h3>
  <p class="muted" style="margin-top:0">AI가 댓글을 쓸 때 참고하는 <b>브랜드·목소리</b>를 정합니다. 영상을 본 시청자의 톤으로 공감하며, 해당 주제의 사주·인연에 대한 궁금증을 자연스럽게 남기도록 안내돼요.</p>
  {#if !loaded}
    <p class="muted">불러오는 중…</p>
  {:else}
    <label class="flabel" for="brand">브랜드 / 서비스명</label>
    <input id="brand" class="finput" bind:value={brand} placeholder="예) 운명원" />

    <div class="toggle">
      <button type="button" class="sw" class:on={brandOpen} role="switch" aria-checked={brandOpen} onclick={() => brandOpen = !brandOpen}><span class="knob"></span></button>
      <div class="tlabel">
        <b>브랜드 공개 모드</b> {brandOpen ? '— 켜짐' : '— 꺼짐'}
        <span class="tdesc">
          {#if brandOpen}
            브랜드 <b>공식 계정 입장</b>에서 신분을 밝히고 댓글을 씁니다. 댓글에 <b>브랜드명이 들어가고</b> 영상 상황과 연결해 도움을 소개해요. (은폐 광고 아님 → 정책 안전)
          {:else}
            일반 <b>시청자 페르소나</b>로 씁니다. 브랜드명 없이, 그 주제(연애 사주)에 대한 궁금증만 자연스럽게 남겨요.
          {/if}
        </span>
      </div>
    </div>
    <p class="fhint">{brandOpen ? '⚠️ 공식 계정으로 게시할 때 쓰세요. 반드시 브랜드 소유 계정으로 연결되어 있어야 떳떳한 공개 댓글이 됩니다.' : '브랜드명을 심거나 "써봤더니 좋더라" 같은 지어낸 후기는 넣지 않습니다.'}</p>

    <label class="flabel" for="persona" style="margin-top:14px">댓글 페르소나 <span class="hint">(목소리·말투)</span></label>
    <div class="presets">
      {#each PRESETS as p}<button class="chip" onclick={() => persona = p.text}>{p.label}</button>{/each}
    </div>
    <textarea id="persona" bind:value={persona} rows="4" placeholder="예) 연애에 지친 20~30대, 솔직한 구어체. 사주·인연에 은근히 관심이 생긴 말투."></textarea>
    <div class="row">
      <button class="btn primary sm" onclick={savePersona} disabled={savingP}>{savingP ? '저장 중…' : '저장'}</button>
      {#if savedP}<span class="ok">{savedP}</span>{/if}
    </div>
    <p class="note"><i class="fi-rr-info"></i> 가짜 신원·다계정이 아니라 <b>내가 다는 댓글의 톤</b>을 정하는 설정입니다. 링크·해시태그·지어낸 후기는 항상 자동 차단돼요.</p>
  {/if}
</div>

<div class="card">
  <h3>운영 규칙 (글자수 · 하루 상한)</h3>
  <p class="muted" style="margin-top:0">댓글 <b>길이 범위</b>와 <b>하루 게시 상한</b>을 정합니다. 스팸처럼 보이지 않게 영상당 1개·하루 상한을 지켜 게시돼요.</p>
  <div class="opsgrid">
    <label class="flabel oplabel">최소 글자수<input class="finput" type="number" min="1" bind:value={ops.min_chars} /></label>
    <label class="flabel oplabel">최대 글자수<input class="finput" type="number" min="1" bind:value={ops.max_chars} /></label>
    <label class="flabel oplabel">하루 상한<input class="finput" type="number" min="1" bind:value={ops.daily_max_comments} /></label>
  </div>
  <div class="row">
    <button class="btn primary sm" onclick={saveOps} disabled={savingOps}>{savingOps ? '저장 중…' : '저장'}</button>
    {#if savedOps}<span class="ok">{savedOps}</span>{/if}
  </div>
</div>

<div class="card">
  <h3>데이터 내보내기 (엑셀)</h3>
  <p class="muted" style="margin-top:0">쌓인 데이터를 <b>엑셀(CSV)</b>로 내려받아 보관·분석하세요. 엑셀에서 한글이 바로 열립니다.</p>
  <div class="exports">
    <button class="btn sm" onclick={() => doExport('videos')} disabled={exporting === 'videos'}>
      <i class="fi-rr-download"></i> {exporting === 'videos' ? '내보내는 중…' : '영상 데이터'}
    </button>
    <button class="btn sm" onclick={() => doExport('comments')} disabled={exporting === 'comments'}>
      <i class="fi-rr-download"></i> {exporting === 'comments' ? '내보내는 중…' : '댓글 데이터'}
    </button>
  </div>
  <p class="muted" style="margin:10px 0 0; font-size:12px">영상 데이터 = 추출한 영상(제목·채널·조회수·고민·요약·초안). 댓글 데이터 = 게시 기록(영상·프로필·댓글·상태·링크).</p>
  {#if exportMsg}<p class="msg" style="color:var(--ok-fg); margin-top:10px">{exportMsg}</p>{/if}
</div>

<style>
  .ph h1 { margin:0; font-size:22px; } .sub { margin:4px 0 0; color:var(--muted); font-size:13px; }
  .err { background:#fde8e8; color:#b42318; padding:10px 13px; border-radius:10px; font-size:13.5px; }
  .ok-banner { background:#e4f5ec; color:#13794a; padding:10px 13px; border-radius:10px; font-size:13.5px; display:flex; align-items:center; gap:7px; }
  .acc-warn { font-size:13px; color:#8a5a00; background:#fdf0d5; padding:10px 12px; border-radius:9px; display:flex; align-items:center; gap:7px; }
  .acc-warn code { background:rgba(0,0,0,.08); padding:1px 6px; border-radius:5px; }
  .acc { display:flex; align-items:center; justify-content:space-between; gap:12px; flex-wrap:wrap; margin-top:12px; padding:12px 14px; border:1px solid var(--line); border-radius:11px; background:var(--surface); }
  .accinfo { display:flex; align-items:center; gap:11px; }
  .dot { width:9px; height:9px; border-radius:50%; background:#1db954; box-shadow:0 0 0 3px rgba(29,185,84,.18); flex:none; }
  .dot.off { background:#b0b0b0; box-shadow:0 0 0 3px rgba(160,160,160,.15); }
  .accname { font-size:14px; font-weight:800; } .accsub { font-size:12px; color:var(--muted); margin-top:1px; }
  .accbtns { display:flex; gap:8px; flex-wrap:wrap; }
  .btn.danger { color:var(--danger-fg); border:1px solid var(--danger-fg); background:transparent; }
  .btn.danger:hover { background:var(--danger-bg); border-color:var(--danger-fg); }
  .flabel { display:block; font-size:12.5px; font-weight:700; color:var(--ink); margin:0 0 6px; }
  .opsgrid { display:grid; grid-template-columns:repeat(3, 1fr); gap:12px; margin-top:4px; }
  .opsgrid .oplabel { display:flex; flex-direction:column; gap:6px; margin:0; }
  @media(max-width:560px){ .opsgrid { grid-template-columns:1fr 1fr; } }
  .finput { width:100%; box-sizing:border-box; padding:10px 11px; border:1px solid var(--line); border-radius:9px; background:var(--bg); color:var(--ink); font:inherit; font-size:14px; }
  .fhint { font-size:12px; color:var(--muted); margin:7px 0 0; line-height:1.5; }
  .toggle { display:flex; gap:11px; align-items:flex-start; margin-top:14px; }
  .sw { flex:none; width:42px; height:24px; border-radius:999px; border:none; background:var(--line); position:relative; cursor:pointer; transition:background .15s; padding:0; margin-top:1px; }
  .sw.on { background:var(--accent); }
  .sw .knob { position:absolute; top:3px; left:3px; width:18px; height:18px; border-radius:50%; background:#fff; box-shadow:0 1px 2px rgba(0,0,0,.3); transition:left .15s, background .15s; }
  .sw.on .knob { left:21px; background:var(--accent-fg); } /* 켜짐: 트랙=accent(다크=흰색) → 손잡이는 반전색으로 보이게 */
  .tlabel { font-size:13px; } .tlabel .tdesc { display:block; font-size:12px; color:var(--muted); margin-top:3px; line-height:1.5; }
  .presets { display:flex; flex-wrap:wrap; gap:6px; margin:4px 0 10px; }
  .chip { font-size:12px; font-weight:600; padding:5px 11px; border:1px solid var(--line); border-radius:999px; background:var(--surface); color:var(--ink); cursor:pointer; }
  .chip:hover { border-color:var(--accent); color:var(--accent); }
  textarea { width:100%; box-sizing:border-box; padding:11px; border:1px solid var(--line); border-radius:9px; background:var(--bg); color:var(--ink); font:inherit; font-size:14px; line-height:1.6; resize:vertical; }
  .row { display:flex; align-items:center; gap:10px; margin-top:10px; } .ok { color:var(--ok-fg); font-size:13px; font-weight:700; }
  .note { font-size:12px; color:var(--muted); margin:12px 0 0; display:flex; align-items:center; gap:6px; background:var(--badge-bg); padding:9px 11px; border-radius:9px; }
  .exports{ display:flex; flex-wrap:wrap; gap:8px; margin-top:12px; }
  .exports .btn{ display:inline-flex; align-items:center; gap:6px; }
</style>
