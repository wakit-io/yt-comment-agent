<script>
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';
  import { session, saveSession, api } from '$lib/client.js';
  import ThemeToggle from '$lib/ThemeToggle.svelte';
  import { t } from '$lib/i18n/index.svelte.js';
  let { children } = $props();

  let ready = $state(false);
  let signed = $state(false);
  let navOpen = $state(false);
  const p = $derived(page.url.pathname);
  const isLogin = $derived(p === '/admin/login');

  // 라우트가 바뀔 때마다 세션 재확인 → 로그인 후 바로 반영.
  $effect(() => {
    const onLogin = isLogin;
    signed = !!session();
    ready = true;
    if (!signed && !onLogin) goto('/admin/login');
  });

  function logout() { saveSession(null); goto('/admin/login'); }

  // ── 헤더 YouTube 계정 칩 + 전환 모달 ──
  let acct = $state({ loaded: false, configured: false, connected: false, channel_title: '' });
  let acctModal = $state(false);
  let connecting = $state(false); let disconnecting = $state(false);
  async function loadAcct() { try { acct = { ...acct, ...(await api('/yt/oauth/status')), loaded: true }; } catch (e) { acct = { ...acct, loaded: true }; } }
  async function connectAcct() { connecting = true; try { const { url } = await api('/yt/oauth/url'); window.location.href = url; } catch (e) { connecting = false; } }
  async function disconnectAcct() { if (!confirm('연결을 해제할까요? 다시 연결하기 전에는 게시가 안 됩니다.')) return; disconnecting = true; try { await api('/yt/oauth/disconnect', 'POST', {}); await loadAcct(); } catch (e) { /* */ } disconnecting = false; }

  // 사이드바 접기(아이콘만) — 상태 저장.
  let collapsed = $state(false);
  function toggleCollapse() { collapsed = !collapsed; try { localStorage.setItem('fl-nav-collapsed', collapsed ? '1' : '0'); } catch (e) { /* */ } }

  // 맨 위로 버튼(스크롤 시 노출)
  let showTop = $state(false);
  onMount(() => {
    try { collapsed = localStorage.getItem('fl-nav-collapsed') === '1'; } catch (e) { /* */ }
    if (session()) { loadAcct(); }
    const onScroll = () => { showTop = window.scrollY > 400; };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    return () => window.removeEventListener('scroll', onScroll);
  });

  // [경로, i18n 키, 아이콘]
  const NAV = [
    ['/admin', 'nav.dashboard', 'fi-rr-dashboard'],
    ['/admin/yt', 'nav.yt', 'fi-rr-search'],
    ['/admin/yt/comments', 'nav.ytc', 'fi-rr-film'],
    ['/admin/yt/posted', 'nav.posted', 'fi-rr-comment-dots'],
    ['/admin/consults', 'nav.consults', 'fi-rr-inbox'],
    ['/admin/settings', 'nav.settings', 'fi-rr-settings']
  ];
  // /admin, /admin/yt 는 하위가 별도 메뉴라 정확일치만(중복 활성 방지).
  const EXACT = ['/admin', '/admin/yt'];
  const on = (href) => EXACT.includes(href) ? p === href : p === href || p.startsWith(href + '/');
</script>

