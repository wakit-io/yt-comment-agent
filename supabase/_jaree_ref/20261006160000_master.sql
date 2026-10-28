-- 플랫폼 공지사항 (운영자 작성, 공개 읽기). service_role로만 접근.
create table if not exists public.desk_announcements(
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null default '',
  published boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.desk_announcements enable row level security;
revoke all on public.desk_announcements from anon,authenticated;

-- 브랜드 블로그 (SEO). service_role로만 접근(공개 페이지는 서버 렌더).
create table if not exists public.desk_posts(
  id uuid primary key default gen_random_uuid(),
  slug text unique not null check(slug ~ '^[a-z0-9][a-z0-9-]{1,80}$'),
  title text not null,
  excerpt text not null default '',
  body text not null default '',
  cover_url text not null default '',
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.desk_posts enable row level security;
revoke all on public.desk_posts from anon,authenticated;
create index if not exists desk_posts_pub on public.desk_posts(published, created_at desc);
