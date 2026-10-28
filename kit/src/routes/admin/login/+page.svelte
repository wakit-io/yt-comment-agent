<script>
  import { api, saveSession } from '$lib/client.js';
  import { goto } from '$app/navigation';
  import { t } from '$lib/i18n/index.svelte.js';
  let email = $state(''), pw = $state(''), msg = $state(''), busy = $state(false);
  async function go(signup = false) {
    if (!email || !pw) { msg = '이메일·비밀번호를 입력하세요'; return; }
    busy = true; msg = '';
    try {
      const r = await api(signup ? '/auth/signup' : '/auth/login', 'POST', { email, password: pw });
      if (r.requires_confirmation) { msg = '확인 메일을 보냈어요. 인증 후 로그인하세요.'; return; }
      saveSession(r.session); goto('/admin');
    } catch (e) { msg = e.message; } finally { busy = false; }
  }
</script>
<svelte:head><title>{t('login.title')}</title></svelte:head>
<div class="lw">
  <form class="card" onsubmit={(e) => { e.preventDefault(); go(false); }}>
    <h1>{t('login.title')}</h1>
    <label>이메일<input bind:value={email} type="email" autocomplete="email" /></label>
    <label>비밀번호<input bind:value={pw} type="password" autocomplete="current-password" /></label>
    <div class="row"><button class="btn primary" type="submit" disabled={busy}>{t('login.signin')}</button><button class="btn" type="button" onclick={() => go(true)} disabled={busy}>{t('login.signup')}</button></div>
    {#if msg}<p class="msg">{msg}</p>{/if}
  </form>
</div>
<style>
  .lw{ min-height:100vh; display:flex; align-items:center; justify-content:center; background:var(--bg); padding:20px; }
  .card{ background:var(--surface); border:1px solid var(--line); border-radius:16px; padding:32px; width:100%; max-width:380px; }
  h1{ margin:0 0 4px; font-size:22px; }
  .muted{ color:var(--muted); margin:0 0 20px; font-size:14px; }
  label{ display:flex; flex-direction:column; gap:6px; font-weight:600; font-size:13px; margin-bottom:14px; }
  input{ padding:11px 12px; border:1px solid var(--line); border-radius:9px; background:var(--surface); color:var(--ink); font:inherit; }
  .row{ display:flex; gap:8px; margin-top:4px; }
  .btn{ flex:1; padding:11px; border-radius:9px; border:1px solid var(--line); background:var(--surface-alt); color:var(--ink); font-weight:700; cursor:pointer; }
  .btn.primary{ background:var(--button-bg); color:#fff; border-color:transparent; }
  .msg{ color:var(--muted); font-size:13px; margin:14px 0 0; }
</style>
