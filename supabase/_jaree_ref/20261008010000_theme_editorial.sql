-- 에디토리얼 테마(무료) 추가: check 제약 + desk_apply_theme 허용 목록 확장.
begin;
alter table public.desk_shop_themes drop constraint if exists desk_shop_themes_theme_id_check;
alter table public.desk_shop_themes add constraint desk_shop_themes_theme_id_check check(theme_id in ('classic','atelier','noir','editorial'));
create or replace function public.desk_apply_theme(target uuid, chosen text) returns text
language plpgsql security definer set search_path=public as $$
begin
 if not public.desk_has_access(target,true) then raise exception '상점 소유자만 테마를 변경할 수 있습니다' using errcode='42501'; end if;
 if chosen not in ('classic','atelier','noir','editorial') or chosen is null then raise exception '지원하지 않는 테마입니다' using errcode='22023'; end if;
 if chosen='noir' and not exists(select 1 from public.desk_theme_entitlements where shop_id=target and theme_id=chosen and (expires_at is null or expires_at>now())) then
  raise exception '이 상점에 프리미엄 테마 사용권이 필요합니다' using errcode='42501';
 end if;
 insert into public.desk_shop_themes(shop_id,theme_id) values(target,chosen) on conflict(shop_id) do update set theme_id=excluded.theme_id,updated_at=now();
 return chosen;
end $$;
commit;
