<script>
  import { api } from '$lib/client.js';
  import { onMount } from 'svelte';

  let s = $state(null);
  let vids = $state([]);
  let err = $state('');

  function fmtTime(ts) { try { return new Date(ts).toLocaleString('ko-KR', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }); } catch { return ''; } }
  function fmtViews(n) { n = +n || 0; return n >= 10000 ? (n / 10000).toFixed(1) + '만' : n.toLocaleString(); }
  function statusKo(s) { return { posted: '게시됨', failed: '실패', posting: '게시 중' }[s] || s; }

  onMount(async () => {
    try { s = await api('/yt/stats'); } catch (e) { err = e.message; }
    try { vids = await api('/yt/extracted?limit=6'); } catch (e) { /* */ }
  });
</script>

<svelte:head><title>대시보드 — 댓글 에이전트</title></svelte:head>

<div class="ph">
  <div><h1>대시보드</h1><p class="sub">한눈에 보는 활동 현황</p></div>
  <div class="links">
    <a class="btn sm" href="/admin/yt">영상 불러오기</a>
    <a class="btn primary sm" href="/admin/yt/comments">영상 선택</a>
  </div>
</div>

{#if err}<p class="banner err">{err}</p>{/if}

{#if !s}
  <div class="kpis">{#each Array(4) as _}<div class="kskel"></div>{/each}</div>
{:else}
  <div class="kpis">
    <div class="kpi">
      <div class="ktext">
        <div class="knum">{s.extracted}</div>
        <div class="klabel">추출한 영상</div>
      </div>
      <div class="kicon vid"><i class="fi-rr-film"></i></div>
    </div>
    <div class="kpi">
      <div class="ktext">
        <div class="knum">{s.posted}</div>
        <div class="klabel">게시한 댓글</div>
      </div>
      <div class="kicon cmt"><i class="fi-rr-comment-dots"></i></div>
    </div>
    <div class="kpi">
      <div class="ktext">
        <div class="knum">{s.today}<span class="kmax">/{s.daily_max}</span></div>
        <div class="klabel">오늘 게시 (하루 상한)</div>
      </div>
      <div class="kicon day"><i class="fi-rr-calendar"></i></div>
    </div>
    <div class="kpi">
      <div class="ktext">
        <div class="knum">{s.failed}</div>
        <div class="klabel">게시 실패</div>
      </div>
      <div class="kicon {s.failed ? 'fail' : 'ok'}"><i class="fi-rr-{s.failed ? 'triangle-warning' : 'check'}"></i></div>
    </div>
  </div>

  <div class="cols">
    <section class="card">
      <div class="ch"><h3>최근 추출한 영상</h3><a class="more" href="/admin/yt/comments">전체 보기 →</a></div>
      {#if !vids.length}
        <p class="empty"><a href="/admin/yt">영상 불러오기</a>에서 영상을 추출해보세요.</p>
      {:else}
        <div class="vgrid">
          {#each vids as v (v.id)}
            <a class="vcard" href={'/admin/yt/comments/' + v.id}>
              <div class="vthumb"><img src={v.thumb} alt="" loading="lazy" /><span class="vbadge {v.posted ? 'done' : ''}">{v.posted ? '게시됨' : '미게시'}</span></div>
              <div class="vtitle">{v.title}</div>
              <div class="vsub">{v.channel_title} · 조회 {fmtViews(v.view_count)}</div>
              {#if v.analysis?.comment}<div class="vcmt"><span>{v.analysis.comment}</span></div>{/if}
            </a>
          {/each}
        </div>
      {/if}
    </section>

    <section class="card side">
      <div class="ch"><h3>최근 활동</h3><a class="more" href="/admin/yt/posted">작성한 댓글 →</a></div>
      {#if !s.recent.length}
        <p class="empty">아직 게시 기록이 없어요. <a href="/admin/yt">영상 불러오기</a>에서 시작하세요.</p>
      {:else}
        <div class="feed">
          {#each s.recent.slice(0, 4) as l}
            <div class="frow">
              <div class="fhead">
                <span class="fstatus {l.success ? 'ok' : l.success === false ? 'bad' : ''}">{statusKo(l.status)}</span>
                <span class="ftitle">{l.video_title || '영상'}</span>
                <span class="fmeta">{fmtTime(l.created_at)}{#if l.comment_link} · <a href={l.comment_link} target="_blank" rel="noopener">보기↗</a>{/if}</span>
              </div>
              <div class="ftext">{l.body}</div>
            </div>
          {/each}
        </div>
      {/if}
    </section>
  </div>
{/if}

<style>
  .ph { display:flex; justify-content:space-between; align-items:flex-start; gap:12px; flex-wrap:wrap; }
  .ph h1 { margin:0; font-size:22px; } .sub { margin:4px 0 0; color:var(--muted); font-size:13px; }
  .links { display:flex; gap:8px; }
  .banner { padding:10px 13px; border-radius:10px; font-size:13.5px; margin-top:12px; } .banner.err { background:#fde8e8; color:#b42318; }

  .kpis { display:grid; grid-template-columns:repeat(4, 1fr); gap:14px; margin-top:18px; }
  @media(max-width:760px){ .kpis { grid-template-columns:repeat(2, 1fr); } }
  .kpi { background:var(--surface); border:1px solid var(--line); border-radius:14px; padding:18px; display:flex; align-items:center; justify-content:space-between; gap:12px; }
  .ktext { min-width:0; }
  .kicon { flex:none; width:52px; display:flex; align-items:center; justify-content:center; font-size:38px; background:transparent; color:var(--muted); }
  .kicon i { line-height:1; }
  /* 배경 박스 없이 아이콘 색상만(보라 제거) */
  .kicon.vid { color:#60a5fa; }
  .kicon.cmt { color:#34d399; }
  .kicon.day { color:#fbbf24; }
  .kicon.ok { color:#34d399; }
  .kicon.fail { color:#f87171; }
  .knum { font-size:30px; font-weight:800; line-height:1; } .kmax { font-size:16px; color:var(--muted); font-weight:600; }
  .klabel { font-size:12.5px; color:var(--muted); margin-top:7px; }
  .kskel { height:120px; border-radius:14px; background:linear-gradient(90deg,var(--line),var(--bg),var(--line)); background-size:200% 100%; animation:sh 1.2s infinite; }
  @keyframes sh { 0%{background-position:200% 0} 100%{background-position:-200% 0} }

  .cols { display:grid; grid-template-columns:2fr 1fr; gap:14px; margin-top:16px; }
  @media(max-width:860px){ .cols { grid-template-columns:1fr; } }
  .card { background:var(--surface); border:1px solid var(--line); border-radius:14px; padding:18px; min-width:0; }
  .card.wide { margin-top:14px; }
  .ch { display:flex; justify-content:space-between; align-items:baseline; margin-bottom:14px; }
  .card h3 { margin:0; font-size:15px; } .more { font-size:12.5px; color:var(--accent); font-weight:700; }
  .empty { color:var(--muted); font-size:13px; text-align:center; padding:28px 0; } .empty a { color:var(--accent); }

  /* 최근 추출한 영상 썸네일 */
  .vgrid { display:grid; grid-template-columns:repeat(3, 1fr); gap:14px; }
  @media(max-width:1100px){ .vgrid { grid-template-columns:repeat(2, 1fr); } }
  @media(max-width:560px){ .vgrid { grid-template-columns:1fr; } }
  .vcard { display:block; text-decoration:none; color:inherit; }
  .vthumb { position:relative; border-radius:10px; overflow:hidden; } .vthumb img { width:100%; aspect-ratio:16/9; object-fit:cover; background:var(--line); display:block; transition:transform .35s ease; }
  .vcard:hover .vthumb img { transform:scale(1.06); }
  .vbadge { position:absolute; top:7px; left:7px; font-size:10.5px; font-weight:700; padding:2px 7px; border-radius:999px; background:var(--surface-alt); color:var(--muted); }
  .vbadge.done { background:#13794a; color:#fff; }
  .vtitle { font-size:13.5px; font-weight:700; line-height:1.4; margin-top:9px; display:-webkit-box; -webkit-line-clamp:2; line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
  .vsub { font-size:11.5px; color:var(--muted); margin-top:4px; }
  .vcmt { font-size:12px; color:var(--muted); line-height:1.5; margin-top:7px; background:var(--bg); border:1px solid var(--line); border-radius:8px; padding:8px 10px; }
  .vcmt span { display:-webkit-box; -webkit-line-clamp:2; line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }

  .feed { display:flex; flex-direction:column; gap:8px; }
  .frow { display:flex; flex-direction:column; gap:7px; padding:13px 14px; border:1px solid var(--line); border-radius:11px; }
  .fhead { display:flex; align-items:center; gap:8px; }
  .fstatus { font-size:11px; font-weight:700; padding:3px 9px; border-radius:999px; background:var(--badge-bg); color:var(--muted); flex:none; }
  .fstatus.ok { background:#e4f5ec; color:#13794a; } .fstatus.bad { background:#fde8e8; color:#b42318; }
  :global(html[data-appearance="dark"]) .fstatus { background:rgba(255,255,255,.08); color:#cdd3de; }
  :global(html[data-appearance="dark"]) .fstatus.ok { background:rgba(29,185,84,.22); color:#4ee08a; }
  :global(html[data-appearance="dark"]) .fstatus.bad { background:rgba(240,72,60,.22); color:#ff9a90; }
  .ftitle { font-size:12.5px; color:var(--muted); flex:1; min-width:0; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .fmeta { font-size:11.5px; color:var(--muted); flex:none; white-space:nowrap; } .fmeta a { color:var(--accent); }
  .ftext { font-size:14px; line-height:1.65; overflow-wrap:anywhere; }
  @media(max-width:560px){ .ftext { font-size:14.5px; } .fmeta { font-size:11px; } }
</style>