{#if isLogin}
  {@render children()}
{:else if ready && signed}
  <div class="aw">
    <aside class="side" class:open={navOpen} class:collapsed>
      <div class="side-head">
        <button class="collapse-btn" onclick={toggleCollapse} aria-label="메뉴 접기/펼치기" title="메뉴 접기/펼치기"><i class="fi-rr-menu-burger"></i></button>
        <a class="logo" href="/admin">
          <span class="bname">댓글 에이전트</span>
        </a>
      </div>
      <nav>
        {#each NAV as [href, key, icon]}
          <a {href} class:on={on(href)} onclick={() => navOpen = false} data-tip={t(key)} aria-label={t(key)}><i class={icon}></i><span class="nav-label">{t(key)}</span></a>
        {/each}
      </nav>
      <div class="side-foot">
        <a href="/" target="_blank" data-tip={t('layout.publicSite')} aria-label={t('layout.publicSite')}><i class="fi-rr-link-alt"></i><span class="nav-label">{t('layout.publicSite')}</span></a>
        <button onclick={logout} data-tip={t('layout.logout')} aria-label={t('layout.logout')}><i class="fi-rr-sign-out-alt"></i><span class="nav-label">{t('layout.logout')}</span></button>
      </div>
    </aside>
    <div class="side-bd" class:open={navOpen} onclick={() => navOpen = false} aria-hidden="true"></div>
    <main class="main">
      <header class="top">
        <button class="burger" onclick={() => navOpen = !navOpen}><i class="fi-rr-menu-burger"></i></button>
        <div class="top-sp"></div>
        {#if acct.loaded}
          <button class="acct-chip" onclick={() => acctModal = true} title="YouTube 계정">
            <span class="adot" class:off={!acct.connected}></span>
            <span class="aname">{acct.connected ? acct.channel_title : '계정 연결'}</span>
            <i class="fi-rr-angle-small-down"></i>
          </button>
        {/if}
        <ThemeToggle />
      </header>
      <div class="content">{@render children()}</div>
    </main>
  </div>

  {#if acctModal}
    <div class="amodal-back" role="presentation" onclick={() => acctModal = false}>
      <div class="amodal" role="dialog" aria-modal="true" aria-label="YouTube 계정" onclick={(e) => e.stopPropagation()}>
        <div class="amhead"><span class="amtitle"><i class="fi-rr-settings-sliders"></i> YouTube 계정</span><button class="amclose" onclick={() => acctModal = false} aria-label="닫기"><i class="fi-rr-cross-small"></i></button></div>
        {#if !acct.configured}
          <p class="amwarn"><i class="fi-rr-triangle-warning"></i> OAuth 미설정 — <code>.env</code>에 GOOGLE_CLIENT_ID/SECRET 를 넣고 서버를 재시작하세요.</p>
        {:else if acct.connected}
          <div class="amcur"><span class="adot"></span><div><div class="amname">{acct.channel_title}</div><div class="amsub">연결됨 · 이 계정으로 게시돼요</div></div></div>
          <p class="amdesc">다른 유튜브 계정으로 바꾸려면 아래에서 다시 연결하세요. 연결을 해제하면 게시가 중단됩니다.</p>
          <div class="ambtns">
            <button class="btn" onclick={disconnectAcct} disabled={disconnecting}>{disconnecting ? '해제 중…' : '연결 해제'}</button>
            <button class="btn primary" onclick={connectAcct} disabled={connecting}>{connecting ? '여는 중…' : '다른 계정으로 연결'}</button>
          </div>
        {:else}
          <p class="amdesc">댓글을 게시할 본인(브랜드) 유튜브 계정을 연결하세요.</p>
          <div class="ambtns">
            <button class="btn" onclick={() => acctModal = false}>닫기</button>
            <button class="btn primary" onclick={connectAcct} disabled={connecting}>{connecting ? '여는 중…' : 'YouTube 계정 연결'}</button>
          </div>
        {/if}
      </div>
    </div>
  {/if}

  {#if showTop}
    <button class="totop" onclick={() => window.scrollTo({ top: 0, behavior: 'smooth' })} aria-label="맨 위로" title="맨 위로"><i class="fi-rr-angle-up"></i></button>
  {/if}
{:else}
  <div class="loading">{t('layout.loading')}</div>
{/if}

<style>
  :global(body){ background:var(--bg); color:var(--ink); }
  .loading{ padding:80px; text-align:center; color:var(--muted); }
  .aw{ display:grid; grid-template-columns:230px 1fr; min-height:100vh; transition:grid-template-columns .18s ease; }
  @media(min-width:861px){ .aw:has(.side.collapsed){ grid-template-columns:66px 1fr; } }
  .side{ background:var(--surface); border-right:1px solid var(--line); display:flex; flex-direction:column; position:sticky; top:0; height:100vh; overflow:hidden; }
  .side-head{ display:flex; align-items:center; gap:4px; padding:14px 14px 10px; }
  .collapse-btn{ flex:none; width:34px; height:34px; border:0; background:none; color:var(--ink); font-size:17px; border-radius:8px; cursor:pointer; display:flex; align-items:center; justify-content:center; }
  .collapse-btn:hover{ background:var(--surface-alt); }
  .logo{ display:block; text-decoration:none; min-width:0; overflow:hidden; }
  .logo .bname{ display:block; font-size:16.5px; font-weight:850; color:var(--ink); letter-spacing:-.4px; line-height:1.2; white-space:nowrap; }
  .side nav{ flex:1; padding:6px 10px; display:flex; flex-direction:column; gap:2px; overflow-y:auto; overflow-x:hidden; }
  .side nav a{ display:flex; align-items:center; gap:11px; padding:10px 12px; border-radius:9px; color:var(--ink); font-weight:600; font-size:14.5px; white-space:nowrap; }
  .side nav a i{ color:var(--muted); font-size:16px; width:20px; flex:none; text-align:center; }
  .side nav a:hover{ background:var(--surface-alt); }
  .side nav a.on{ background:var(--surface-alt); color:var(--ink); font-weight:800; }
  .side nav a.on i{ color:var(--accent); }
  .side-foot{ border-top:1px solid var(--line); padding:14px 18px; display:flex; flex-direction:column; gap:10px; }
  .side-foot a{ color:var(--muted); font-size:13px; display:flex; align-items:center; gap:9px; white-space:nowrap; }
  .side-foot a i{ font-size:15px; width:18px; flex:none; text-align:center; }
  .side-foot button{ background:var(--surface-alt); color:var(--ink); border:1px solid var(--line); border-radius:8px; padding:8px; font-weight:600; cursor:pointer; font-size:13px; display:flex; align-items:center; justify-content:center; gap:8px; }
  .side-foot button i{ font-size:15px; }
  /* 접힌 상태: 아이콘만 (데스크탑 전용 — 모바일은 슬라이드인 그대로) */
  @media(min-width:861px){
    .side.collapsed .logo, .side.collapsed .nav-label{ display:none; }
    .side.collapsed .side-head{ justify-content:center; padding:14px 0 10px; }
    .side.collapsed nav{ padding:6px 8px; }
    .side.collapsed nav a{ justify-content:center; padding:10px 0; gap:0; }
    .side.collapsed .side-foot{ padding:14px 10px; }
    .side.collapsed .side-foot a{ justify-content:center; }
    .side.collapsed .side-foot button{ padding:8px 0; }
    /* 접힘 상태: 아이콘 호버 시 툴팁 박스(사이드바 밖으로 나오게 overflow 허용) */
    /* z-index로 헤더(.top=20)·본문 위로 떠서 툴팁이 안 잘리게 */
    .side.collapsed{ z-index:40; }
    .side.collapsed, .side.collapsed nav, .side.collapsed .side-foot{ overflow:visible; }
    .side.collapsed nav a, .side.collapsed .side-foot a, .side.collapsed .side-foot button{ position:relative; }
    .side.collapsed nav a::after, .side.collapsed .side-foot a::after, .side.collapsed .side-foot button::after{
      content:attr(data-tip); position:absolute; left:calc(100% + 12px); top:50%; transform:translateY(-50%) scale(.96);
      background:var(--ink); color:var(--bg); white-space:nowrap; padding:7px 11px; border-radius:8px;
      font-size:12.5px; font-weight:700; line-height:1; letter-spacing:-.2px;
      opacity:0; pointer-events:none; transition:opacity .12s, transform .12s; z-index:100; box-shadow:0 6px 18px rgba(0,0,0,.28);
    }
    .side.collapsed nav a:hover::after, .side.collapsed .side-foot a:hover::after, .side.collapsed .side-foot button:hover::after{ opacity:1; transform:translateY(-50%) scale(1); }
  }
  .main{ min-width:0; }
  .top{ height:56px; display:flex; align-items:center; gap:10px; padding:0 18px; border-bottom:1px solid var(--line); background:var(--surface); position:sticky; top:0; z-index:20; }
  .top-sp{ flex:1; }
  .burger{ display:none; background:none; border:0; font-size:19px; color:var(--ink); cursor:pointer; }
  /* 헤더 계정 칩 */
  .acct-chip{ display:inline-flex; align-items:center; gap:7px; background:var(--surface-alt); border:1px solid var(--line); border-radius:999px; padding:5px 10px 5px 11px; cursor:pointer; color:var(--ink); font:inherit; max-width:230px; }
  .acct-chip:hover{ border-color:var(--accent); }
  .acct-chip .aname{ font-size:13px; font-weight:700; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .acct-chip i{ color:var(--muted); font-size:14px; }
  .adot{ width:8px; height:8px; border-radius:50%; background:#1db954; box-shadow:0 0 0 3px rgba(29,185,84,.18); flex:none; }
  .adot.off{ background:#b0b0b0; box-shadow:0 0 0 3px rgba(160,160,160,.15); }
  /* 계정 모달 */
  .amodal-back{ position:fixed; inset:0; background:rgba(0,0,0,.6); backdrop-filter:blur(5px); -webkit-backdrop-filter:blur(5px); display:flex; align-items:center; justify-content:center; padding:18px; z-index:80; }
  .amodal{ background:var(--surface); border:1px solid var(--line); border-radius:16px; padding:20px; max-width:400px; width:100%; box-shadow:0 24px 70px rgba(0,0,0,.5); }
  .amhead{ font-size:16px; font-weight:800; display:flex; align-items:center; justify-content:space-between; gap:8px; }
  .amtitle{ display:flex; align-items:center; gap:8px; }
  .amtitle i{ color:var(--accent); }
  .amclose{ flex:none; width:30px; height:30px; border-radius:8px; border:0; background:transparent; color:var(--muted); cursor:pointer; display:flex; align-items:center; justify-content:center; font-size:18px; }
  .amclose:hover{ background:var(--surface-alt); color:var(--ink); }
  .amcur{ display:flex; align-items:center; gap:11px; margin-top:14px; padding:12px 14px; border:1px solid var(--line); border-radius:11px; background:var(--surface); }
  .amname{ font-size:14px; font-weight:800; } .amsub{ font-size:12px; color:var(--muted); margin-top:1px; }
  .amdesc{ font-size:13px; color:var(--muted); line-height:1.6; margin:12px 0 0; }
  .amwarn{ font-size:13px; color:#8a5a00; background:#fdf0d5; padding:10px 12px; border-radius:9px; margin-top:12px; display:flex; align-items:center; gap:7px; }
  .amwarn code{ background:rgba(0,0,0,.08); padding:1px 6px; border-radius:5px; }
  .ambtns{ display:flex; justify-content:flex-end; gap:8px; margin-top:18px; }
  /* 맨 위로 버튼 */
  .totop{ position:fixed; right:24px; bottom:24px; z-index:70; width:46px; height:46px; border-radius:50%; border:1px solid var(--line); background:var(--surface); color:var(--ink); cursor:pointer; display:flex; align-items:center; justify-content:center; font-size:19px; box-shadow:0 6px 22px rgba(0,0,0,.28); transition:border-color .12s, transform .12s; }
  .totop:hover{ border-color:var(--accent); transform:translateY(-2px); }
  .content{ padding:26px; width:100%; box-sizing:border-box; }
  .side-bd{ display:none; }
  @media(max-width:860px){
    .aw{ grid-template-columns:1fr; }
    .side{ position:fixed; left:0; top:0; bottom:0; width:240px; z-index:60; transform:translateX(-100%); transition:transform .2s; }
    .side.open{ transform:none; }
    .side-bd.open{ display:block; position:fixed; inset:0; background:#0006; z-index:55; }
    .burger{ display:block; }
    .content{ padding:18px; }
  }
</style>
