# JAREE kit(SvelteKit SSR) 배포 런북

라이브 `jaree.kr`(Netlify 사이트 `b45835a3-cc21-4410-8a3c-d6f73876aa6b`)의 프론트를
바닐라(web/ + netlify/functions) → **kit(SvelteKit SSR)** 로 교체한다.
**MCP/OAuth/API URL은 전부 동일하게 유지**되므로 이미 연결된 ChatGPT·Claude 커넥터는 끊기지 않는다.

> ⚠️ 이건 **라이브 서비스 교체(컷오버)** 다. 반드시 ① 드래프트 배포로 먼저 검증 → ② 프로덕션 배포 순서.
> 배포 명령은 사장님이 직접 실행한다(Claude는 배포 트리거 안 함).

---

## 0. 사전 점검 (배포 전 1회)

- [ ] **사이트 환경변수 확인** (Netlify → Site `b45835a3` → Environment variables). 라이브가 쓰던 값 그대로여야 함:
  - `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`  (프로덕션 Supabase = waanee87 계정 `oqacbxfbrodxjmiiestk`)
  - `APP_ORIGIN = https://jaree.kr`  ← **반드시 정확히 이 값** (OAuth issuer·디스커버리·/api Origin정책 기준)
- [ ] **프로덕션 Supabase 마이그레이션 적용 여부** 확인: `desk_reviews`, `desk_theme_entitlements`, `desk_shop_themes`, 정원/플래너 컬럼 등. (라이브가 이미 해당 기능으로 떠 있었다면 적용된 상태.)
- [ ] 로컬에서 빌드·검증 통과 확인:
  ```bash
  cd kit
  npm install
  npm run build        # ✓ built / adapter-netlify done
  ```

---

## ⚠️ 배포 명령 주의 (중요)

이 프로젝트는 **서브디렉토리(kit/)** 앱이고 코드가 부모(`../lib`, `../web`)를 import하므로,
`netlify deploy --build` **자동 감지로는 SSR 함수가 배포되지 않는다**(available_functions=[] → 전 페이지 404).
반드시 **로컬에서 `npm run build` 후, `--functions=.netlify/functions-internal`를 명시**해서 배포한다.
(kit/.netlify/state.json으로 kit을 프로젝트 베이스로 링크해 둠)

## 1. 드래프트 배포 (프리뷰 URL, jaree.kr 안 건드림)

```bash
cd kit
npm run build
netlify deploy --dir=build --functions=.netlify/functions-internal
```

출력된 **Website Draft URL**(예: `https://<hash>--<site>.netlify.app`)에서 스모크 점검:
- [ ] `available_functions`에 `sveltekit-render` 포함 확인(없으면 전부 404)

- [ ] 홈 `/`, `/@라움-studio`(실상점), `/about`, `/guide` 등 페이지가 **SSR로 렌더**되는지(소스보기에 데이터 포함)
- [ ] `/.well-known/oauth-authorization-server` → 200 (JSON)
- [ ] `/mcp`에 인증 없이 POST → **401**(회원 전용 게이트 정상)
- [ ] 상점 페이지 테마·예약폼·후기 노출, 관리자 로그인 동작

> 참고: 드래프트에서도 `APP_ORIGIN=https://jaree.kr`를 따르므로 OAuth 디스커버리 issuer는 jaree.kr로 나온다.
> 드래프트에서 전체 OAuth 승인까지는 리다이렉트가 jaree.kr로 가므로, OAuth 전체 흐름 최종 확인은 프로덕션에서 한다.

---

## 2. 프로덕션 배포 (jaree.kr 컷오버)

```bash
cd kit
npm run build
netlify deploy --prod --dir=build --functions=.netlify/functions-internal
```

### 배포 직후 검증 (jaree.kr)
- [ ] `https://jaree.kr/` 및 상점 페이지 정상
- [ ] `https://jaree.kr/.well-known/oauth-authorization-server` → issuer `https://jaree.kr` 확인
- [ ] **기존 커넥터**(ChatGPT/Claude)에서 상점 조회·예약 도구 1회 호출 → 재인증 없이 동작
- [ ] 필요 시 **신규 커넥터 연결**(`https://jaree.kr/mcp` 또는 `https://jaree.kr/@상점/mcp`) OAuth 전체 흐름 1회
- [ ] 비밀번호 복구: 기존 메일의 `/reset-password.html` 링크 → `/reset-password`로 301 되는지

---

## 3. 롤백 (문제 시)

Netlify UI → 사이트 `b45835a3` → **Deploys** → 직전 바닐라 배포 선택 → **Publish deploy**.
(URL·커넥터 그대로 복구됨. 바닐라 web/ + netlify/functions 설정은 루트 `netlify.toml`에 보존되어 있음.)

---

## 변경 요약 (이번 배포에 포함된 것)

- 프론트 전체 SvelteKit SSR 이전 (페이지·관리자·마스터·테마·블로그/공지/약관/소개/가이드/리셋)
- 상점 페이지 **테마별 레이아웃 분리**(classic/atelier/noir) + 관리자 **테마 탭**·미리보기
- 설정탭 **이미지 업로드·공개 토글** 복원
- 백엔드 3표면(MCP·OAuth·API)·디스커버리 전부 동일 URL 재배선 (lib/ 핸들러 재사용)
- `/reset-password.html` → `/reset-password` 호환 리다이렉트
- `/api` Origin 정책: `APP_ORIGIN` 설정 환경에서만 적용(바닐라 동치)
- MCP 엔드포인트 깨진 JSON → 400 (하드닝)

## 검증 상태 (배포 전)
- lib 유닛/통합 28/28 · 일상 시나리오 12/12 · 보안 17/17 · OAuth 2.1 E2E 5/5 · 전체 라우트 200+SSR+404 · 빌드 통과
