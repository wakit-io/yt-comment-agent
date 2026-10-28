// YouTube OAuth 콜백 — Google 이 code,state 를 붙여 리다이렉트.
//   state 에 서명된 ownerId 가 들어있어(브라우저엔 bearer가 없으므로) 이를 검증해 토큰 저장.
import { redirect } from '@sveltejs/kit';
import { verifyState, exchangeCode } from '../../../../../../lib/yt.mjs';

export async function GET({ url }) {
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  const err = url.searchParams.get('error');
  if (err) throw redirect(302, '/admin/settings?error=' + encodeURIComponent(err));
  const ownerId = verifyState(state);
  if (!code || !ownerId) throw redirect(302, '/admin/settings?error=invalid_state');
  try {
    const { channel_title } = await exchangeCode(code, ownerId);
    throw redirect(302, '/admin/settings?connected=' + encodeURIComponent(channel_title || '1'));
  } catch (e) {
    if (e?.status === 302 || e?.location) throw e; // redirect 통과
    throw redirect(302, '/admin/settings?error=' + encodeURIComponent((e?.message || 'exchange_failed').slice(0, 80)));
  }
}
