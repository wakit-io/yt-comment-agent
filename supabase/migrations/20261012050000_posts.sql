-- 게시판(관리자용 자료 정리) — 카테고리별 메모/자료 글.
create table if not exists fl_posts (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  body       text,
  category   text not null default '일반',
  pinned     boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists fl_posts_cat on fl_posts(category);
create index if not exists fl_posts_updated on fl_posts(updated_at desc);
drop trigger if exists fl_posts_touch on fl_posts;
create trigger fl_posts_touch before update on fl_posts for each row execute function fl_touch();
alter table fl_posts enable row level security;
-- RLS 정책 없음 = 기본 거부(서버 service_role만 접근).
