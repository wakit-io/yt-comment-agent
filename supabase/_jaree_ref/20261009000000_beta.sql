-- 집중 베타테스터 지정(마스터 운영용). service_role로만 접근(브라우저/일반회원 접근 차단).
create table if not exists public.desk_beta_testers(
  user_id uuid primary key references auth.users(id) on delete cascade,
  note text not null default '',
  status text not null default 'onboarding' check(status in ('onboarding','active','paused','done')),
  created_at timestamptz not null default now()
);
alter table public.desk_beta_testers enable row level security;
revoke all on public.desk_beta_testers from anon, authenticated;
