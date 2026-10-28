<script>
  import { onMount } from 'svelte';
  import { getPref, setPref, effective } from '$lib/theme.js';
  // 다크 ↔ 라이트 2단계 토글(시스템 모드 제거 — 한 번에 바로 전환)
  let cur = $state('light'); // 현재 적용된 테마
  onMount(() => { cur = effective(getPref()); });
  function toggle() { cur = cur === 'dark' ? 'light' : 'dark'; setPref(cur); }
</script>
<button class="tt" onclick={toggle} title={cur === 'dark' ? '라이트 모드로 전환' : '다크 모드로 전환'} aria-label="테마 전환">
  <i class={cur === 'dark' ? 'fi-rr-moon' : 'fi-rr-sun'}></i>
</button>
<style>
  .tt{ display:inline-flex; align-items:center; justify-content:center; width:36px; height:36px; border-radius:9px; border:0; background:transparent; color:var(--ink); cursor:pointer; font-size:16px; }
  .tt:hover{ background:var(--badge-bg); color:var(--accent); }
</style>
