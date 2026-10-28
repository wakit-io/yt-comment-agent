-- 커뮤니티(창문): 회원 닉네임 프로필 + 회원 메모(공개/비공개) + 댓글.
-- 상점 무관·회원 소유. 공개 글만 공개 읽기(RLS), 쓰기는 서버(service_role)가 컬럼 통제(리뷰와 동일 패턴).
begin;

-- 회원 닉네임(공개 표시용). service_role 전용(본인 조회는 API가 user_id 필터).
create table if not exists public.desk_profiles(
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check(length(trim(nickname)) between 1 and 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.desk_profiles enable row level security;
revoke all on public.desk_profiles from anon, authenticated;

-- 회원 커뮤니티 메모. author_name = 작성 시점 닉네임 스냅샷(공개 표시).
create table if not exists public.desk_memos(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null,
  category text not null default '기타',
  region text not null default '',
  body text not null check(length(trim(body)) between 1 and 2000),
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists desk_memos_public on public.desk_memos(published, created_at desc);
create index if not exists desk_memos_user on public.desk_memos(user_id, created_at desc);
alter table public.desk_memos enable row level security;
revoke all on public.desk_memos from anon, authenticated;
grant select on public.desk_memos to anon, authenticated;
drop policy if exists memos_public_read on public.desk_memos;
create policy memos_public_read on public.desk_memos for select to anon, authenticated using(published);

-- 댓글(공개 메모에만). 쓰기는 서버.
create table if not exists public.desk_memo_comments(
  id uuid primary key default gen_random_uuid(),
  memo_id uuid not null references public.desk_memos(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null,
  body text not null check(length(trim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists desk_memo_comments_memo on public.desk_memo_comments(memo_id, created_at);
alter table public.desk_memo_comments enable row level security;
revoke all on public.desk_memo_comments from anon, authenticated;
grant select on public.desk_memo_comments to anon, authenticated;
drop policy if exists memo_comments_read on public.desk_memo_comments;
create policy memo_comments_read on public.desk_memo_comments for select to anon, authenticated
  using(exists(select 1 from public.desk_memos m where m.id=memo_id and m.published));

commit;
