<script>
  // 공개 랜딩 — 운명원(연애 사주). 랜딩노출(featured) 체크한 유튜브 댓글을 "우리가 나눈 이야기"로 노출.
  //  ⚠️ 프레이밍: 제3자 후기(X). 우리가 유튜브에서 전한 공감의 말들(O).
  import { onMount } from 'svelte';

  let brand = $state('운명원');
  let feed = $state([]);
  let loaded = $state(false);
  let scrolled = $state(false);

  function fmtDate(ts) { try { return new Date(ts).toLocaleDateString('ko-KR', { year: 'numeric', month: 'long', day: 'numeric' }); } catch { return ''; } }

  onMount(async () => {
    try {
      const [s, f] = await Promise.all([
        fetch('/api/yt/settings').then((r) => r.json()).catch(() => ({})),
        fetch('/api/yt/featured').then((r) => r.json()).catch(() => []),
      ]);
      if (s?.brand) brand = s.brand;
      feed = Array.isArray(f) ? f : [];
    } catch (e) { /* */ }
    loaded = true;
  });

  // 스크롤 시 상단 내비게이션을 크림 바탕으로 전환
  onMount(() => {
    const onScroll = () => { scrolled = window.scrollY > 40; };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    return () => window.removeEventListener('scroll', onScroll);
  });

  // 히어로 — 골든아워 역광 먼지/빛 입자(three.js). 은은하게, 텍스트 뒤에서 천천히 떠오름.
  let fxCanvas = $state(null);
  onMount(() => {
    if (!fxCanvas) return;
    const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches;
    let cleanup = () => {};
    (async () => {
      let THREE;
      try { THREE = await import('three'); } catch { return; }
      const host = fxCanvas.parentElement;
      let w = host.clientWidth || 1200, h = host.clientHeight || 600;
      let renderer;
      try { renderer = new THREE.WebGLRenderer({ canvas: fxCanvas, alpha: true, antialias: true }); } catch { return; }
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
      renderer.setSize(w, h, false);
      const scene = new THREE.Scene();
      const camera = new THREE.PerspectiveCamera(60, w / h, 1, 1000);
      camera.position.z = 120;

      // 부드러운 원형 bokeh 스프라이트
      const cv = document.createElement('canvas'); cv.width = cv.height = 64;
      const g2 = cv.getContext('2d');
      const grd = g2.createRadialGradient(32, 32, 0, 32, 32, 32);
      grd.addColorStop(0, 'rgba(255,241,208,1)'); grd.addColorStop(.35, 'rgba(255,214,150,.5)'); grd.addColorStop(1, 'rgba(255,198,128,0)');
      g2.fillStyle = grd; g2.fillRect(0, 0, 64, 64);
      const tex = new THREE.CanvasTexture(cv);

      const N = 70, RX = 230, RY = 130, RZ = 170;
      const pos = new Float32Array(N * 3); const spd = new Float32Array(N);
      for (let i = 0; i < N; i++) {
        pos[i * 3] = (Math.random() * 2 - 1) * RX;
        pos[i * 3 + 1] = (Math.random() * 2 - 1) * RY;
        pos[i * 3 + 2] = -Math.random() * RZ;
        spd[i] = 0.05 + Math.random() * 0.13;
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      const mat = new THREE.PointsMaterial({ size: 5, map: tex, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, color: 0xffd79a, opacity: .5, sizeAttenuation: true });
      const pts = new THREE.Points(geo, mat);
      scene.add(pts);

      const onResize = () => { w = host.clientWidth; h = host.clientHeight; camera.aspect = w / h; camera.updateProjectionMatrix(); renderer.setSize(w, h, false); };
      window.addEventListener('resize', onResize);

      let t = 0, raf;
      const tick = () => {
        t += 0.016;
        const p = geo.attributes.position.array;
        for (let i = 0; i < N; i++) {
          p[i * 3 + 1] += spd[i];
          p[i * 3] += Math.sin(t * 0.5 + i) * 0.012;
          if (p[i * 3 + 1] > RY) { p[i * 3 + 1] = -RY; p[i * 3] = (Math.random() * 2 - 1) * RX; }
        }
        geo.attributes.position.needsUpdate = true;
        mat.opacity = .4 + Math.sin(t * 0.5) * 0.12;
        renderer.render(scene, camera);
        raf = requestAnimationFrame(tick);
      };
      renderer.render(scene, camera);
      if (!reduce) raf = requestAnimationFrame(tick);

      cleanup = () => { cancelAnimationFrame(raf); window.removeEventListener('resize', onResize); geo.dispose(); mat.dispose(); tex.dispose(); renderer.dispose(); };
    })();
    return () => cleanup();
  });

  // 상담 메뉴(에디토리얼 카드)
  const MENU = [
    { no: '01', title: '연애운 흐름', img: '/landing/menu1.jpg', desc: '지금 내 연애가 어느 계절인지 — 들어오는 흐름과 멈춰 선 자리를 읽어요.' },
    { no: '02', title: '궁합 · 관계', img: '/landing/menu2.jpg', desc: '두 사람의 결이 어떻게 맞물리는지, 지금 이 관계의 온도를 짚어요.' },
    { no: '03', title: '인연의 때(택일)', img: '/landing/menu3.jpg', desc: '기다릴 때인지 움직일 때인지 — 흐름이 열리는 타이밍을 봐요.' },
  ];

  // ── 상담 신청 폼(접수 저장 없음 — UI·검증·완료확인만) ──
  const TOPICS = ['연애운 흐름', '궁합 보기', '재회운', '인연의 때(택일)', '기타 고민'];
  let form = $state({ name: '', phone: '', birth: '', btime: '모름', topic: TOPICS[0], story: '', agree: false });
  let submitting = $state(false);
  let done = $state(false);
  let ferr = $state('');

  const digits = (s) => (s || '').replace(/[^0-9]/g, '');
  const phoneOk = $derived(/^01[016789][0-9]{7,8}$/.test(digits(form.phone)));
  function onPhone(e) {
    const d = digits(e.target.value).slice(0, 11);
    let out = d;
    if (d.length >= 11) out = d.replace(/(\d{3})(\d{4})(\d{4})/, '$1-$2-$3');
    else if (d.length >= 7) out = d.replace(/(\d{3})(\d{3,4})(\d{0,4})/, (m, a, b, c) => c ? `${a}-${b}-${c}` : `${a}-${b}`);
    form.phone = out;
  }

  function submit(e) {
    e.preventDefault();
    ferr = '';
    if (!form.name.trim()) { ferr = '이름을 입력해 주세요.'; return; }
    if (!phoneOk) { ferr = '연락처를 정확히 입력해 주세요. (예: 010-1234-5678)'; return; }
    if (!form.agree) { ferr = '개인정보 수집·이용에 동의해 주세요.'; return; }
    submitting = true;
    // 데모: 서버 저장 없이 접수 완료 화면으로
    setTimeout(() => { submitting = false; done = true; }, 650);
  }
</script>

<svelte:head>
  <title>{brand} · 연애 사주 — 그 사람과 나의 흐름을 읽다</title>
  <meta name="description" content="{brand}는 연애의 흐름과 인연의 때를 사주로 풀어드립니다. 혼자 끙끙 앓던 연애 고민, 흐름부터 짚어보세요." />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
  <link href="https://fonts.googleapis.com/css2?family=Nanum+Myeongjo:wght@400;700;800&display=swap" rel="stylesheet" />
</svelte:head>

<div class="site">
  <!-- 상단 -->
  <header class="nav" class:scrolled>
    <div class="wrap navin">
      <a class="logo" href="#top">{brand}</a>
      <nav class="navlinks">
        <a href="#menu">상담 메뉴</a>
        <a href="#story">나눈 이야기</a>
        <a href="#about">소개</a>
        <a class="cta sm" href="#consult">상담 신청</a>
      </nav>
    </div>
  </header>

  <!-- 히어로 (시네마틱 석양) -->
  <section class="hero" id="top">
    <div class="sky" aria-hidden="true">
      <div class="stars">
        {#each Array(22) as _, i}<span style="left:{(i * 37 % 100)}%; top:{(i * 19 % 34)}%; animation-delay:{(i % 5) * 0.6}s"></span>{/each}
      </div>
    </div>
    <canvas class="hero-fx" bind:this={fxCanvas} aria-hidden="true"></canvas>

    <div class="wrap heroin">
      <p class="eyebrow light">연애 사주 · 인연의 흐름</p>
      <h1>그 사람과 나의 흐름,<br />지금 어디쯤일까.</h1>
      <p class="sub">매번 같은 자리에서 멈추는 연애. 혼자선 답이 안 나오던 마음을,<br /><b>{brand}</b>이 사주로 그 흐름부터 짚어드립니다.</p>
      <div class="herobtns">
        <a class="cta" href="#consult">내 연애 흐름 보기</a>
        <a class="cta ghost" href="#story">나눈 이야기 보기</a>
      </div>
      <div class="stat">
        <div><b>10,000+</b><span>상담 누적</span></div>
        <div class="sep"></div>
        <div><b>4.9</b><span>만족도</span></div>
        <div class="sep"></div>
        <div><b>15년</b><span>연애 사주 전문</span></div>
      </div>
    </div>
  </section>

  <!-- 상담 메뉴 -->
  <section class="menu-sec" id="menu">
    <div class="wrap">
      <p class="eyebrow center">무엇을 봐드릴까요</p>
      <h2 class="center">흐름을 읽는 세 가지 결</h2>
      <div class="menu-grid">
        {#each MENU as m}
          <a class="mcard" href="#consult">
            <div class="mthumb"><img src={m.img} alt="" loading="lazy" /><span class="mno">{m.no}</span></div>
            <div class="mbody">
              <span class="mdiv"></span>
              <h3>{m.title}</h3>
              <p>{m.desc}</p>
              <span class="mgo">상담 신청 →</span>
            </div>
          </a>
        {/each}
      </div>
    </div>
  </section>

  <!-- 유튜브에서 나눈 이야기(= featured 댓글) -->
  <section class="feed-sec" id="story">
    <div class="wrap">
      <p class="eyebrow center">유튜브에서 나눈 이야기</p>
      <h2 class="center">같은 마음을, 먼저 지나온 말들</h2>
      <p class="secsub">{brand}이 유튜브 연애 사연 영상에서 직접 남긴 공감의 말들이에요.<br />(제3자 후기가 아닌, 저희가 전한 이야기입니다.)</p>

      {#if !loaded}
        <div class="grid">{#each Array(4) as _}<div class="fskel"></div>{/each}</div>
      {:else if feed.length}
        <div class="grid">
          {#each feed as c}
            <figure class="fcard">
              <blockquote>{c.body}</blockquote>
              <figcaption>
                <span class="vctx">“{c.video_title}” 영상에서</span>
                <span class="fdate">{fmtDate(c.created_at)}</span>
              </figcaption>
              {#if c.comment_link}<a class="flink" href={c.comment_link} target="_blank" rel="noopener">유튜브에서 보기 ↗</a>{/if}
            </figure>
          {/each}
        </div>
      {:else}
        <p class="empty">곧 이야기가 쌓입니다.</p>
      {/if}
    </div>
  </section>

  <!-- 소개 -->
  <section class="about" id="about">
    <div class="wrap abgrid">
      <div class="abcopy">
        <p class="eyebrow">{brand}은</p>
        <h2>흐름을 알면,<br />마음이 한결 가벼워져요.</h2>
        <p class="ablead">연애는 타이밍과 흐름이에요. 지금이 기다릴 때인지, 움직일 때인지 — 사주로 그 결을 읽어드립니다.</p>
        <ul>
          <li>연애운·궁합·재회 흐름 상담</li>
          <li>지금 관계의 때(타이밍) 진단</li>
          <li>비대면 간편 상담, 기록으로 전달</li>
        </ul>
      </div>
      <!-- 소개 이미지 -->
      <div class="abart">
        <img src="/landing/about.jpg" alt="창가에서 석양을 바라보며 마음을 가다듬는 모습" loading="lazy" />
        <p class="abcap">흐름을 알면, 오늘의 마음이 한결 가벼워져요.</p>
      </div>
    </div>
  </section>

  <!-- 상담 신청 폼 -->
  <section class="consult" id="consult">
    <div class="wrap consultin">
      <div class="ccopy">
        <p class="eyebrow gold">상담 신청</p>
        <h2>혼자 고민하지 말고,<br />흐름부터 같이 봐요.</h2>
        <p class="cdesc">간단한 사연만 남기면 {brand}이 연애 흐름을 짚어 비대면으로 전해드려요. 보통 1영업일 내에 연락드립니다.</p>
        <ul class="trust">
          <li>상담 전 결제·부담 없이 신청</li>
          <li>비대면 상담 · 기록으로 전달</li>
          <li>개인정보는 상담 목적 외 사용하지 않아요</li>
        </ul>
      </div>

      <div class="formcard">
        {#if done}
          <div class="success">
            <div class="scheck" aria-hidden="true">
              <svg viewBox="0 0 24 24"><path d="M5 13l4 4L19 7" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" /></svg>
            </div>
            <h3>{form.name}님, 신청이 접수됐어요.</h3>
            <p>남겨주신 연락처({form.phone})로 보통 <b>1영업일 내</b>에 연락드릴게요.<br />마음 편히 기다려 주세요.</p>
            <dl class="recap">
              <div><dt>상담 유형</dt><dd>{form.topic}</dd></div>
              {#if form.birth}<div><dt>생년월일</dt><dd>{form.birth}{form.btime !== '모름' ? ` · ${form.btime}` : ''}</dd></div>{/if}
            </dl>
            <button class="cta full" onclick={() => { done = false; form = { name: '', phone: '', birth: '', btime: '모름', topic: TOPICS[0], story: '', agree: false }; }}>새로 신청하기</button>
            <p class="dnote">※ 심사용 데모 랜딩이라 실제로 저장·발송되지는 않습니다.</p>
          </div>
        {:else}
          <h3 class="fhd">연애 흐름 상담 신청</h3>
          <form onsubmit={submit} novalidate>
            <div class="frow">
              <label for="f-name">이름 <span class="req">*</span></label>
              <input id="f-name" type="text" bind:value={form.name} placeholder="성함 또는 닉네임" autocomplete="name" />
            </div>
            <div class="frow">
              <label for="f-phone">연락처 <span class="req">*</span></label>
              <input id="f-phone" type="tel" value={form.phone} oninput={onPhone} placeholder="010-0000-0000" inputmode="numeric" autocomplete="tel" class:bad={form.phone && !phoneOk} />
            </div>
            <div class="frow2">
              <div class="frow">
                <label for="f-birth">생년월일</label>
                <input id="f-birth" type="date" bind:value={form.birth} />
              </div>
              <div class="frow">
                <label for="f-btime">태어난 시</label>
                <select id="f-btime" bind:value={form.btime}>
                  <option>모름</option><option>자시(23~01)</option><option>축시(01~03)</option><option>인시(03~05)</option><option>묘시(05~07)</option><option>진시(07~09)</option><option>사시(09~11)</option><option>오시(11~13)</option><option>미시(13~15)</option><option>신시(15~17)</option><option>유시(17~19)</option><option>술시(19~21)</option><option>해시(21~23)</option>
                </select>
              </div>
            </div>
            <div class="frow">
              <label for="f-topic">상담 유형 <span class="req">*</span></label>
              <select id="f-topic" bind:value={form.topic}>{#each TOPICS as t}<option>{t}</option>{/each}</select>
            </div>
            <div class="frow">
              <label for="f-story">사연 <span class="opt">(선택)</span></label>
              <textarea id="f-story" rows="3" bind:value={form.story} placeholder="어떤 연애 고민인지 편하게 적어주세요. 더 정확히 짚어드릴 수 있어요."></textarea>
            </div>
            <label class="agree">
              <input type="checkbox" bind:checked={form.agree} />
              <span>개인정보 수집·이용에 동의합니다. <span class="opt">(상담 연락 목적, 상담 후 파기)</span></span>
            </label>
            {#if ferr}<p class="ferr">{ferr}</p>{/if}
            <button class="cta full" type="submit" disabled={submitting}>{submitting ? '접수 중…' : '무료로 상담 신청하기'}</button>
            <p class="fnote">버튼을 누르면 위 내용으로 상담 신청이 접수됩니다.</p>
          </form>
        {/if}
      </div>
    </div>
  </section>

  <footer class="foot">
    <div class="wrap footin">
      <div>
        <span class="logo sm">{brand}</span>
        <p class="fdesc">연애 사주 · 인연의 흐름 상담</p>
      </div>
      <div class="footlinks">
        <a href="#menu">상담 메뉴</a><a href="#story">나눈 이야기</a><a href="#about">소개</a><a href="#consult">상담 신청</a>
      </div>
      <span class="copy">© {new Date().getFullYear()} {brand}</span>
    </div>
  </footer>
</div>

<style>
  .site {
    --paper:#f6efe3; --paper2:#efe4d3; --card:#fffdf8; --ink:#2b241c; --muted:#8c7c66;
    --clay:#b4532f; --clay-d:#984325; --gold:#ab8438; --line:#e7dcc8;
    color:var(--ink); background:var(--paper);
    font-family:'Apple SD Gothic Neo','Noto Sans KR',system-ui,sans-serif; -webkit-font-smoothing:antialiased;
  }
  .wrap { max-width:1080px; margin:0 auto; padding:0 24px; }
  :where(.site) h1, :where(.site) h2, :where(.site) h3, .logo, .fcard blockquote, .serif { font-family:'Nanum Myeongjo',serif; }

  .eyebrow { font-size:12px; font-weight:700; letter-spacing:.22em; color:var(--clay); text-transform:uppercase; margin:0 0 16px; }
  .eyebrow.center, .center { text-align:center; }
  .eyebrow.light { color:#f3d9a8; }
  .eyebrow.gold { color:var(--gold); }

  .cta { display:inline-block; background:var(--clay); color:#fff; font-weight:700; padding:15px 32px; border-radius:2px; text-decoration:none; font-size:15px; letter-spacing:.02em; transition:transform .14s, box-shadow .14s, background .14s; border:none; cursor:pointer; }
  .cta:hover { transform:translateY(-2px); background:var(--clay-d); box-shadow:0 12px 28px rgba(152,67,37,.3); }
  .cta.sm { padding:10px 20px; font-size:13.5px; }
  .cta.ghost { background:transparent; color:#fdf4e4; border:1px solid rgba(253,244,228,.5); }
  .cta.ghost:hover { background:rgba(253,244,228,.12); box-shadow:none; border-color:#fdf4e4; }
  .cta.full { display:block; width:100%; text-align:center; padding:16px; }
  .cta.full:disabled { opacity:.6; cursor:default; transform:none; box-shadow:none; }

  /* 내비게이션 — 히어로 위 투명 → 스크롤 시 크림 */
  .nav { position:fixed; top:0; left:0; right:0; z-index:30; transition:background .25s, box-shadow .25s, border-color .25s; border-bottom:1px solid transparent; }
  .nav.scrolled { background:rgba(246,239,227,.92); backdrop-filter:blur(10px); border-bottom-color:var(--line); box-shadow:0 2px 18px rgba(80,55,25,.06); }
  .navin { display:flex; justify-content:space-between; align-items:center; height:66px; }
  .logo { font-size:23px; font-weight:800; letter-spacing:.04em; color:#fdf4e4; text-decoration:none; transition:color .25s; } .logo.sm { font-size:19px; }
  .nav.scrolled .logo { color:var(--ink); }
  .navlinks { display:flex; align-items:center; gap:28px; }
  .navlinks a { color:rgba(253,244,228,.82); text-decoration:none; font-size:14px; font-weight:600; transition:color .2s; }
  .navlinks a:hover { color:#fff; }
  .nav.scrolled .navlinks a { color:var(--muted); } .nav.scrolled .navlinks a:hover { color:var(--ink); }
  .navlinks a.cta { color:#fff; } .nav.scrolled .navlinks a.cta { color:#fff; }
  @media(max-width:640px){ .navlinks a:not(.cta){ display:none; } }

  /* 히어로 */
  .hero { position:relative; padding:170px 0 120px; text-align:center; overflow:hidden; color:#fdf4e4;
    background:linear-gradient(180deg, rgba(30,18,30,.6) 0%, rgba(40,24,34,.44) 40%, rgba(90,48,38,.34) 72%, rgba(50,30,34,.5) 100%), #241a2e url('/landing/hero2.jpg') center 42%/cover no-repeat; }
  .hero::after { content:""; position:absolute; inset:0; pointer-events:none; opacity:.5; mix-blend-mode:overlay;
    background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='140' height='140'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/></filter><rect width='100%25' height='100%25' filter='url(%23n)'/></svg>"); }
  .sky { position:absolute; inset:0; overflow:hidden; z-index:1; }
  .hero-fx { position:absolute; inset:0; width:100%; height:100%; z-index:1; pointer-events:none; }
  .stars span { position:absolute; width:2px; height:2px; border-radius:50%; background:#fff; opacity:.6; animation:tw 3.4s ease-in-out infinite; }
  @keyframes tw { 0%,100%{opacity:.75} 50%{opacity:.15} }
  .heroin { position:relative; z-index:2; }
  .hero h1 { font-size:54px; line-height:1.26; margin:0 0 22px; font-weight:800; letter-spacing:-.01em; text-shadow:0 2px 24px rgba(40,20,30,.35); }
  .hero .sub { font-size:17px; line-height:1.85; color:#f4e3cf; margin:0 auto 32px; max-width:580px; }
  .hero .sub b { color:#ffe6bd; font-weight:700; }
  .herobtns { display:flex; gap:12px; justify-content:center; flex-wrap:wrap; }
  .stat { display:inline-flex; gap:30px; align-items:center; margin-top:56px; background:rgba(36,20,28,.42); border:1px solid rgba(255,230,200,.28); border-radius:4px; padding:18px 30px; backdrop-filter:blur(6px); box-shadow:0 10px 40px rgba(30,15,20,.3); }
  .stat > div:not(.sep) { display:flex; flex-direction:column; gap:4px; }
  .stat b { font-size:27px; color:#ffe6bd; font-family:'Nanum Myeongjo',serif; font-weight:800; } .stat span { font-size:12px; color:#eccfae; letter-spacing:.02em; }
  .stat .sep { width:1px; align-self:stretch; background:rgba(255,248,236,.22); }
  @media(max-width:640px){ .hero { padding:130px 0 80px; } .hero h1 { font-size:34px; } .stat { gap:18px; padding:16px 18px; } .stat b { font-size:22px; } }

  h2 { letter-spacing:-.01em; font-weight:800; color:var(--ink); }
  .secsub { text-align:center; color:var(--muted); font-size:14.5px; margin:14px auto 0; max-width:560px; line-height:1.75; }

  /* 상담 메뉴 */
  .menu-sec { padding:96px 0; background:var(--paper); }
  .menu-sec h2 { font-size:32px; margin:0 0 44px; }
  .menu-grid { display:grid; grid-template-columns:repeat(3,1fr); gap:20px; }
  @media(max-width:780px){ .menu-grid { grid-template-columns:1fr; } }
  .mcard { display:flex; flex-direction:column; background:var(--card); border:1px solid var(--line); border-radius:6px; overflow:hidden; text-decoration:none; color:inherit; transition:transform .16s, box-shadow .16s, border-color .16s; }
  .mcard:hover { transform:translateY(-4px); box-shadow:0 20px 48px rgba(90,60,30,.16); border-color:#d9c9ac; }
  .mthumb { position:relative; aspect-ratio:16/9; overflow:hidden; background:var(--paper2); }
  .mthumb img { width:100%; height:100%; object-fit:cover; display:block; transition:transform .45s ease; }
  .mcard:hover .mthumb img { transform:scale(1.06); }
  .mno { position:absolute; left:16px; bottom:12px; font-family:'Nanum Myeongjo',serif; font-size:28px; font-weight:800; color:#fff; line-height:1; text-shadow:0 2px 12px rgba(0,0,0,.5); }
  .mbody { display:flex; flex-direction:column; align-items:flex-start; padding:24px 26px 28px; flex:1; }
  .mdiv { width:34px; height:2px; background:var(--gold); margin:0 0 16px; }
  .mcard h3 { font-size:21px; margin:0 0 12px; }
  .mcard p { font-size:14px; line-height:1.75; color:var(--muted); margin:0 0 20px; }
  .mgo { font-size:13px; font-weight:700; color:var(--clay); margin-top:auto; }

  /* 나눈 이야기 */
  .feed-sec { padding:96px 0; background:var(--paper2); }
  .feed-sec h2 { font-size:32px; margin:0; }
  .grid { display:grid; grid-template-columns:repeat(2, 1fr); gap:20px; margin-top:44px; }
  @media(max-width:720px){ .grid { grid-template-columns:1fr; } }
  .fcard { margin:0; background:var(--card); border:1px solid var(--line); border-radius:4px; padding:30px 28px; display:flex; flex-direction:column; }
  .fcard blockquote { margin:0 0 18px; font-size:17px; line-height:1.9; color:var(--ink); position:relative; padding-top:20px; }
  .fcard blockquote::before { content:'“'; position:absolute; top:-6px; left:-6px; font-size:52px; color:var(--gold); opacity:.5; font-family:'Nanum Myeongjo',serif; line-height:1; }
  .fcard figcaption { display:flex; justify-content:space-between; align-items:baseline; gap:10px; border-top:1px solid var(--line); padding-top:14px; margin-top:auto; }
  .vctx { font-size:12.5px; color:var(--muted); font-weight:600; line-height:1.4; }
  .fdate { font-size:11.5px; color:#a99a82; white-space:nowrap; }
  .flink { font-size:12.5px; color:var(--clay); font-weight:700; text-decoration:none; margin-top:12px; align-self:flex-start; }
  .flink:hover { color:var(--clay-d); }
  .fskel { height:190px; border-radius:4px; background:linear-gradient(90deg,#efe4d3,#f7f0e4,#efe4d3); background-size:200% 100%; animation:sh 1.2s infinite; }
  @keyframes sh { 0%{background-position:200% 0} 100%{background-position:-200% 0} }
  .empty { text-align:center; color:var(--muted); padding:40px 0; }

  /* 소개 */
  .about { background:var(--paper); padding:100px 0; }
  .abgrid { display:grid; grid-template-columns:1.05fr .95fr; gap:60px; align-items:center; }
  @media(max-width:780px){ .abgrid { grid-template-columns:1fr; gap:36px; } }
  .about h2 { font-size:33px; margin:0 0 20px; line-height:1.32; }
  .ablead { font-size:16px; line-height:1.9; color:#6f6151; margin:0 0 24px; }
  .abcopy ul { margin:0; padding:0; list-style:none; }
  .abcopy li { padding:14px 0 14px 26px; border-top:1px solid var(--line); position:relative; font-size:15px; color:var(--ink); }
  .abcopy li::before { content:''; position:absolute; left:2px; top:21px; width:7px; height:7px; border-radius:50%; background:var(--clay); }
  .abart { border:1px solid var(--line); border-radius:8px; overflow:hidden; box-shadow:0 20px 50px rgba(90,60,30,.14); background:var(--paper2); }
  .abart img { width:100%; aspect-ratio:4/3; object-fit:cover; display:block; }
  .abcap { text-align:center; color:var(--muted); font-size:12.5px; margin:0; padding:13px 16px; font-style:italic; border-top:1px solid var(--line); background:var(--card); }

  /* 상담 신청 */
  .consult { background:linear-gradient(145deg, #3a2430 0%, #6e3a2e 55%, #8a4a30 100%); color:#fdf4e4; padding:100px 0; position:relative; overflow:hidden; }
  .consult::after { content:""; position:absolute; inset:0; pointer-events:none; opacity:.4; mix-blend-mode:overlay;
    background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='140' height='140'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/></filter><rect width='100%25' height='100%25' filter='url(%23n)'/></svg>"); }
  .consultin { position:relative; z-index:2; display:grid; grid-template-columns:1fr 1fr; gap:56px; align-items:center; }
  @media(max-width:840px){ .consultin { grid-template-columns:1fr; gap:34px; } }
  .consult h2 { font-size:33px; margin:0 0 18px; line-height:1.4; color:#fff; }
  .cdesc { color:#f0ddc8; font-size:15.5px; line-height:1.85; margin:0 0 24px; }
  .trust { list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:13px; }
  .trust li { position:relative; padding-left:28px; font-size:14.5px; color:#f4e5d3; }
  .trust li::before { content:'✓'; position:absolute; left:0; top:-1px; color:#ffcf8f; font-weight:800; }

  .formcard { background:var(--card); color:var(--ink); border:1px solid var(--line); border-radius:6px; padding:30px; box-shadow:0 30px 70px rgba(30,15,12,.4); }
  .fhd { margin:0 0 20px; font-size:20px; }
  .frow { margin-bottom:15px; } .frow2 { display:grid; grid-template-columns:1fr 1fr; gap:12px; }
  .frow label { display:block; font-size:13px; font-weight:700; margin-bottom:7px; color:#5f5345; }
  .req { color:var(--clay); } .opt { color:#a99a82; font-weight:500; font-size:12px; }
  .frow input, .frow select, .frow textarea { width:100%; box-sizing:border-box; padding:12px 13px; border:1px solid var(--line); border-radius:3px; font:inherit; font-size:14px; background:#fffefb; color:var(--ink); transition:border-color .12s, box-shadow .12s; }
  .frow input::placeholder, .frow textarea::placeholder { color:#b7a88f; }
  .frow input:focus, .frow select:focus, .frow textarea:focus { outline:none; border-color:var(--clay); box-shadow:0 0 0 3px rgba(180,83,47,.14); }
  .frow input.bad { border-color:var(--clay); }
  .frow textarea { resize:vertical; line-height:1.6; }
  .agree { display:flex; align-items:flex-start; gap:9px; font-size:13px; color:#6f6151; margin:4px 0 16px; line-height:1.55; cursor:pointer; }
  .agree input { width:17px; height:17px; margin:1px 0 0; accent-color:var(--clay); flex:none; }
  .ferr { color:var(--clay-d); font-size:13px; margin:0 0 12px; font-weight:700; }
  .fnote { font-size:11.5px; color:#a99a82; text-align:center; margin:12px 0 0; }

  .success { text-align:center; padding:12px 4px; }
  .scheck { width:60px; height:60px; margin:4px auto 18px; border-radius:50%; background:rgba(176,137,56,.14); color:#8a6a1f; display:flex; align-items:center; justify-content:center; }
  .scheck svg { width:30px; height:30px; }
  .success h3 { margin:0 0 10px; font-size:21px; }
  .success p { font-size:14.5px; line-height:1.75; color:#6f6151; margin:0 0 20px; }
  .recap { display:flex; flex-direction:column; gap:9px; background:var(--paper); border:1px solid var(--line); border-radius:4px; padding:15px 17px; margin:0 0 22px; text-align:left; }
  .recap div { display:flex; justify-content:space-between; font-size:13.5px; }
  .recap dt { color:var(--muted); margin:0; } .recap dd { margin:0; font-weight:700; }
  .dnote { font-size:11.5px; color:#a99a82; margin:14px 0 0; }

  /* 푸터 */
  .foot { background:#2b241c; color:#b7a88f; padding:40px 0; }
  .foot .logo { color:#f6efe3; }
  .footin { display:flex; justify-content:space-between; align-items:center; gap:18px; flex-wrap:wrap; }
  .fdesc { font-size:12.5px; margin:7px 0 0; color:#8c7d66; }
  .footlinks { display:flex; gap:22px; } .footlinks a { color:#b7a88f; text-decoration:none; font-size:13px; } .footlinks a:hover { color:#fff; }
  .copy { font-size:12.5px; }
  @media(max-width:640px){ .footin { flex-direction:column; align-items:flex-start; gap:12px; } }
</style>
