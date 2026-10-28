<script>
  import "../app.css";
  import { page } from '$app/state';
  import { apply } from '$lib/theme.js';
  let { children } = $props();
  // 관리자/인증=저장된 테마(라이트/다크/시스템). 공개 랜딩=자체 다크 디자인(브랜드 톤 고정).
  $effect(() => {
    const p = page.url.pathname;
    const isApp = p.startsWith('/admin') || p.startsWith('/auth');
    try {
      if (isApp) { apply(); document.body.style.background = ''; }
      else { document.documentElement.dataset.appearance = 'light'; document.body.style.background = '#0b0d28'; }
    } catch (e) { /* */ }
  });
</script>

{@render children()}
