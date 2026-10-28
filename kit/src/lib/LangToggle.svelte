<script>
  import { onMount } from 'svelte';
  import { getLocale, setLocale, initLocale, LOCALES } from '$lib/i18n/index.svelte.js';
  onMount(initLocale);
  // 2개 이상이면 다음 로케일로 순환.
  function cycle() {
    const codes = LOCALES.map((l) => l.code);
    const next = codes[(codes.indexOf(getLocale()) + 1) % codes.length];
    setLocale(next);
  }
  const current = $derived(LOCALES.find((l) => l.code === getLocale()) || LOCALES[0]);
</script>
<button class="lt" onclick={cycle} title={'언어 / Language: ' + current.label + ' (클릭하여 전환)'} aria-label="언어 전환">
  {getLocale().toUpperCase()}
</button>
<style>
  .lt{ display:inline-flex; align-items:center; justify-content:center; min-width:36px; height:36px; padding:0 9px; border-radius:9px; border:1px solid var(--line); background:var(--surface); color:var(--ink); cursor:pointer; font-size:13px; font-weight:800; letter-spacing:.3px; }
  .lt:hover{ border-color:var(--accent); color:var(--accent); }
</style>
