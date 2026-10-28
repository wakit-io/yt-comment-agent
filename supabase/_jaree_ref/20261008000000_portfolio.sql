-- 상점 포트폴리오(작업 갤러리). 헤어·네일·스튜디오 등 "작업물 = 영업" 업종 핵심.
-- 공개 읽기는 서버(service_role)가 published=true만 필터해서 노출(리뷰와 동일 패턴).
-- 운영자 CRUD는 authenticated + desk_has_access(RLS). AI(MCP)가 작업 등록까지 가능.
begin;

create table if not exists public.desk_portfolio(
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.desk_shops(id) on delete cascade,
  title text not null check(length(trim(title)) between 1 and 120),
  category text not null default '' check(length(category) <= 40),
  description text not null default '' check(length(description) <= 600),
  image_url text not null check(length(image_url) between 1 and 2000),
  before_url text not null default '' check(length(before_url) <= 2000),
  featured boolean not null default false,
  published boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists desk_portfolio_shop
  on public.desk_portfolio(shop_id, published, featured desc, sort_order, created_at desc);

alter table public.desk_portfolio enable row level security;
revoke all on public.desk_portfolio from anon;
grant select,insert,update,delete on public.desk_portfolio to authenticated;
drop policy if exists desk_portfolio_all on public.desk_portfolio;
create policy desk_portfolio_all on public.desk_portfolio
  for all to authenticated
  using(public.desk_has_access(shop_id))
  with check(public.desk_has_access(shop_id));

commit;
