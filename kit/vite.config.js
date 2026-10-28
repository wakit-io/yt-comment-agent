// SvelteKit 3: kit 설정(어댑터·csrf)을 svelte.config.js 대신 sveltekit() 플러그인 인자로 전달.
//  sveltekit()가 async(Promise 반환)라 config도 async 함수로.
import { sveltekit } from '@sveltejs/kit/vite';
import vercel from '@sveltejs/adapter-vercel';
import netlify from '@sveltejs/adapter-netlify';

const onVercel = !!process.env.VERCEL;

export default async () => ({
  plugins: [
    await sveltekit({
      adapter: onVercel ? vercel({ runtime: 'nodejs24.x', regions: ['icn1'], split: false }) : netlify(),
      csrf: { trustedOrigins: ['*'] },
      // kit3: $lib 기본 제거됨 → 기존 임포트 유지하려 별칭 복원
      alias: { '$lib': 'src/lib' }
    })
  ],
  server: {
    fs: { allow: ['..'] }
  },
  ssr: { external: ['@supabase/supabase-js', '@modelcontextprotocol/sdk', 'nodemailer', 'web-push', 'jszip'] }
});
