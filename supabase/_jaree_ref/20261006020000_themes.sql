-- 테마 선택과 사용권은 브랜드 설정과 별도로 보호한다.
create table if not exists public.desk_shop_themes (
 shop_id uuid primary key references public.desk_shops(id) on delete cascade,
 theme_id text not null check(theme_id in ('classic','atelier','noir')),
 updated_at timestamptz not null default now()
);
create table if not exists public.desk_theme_entitlements (
 shop_id uuid not null references public.desk_shops(id) on delete cascade,
 theme_id text not null check(theme_id in ('noir')),
 expires_at timestamptz,
 created_at timestamptz not null default now(),
 primary key(shop_id,theme_id)
);
alter table public.desk_shop_themes enable row level security;
alter table public.desk_theme_entitlements enable row level security;
revoke all on public.desk_shop_themes,public.desk_theme_entitlements from anon,authenticated;
grant select on public.desk_shop_themes,public.desk_theme_entitlements to authenticated;
drop policy if exists themes_read on public.desk_shop_themes;
create policy themes_read on public.desk_shop_themes for select to authenticated using(public.desk_has_access(shop_id,false));
drop policy if exists entitlements_read on public.desk_theme_entitlements;
create policy entitlements_read on public.desk_theme_entitlements for select to authenticated using(public.desk_has_access(shop_id,false));
create or replace function public.desk_apply_theme(target uuid, chosen text) returns text
language plpgsql security definer set search_path=public as $$
begin
 if not public.desk_has_access(target,true) then raise exception '상점 소유자만 테마를 변경할 수 있습니다' using errcode='42501'; end if;
 if chosen not in ('classic','atelier','noir') or chosen is null then raise exception '지원하지 않는 테마입니다' using errcode='22023'; end if;
 if chosen='noir' and not exists(select 1 from public.desk_theme_entitlements where shop_id=target and theme_id=chosen and (expires_at is null or expires_at>now())) then
  raise exception '이 상점에 프리미엄 테마 사용권이 필요합니다' using errcode='42501';
 end if;
 insert into public.desk_shop_themes(shop_id,theme_id) values(target,chosen) on conflict(shop_id) do update set theme_id=excluded.theme_id,updated_at=now();
 return chosen;
end $$;
revoke all on function public.desk_apply_theme(uuid,text) from public;
grant execute on function public.desk_apply_theme(uuid,text) to authenticated;
