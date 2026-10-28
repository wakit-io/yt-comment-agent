begin;
alter table public.desk_services add column if not exists closed_dates date[] not null default '{}';
create or replace function public.desk_check_closed_date() returns trigger language plpgsql set search_path='' as $$
declare changed boolean; begin
 if tg_op='INSERT' then changed=true; else changed=new.service_id is distinct from old.service_id or new.date is distinct from old.date or new.time is distinct from old.time or (new.status in ('requested','confirmed') and old.status not in ('requested','confirmed')); end if;
 if changed and exists(select 1 from public.desk_services where id=new.service_id and shop_id=new.shop_id and new.date=any(closed_dates)) then raise exception '선택한 날짜는 서비스 휴무일입니다'; end if;
 return new;
end $$;
drop trigger if exists desk_zz_closed_date on public.desk_bookings;
create trigger desk_zz_closed_date before insert or update on public.desk_bookings for each row execute function public.desk_check_closed_date();
revoke all on function public.desk_check_closed_date() from public;
commit;
