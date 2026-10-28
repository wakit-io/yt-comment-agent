-- 서비스 개선용 피드백/문의/버그 접수. 누구나 제출(공개 API→service_role 삽입), 마스터만 조회.
create table if not exists public.desk_feedback(
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'inquiry' check (kind in ('inquiry','bug','suggestion')),
  title text not null,
  body text not null default '',
  contact text not null default '',
  page_url text not null default '',
  user_id uuid,
  user_email text not null default '',
  status text not null default 'new' check (status in ('new','reviewing','resolved')),
  created_at timestamptz not null default now()
);
alter table public.desk_feedback enable row level security;
revoke all on public.desk_feedback from anon,authenticated;
create index if not exists desk_feedback_status on public.desk_feedback(status, created_at desc);
