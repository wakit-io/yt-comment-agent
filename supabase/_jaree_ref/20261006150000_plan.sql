-- 상점 요금제: free(기본) / pro. pro는 브랜드 배지 제거 등 유료 기능.
alter table public.desk_shops add column if not exists plan text not null default 'free' check(plan in ('free','pro'));
