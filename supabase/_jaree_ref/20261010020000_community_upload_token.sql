-- 커뮤니티 사진 업로드 링크: 일회용·단명 토큰(30분). 토큰이 곧 인증(비로그인 폰에서 업로드).
-- 특정 메모에 바인딩, 업로드 성공 시 그 메모에 image_url 세팅(+publish). service_role 전용.
begin;
create table if not exists public.desk_upload_tokens(
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  memo_id uuid not null references public.desk_memos(id) on delete cascade,
  publish boolean not null default true,
  used_at timestamptz,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists desk_upload_tokens_exp on public.desk_upload_tokens(expires_at);
alter table public.desk_upload_tokens enable row level security;
revoke all on public.desk_upload_tokens from anon, authenticated;
commit;
