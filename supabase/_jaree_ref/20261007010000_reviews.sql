-- 상점 리뷰(사용후기 + 평점). 회원이 작성(상점당 1건, 수정가능), 공개 읽기, 운영자 답변.
-- 쓰기는 서버(service_role)가 컬럼을 통제해 처리 → 회원은 rating/body만, 운영자는 reply/published만.
begin;
create table if not exists public.desk_reviews(
 id uuid primary key default gen_random_uuid(),
 shop_id uuid not null references public.desk_shops(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 author_name text not null check(length(trim(author_name)) between 1 and 40),
 rating integer not null check(rating between 1 and 5),
 body text not null check(length(trim(body)) between 1 and 2000),
 reply text not null default '' check(length(reply)<=2000),
 reply_at timestamptz,
 published boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(shop_id,user_id)
);
create index if not exists desk_reviews_shop on public.desk_reviews(shop_id,created_at desc);
alter table public.desk_reviews enable row level security;
revoke all on public.desk_reviews from anon,authenticated;
-- 공개 읽기(공개된 리뷰만). 쓰기는 service_role(서버)만.
grant select on public.desk_reviews to anon,authenticated;
grant select,insert,update,delete on public.desk_reviews to service_role;
drop policy if exists desk_reviews_read on public.desk_reviews;
create policy desk_reviews_read on public.desk_reviews for select to anon,authenticated using(published);
commit;
