<script>
  // 상담 신청 — 공개 랜딩의 상담 폼으로 들어온 신청 내역(시연용 샘플).
  //  ⚠️ 데모: 실제 저장 없음. 아래는 "이런 화면이 있다"를 보여주기 위한 예시 데이터.
  const STATUS = { new: '신규', contacted: '연락완료', done: '상담완료' };

  // 샘플 신청 내역
  let rows = $state([
    { id: 1, name: '김서연', phone: '010-2841-7792', topic: '재회운', birth: '1995-03-12', btime: '사시(09~11)', story: '3개월 전에 헤어진 사람이 자꾸 생각나요. 다시 만날 인연이 있는지, 지금 연락해도 될 타이밍인지 궁금해요.', created_at: '2026-10-28T09:12:00', status: 'new' },
    { id: 2, name: '이도현', phone: '010-5537-2210', topic: '궁합 보기', birth: '1992-11-08', btime: '모름', story: '지금 만나는 사람이랑 결혼까지 생각 중인데, 둘 궁합이 어떤지 봐주실 수 있나요?', created_at: '2026-10-28T08:40:00', status: 'new' },
    { id: 3, name: '박지우', phone: '010-9921-4408', topic: '연애운 흐름', birth: '1998-06-24', btime: '자시(23~01)', story: '요즘 들어오는 인연이 하나도 없어요. 제 연애운 흐름이 지금 어느 시기인지 알고 싶어요.', created_at: '2026-10-27T21:05:00', status: 'contacted' },
    { id: 4, name: '최민재', phone: '010-3312-8876', topic: '인연의 때(택일)', birth: '1990-01-30', btime: '오시(11~13)', story: '소개팅을 언제쯤 잡는 게 좋을지, 좋은 인연이 들어오는 때가 궁금합니다.', created_at: '2026-10-27T15:48:00', status: 'contacted' },
    { id: 5, name: '정하늘', phone: '010-7745-1123', topic: '기타 고민', birth: '1996-09-17', btime: '유시(17~19)', story: '짝사랑만 몇 년째예요… 고백해도 될지, 아니면 접는 게 맞는지 흐름을 봐주세요.', created_at: '2026-10-27T11:20:00', status: 'done' },
    { id: 6, name: '한예린', phone: '010-2206-5540', topic: '궁합 보기', birth: '1993-04-02', btime: '진시(07~09)', story: '친구 소개로 만난 사람인데 자꾸 엇갈려요. 저희가 잘 맞는 사이인지 확인하고 싶어요.', created_at: '2026-10-26T19:33:00', status: 'done' },
    { id: 7, name: '오태윤', phone: '010-6698-3312', topic: '연애운 흐름', birth: '1994-12-11', btime: '모름', story: '올해 연애운이 어떤지, 하반기에 좋은 흐름이 오는지 궁금합니다.', created_at: '2026-10-26T10:02:00', status: 'done' },
    { id: 8, name: '윤소민', phone: '010-4417-9980', topic: '재회운', birth: '1997-08-05', btime: '해시(21~23)', story: '먼저 이별을 말한 건 저인데 자꾸 후회돼요. 다시 돌아갈 수 있는 흐름인지 봐주세요.', created_at: '2026-10-25T22:14:00', status: 'done' },
  ]);

  let filter = $state('all'); // all | new | contacted | done
  let sel = $state(null);     // 상세 모달 대상

  const total = $derived(rows.length);
  const todayN = $derived(rows.filter((r) => isToday(r.created_at)).length);
  const newN = $derived(rows.filter((r) => r.status === 'new').length);
  const doneN = $derived(rows.filter((r) => r.status === 'done').length);
  const shown = $derived(filter === 'all' ? rows : rows.filter((r) => r.status === filter));

  function mask(name) { const n = (name || '').trim(); return n.length <= 1 ? n : n[0] + '*'.repeat(n.length - 1); }
  function isToday(ts) { try { return new Date(ts).toDateString() === new Date().toDateString(); } catch { return false; } }
  function fmtDate(ts) { try { return new Date(ts).toLocaleString('ko-KR', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }); } catch { return ''; } }
  function setStatus(s) { if (!sel) return; const r = rows.find((x) => x.id === sel.id); if (r) { r.status = s; rows = [...rows]; sel = { ...sel, status: s }; } }
</script>

<svelte:head><title>상담 신청 — 댓글 에이전트</title></svelte:head>

<div class="ph">
  <div><h1>상담 신청</h1><p class="sub">공개 랜딩의 상담 신청 폼으로 들어온 신청 내역이에요.</p></div>
