// 모든 요청 passthrough — 공개 라우트는 일반 SvelteKit 페이지(랜딩)로 서빙.
export async function handle({ event, resolve }) {
  return resolve(event);
}