</div>

<p class="demo"><i class="fi-rr-info"></i> 심사용 데모 화면이에요. 실제 신청은 저장되지 않으며, 아래는 예시 데이터입니다.</p>

<div class="kpis">
  <button class="kpi" class:on={filter === 'all'} onclick={() => filter = 'all'}><b>{total}</b><span>전체</span></button>
  <button class="kpi" class:on={filter === 'new'} onclick={() => filter = 'new'}><b>{newN}</b><span>신규</span></button>
  <button class="kpi" onclick={() => filter = 'all'}><b>{todayN}</b><span>오늘 접수</span></button>
  <button class="kpi" class:on={filter === 'done'} onclick={() => filter = 'done'}><b>{doneN}</b><span>상담완료</span></button>
</div>

<div class="list">
  {#if !shown.length}<p class="empty">해당 조건의 신청이 없어요.</p>{/if}
  {#each shown as r (r.id)}
    <button class="row" onclick={() => sel = r}>
      <span class="ava" aria-hidden="true">{r.name[0]}</span>
      <div class="rmain">
        <div class="rtop">
          <span class="st {r.status}">{STATUS[r.status]}</span>
          <b class="name">{mask(r.name)}</b>
          <span class="topic">{r.topic}</span>
        </div>
        <p class="story">{r.story}</p>
      </div>
      <div class="rmeta">
        <span class="phone">{r.phone}</span>
        <span class="date">{fmtDate(r.created_at)}</span>
      </div>
      <i class="fi-rr-angle-right go"></i>
    </button>
  {/each}
</div>

{#if sel}
  <div class="back" role="presentation" onclick={() => sel = null}>
    <div class="modal" role="dialog" aria-modal="true" onclick={(e) => e.stopPropagation()}>
      <div class="mhead">
        <span class="mtitle"><i class="fi-rr-user"></i> {mask(sel.name)}</span>
        <button class="mx" onclick={() => sel = null} aria-label="닫기"><i class="fi-rr-cross-small"></i></button>
      </div>
      <div class="mstatus"><span class="st {sel.status}">{STATUS[sel.status]}</span><span class="mdate">{fmtDate(sel.created_at)} 접수</span></div>

      <dl class="info">
        <div><dt>연락처</dt><dd>{sel.phone}</dd></div>
        <div><dt>상담 유형</dt><dd>{sel.topic}</dd></div>
        <div><dt>생년월일</dt><dd>{sel.birth}{sel.btime !== '모름' ? ` · ${sel.btime}` : ''}</dd></div>
      </dl>
      <div class="storybox"><span class="lbl">사연</span>{sel.story}</div>

      <div class="actions">
        <span class="albl">상태 변경</span>
        <div class="sbtns">
          {#each Object.entries(STATUS) as [k, label]}
            <button class="sbtn {k}" class:on={sel.status === k} onclick={() => setStatus(k)}>{label}</button>
          {/each}
        </div>
      </div>
      <p class="dnote">※ 데모라 상태 변경은 이 화면에서만 반영됩니다.</p>
    </div>
  </div>
{/if}

<style>
  .ph { display:flex; justify-content:space-between; align-items:flex-start; gap:12px; flex-wrap:wrap; }
  .ph h1 { margin:0; font-size:22px; } .sub { margin:4px 0 0; color:var(--muted); font-size:13px; }
  .demo { display:flex; align-items:center; gap:7px; margin:14px 0 0; font-size:12.5px; color:#b9770b; background:#fff4e0; border:1px solid #f3d9a6; padding:9px 13px; border-radius:10px; }
  :global(html[data-appearance="dark"]) .demo { background:rgba(255,180,60,.1); border-color:rgba(255,180,60,.28); color:#f0b650; }

  .kpis { display:grid; grid-template-columns:repeat(4, 1fr); gap:12px; margin-top:16px; }
  @media(max-width:620px){ .kpis{ grid-template-columns:repeat(2,1fr); } }
  .kpi { background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:14px 16px; text-align:left; cursor:pointer; display:flex; flex-direction:column; gap:2px; }
  .kpi:hover { border-color:var(--accent); } .kpi.on { border-color:var(--accent); box-shadow:0 0 0 1px var(--accent) inset; }
  .kpi b { font-size:22px; font-weight:850; color:var(--ink); } .kpi span { font-size:12.5px; color:var(--muted); }

  .list { margin-top:16px; display:flex; flex-direction:column; gap:10px; }
  .empty { color:var(--muted); font-size:13px; text-align:center; padding:40px 0; }
  .row { display:grid; grid-template-columns:auto 1fr auto auto; align-items:center; gap:15px; width:100%; text-align:left; cursor:pointer;
    background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:15px 18px; transition:border-color .12s, background .12s; }
  .row:hover { border-color:var(--accent); background:var(--surface-alt); }
  .ava { flex:none; width:40px; height:40px; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:17px; font-weight:800; color:var(--accent); background:rgba(230,33,23,.1); }
  :global(html[data-appearance="dark"]) .ava { background:rgba(255,77,66,.14); }
  .rmain { min-width:0; }
  .rtop { display:flex; align-items:center; gap:9px; flex-wrap:wrap; }
  .st { font-size:11px; font-weight:800; padding:3px 10px; border-radius:999px; flex:none; white-space:nowrap; }
  .st.new { background:rgba(230,33,23,.12); color:var(--accent); }
  .st.contacted { background:rgba(59,130,246,.14); color:#3b82f6; }
  .st.done { background:rgba(29,185,84,.16); color:#13794a; }
  :global(html[data-appearance="dark"]) .st.done { color:#4ee08a; }
  .name { font-size:15.5px; font-weight:800; color:var(--ink); letter-spacing:.02em; }
  .topic { color:var(--muted); font-size:12px; font-weight:700; background:var(--badge-bg); padding:2px 9px; border-radius:999px; }
  .story { color:var(--muted); font-size:13px; margin:6px 0 0; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .rmeta { display:flex; flex-direction:column; align-items:flex-end; gap:3px; white-space:nowrap; }
  .phone { font-size:13px; font-weight:700; color:var(--ink); } .date { font-size:11.5px; color:var(--muted); }
  .go { color:var(--muted); font-size:13px; }
  @media(max-width:720px){
    .row { grid-template-columns:auto 1fr auto; }
    .rmeta { grid-column:1 / -1; flex-direction:row; justify-content:flex-start; gap:8px; align-items:baseline; margin-top:2px; }
    .go { display:none; }
  }

  .back { position:fixed; inset:0; background:rgba(0,0,0,.6); backdrop-filter:blur(5px); -webkit-backdrop-filter:blur(5px); display:flex; align-items:center; justify-content:center; padding:18px; z-index:80; }
  .modal { background:var(--surface); border:1px solid var(--line); border-radius:16px; padding:22px; max-width:460px; width:100%; box-shadow:0 24px 70px rgba(0,0,0,.5); }
  .mhead { display:flex; align-items:center; justify-content:space-between; gap:8px; }
  .mtitle { font-size:18px; font-weight:800; display:inline-flex; align-items:center; gap:8px; } .mtitle i { color:var(--accent); }
  .mx { width:30px; height:30px; border:0; background:transparent; color:var(--muted); border-radius:8px; cursor:pointer; display:flex; align-items:center; justify-content:center; font-size:18px; }
  .mx:hover { background:var(--badge-bg); color:var(--ink); }
  .mstatus { display:flex; align-items:center; gap:10px; margin:12px 0 16px; } .mdate { font-size:12.5px; color:var(--muted); }
  .info { display:flex; flex-direction:column; gap:0; margin:0 0 14px; border:1px solid var(--line); border-radius:11px; overflow:hidden; }
  .info div { display:flex; justify-content:space-between; gap:12px; padding:11px 14px; font-size:13.5px; border-top:1px solid var(--line); } .info div:first-child { border-top:0; }
  .info dt { color:var(--muted); margin:0; } .info dd { margin:0; font-weight:700; text-align:right; }
  .storybox { background:var(--bg); border:1px solid var(--line); border-radius:11px; padding:13px 15px; font-size:14px; line-height:1.75; }
  .storybox .lbl { display:block; font-size:11px; font-weight:700; color:var(--muted); margin-bottom:6px; }
  .actions { margin-top:16px; } .albl { font-size:12px; font-weight:700; color:var(--muted); }
  .sbtns { display:flex; gap:8px; margin-top:8px; }
  .sbtn { flex:1; padding:9px; border:1px solid var(--line); background:var(--bg); color:var(--muted); border-radius:9px; font:inherit; font-size:13px; font-weight:700; cursor:pointer; }
  .sbtn:hover { border-color:var(--accent); }
  .sbtn.on.new { background:var(--accent); border-color:var(--accent); color:var(--accent-fg); }
  .sbtn.on.contacted { background:#3b82f6; border-color:#3b82f6; color:#fff; }
  .sbtn.on.done { background:#13794a; border-color:#13794a; color:#fff; }
  .dnote { font-size:11.5px; color:var(--muted); margin:12px 0 0; }
</style>
