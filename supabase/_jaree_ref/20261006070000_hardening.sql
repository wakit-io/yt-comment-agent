begin;
alter table public.desk_services add column if not exists break_start time;
alter table public.desk_services add column if not exists break_end time;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='desk_service_break') then
 alter table public.desk_services add constraint desk_service_break check ((break_start is null and break_end is null) or (break_start is not null and break_end is not null and break_start>=start_time and break_end<=end_time and break_end>break_start));
 end if;
end $$;
alter table public.desk_events add column if not exists actor_user_id uuid references auth.users(id) on delete set null;
-- 활동 기록은 서버만 작성한다. 운영자는 자신의 상점 기록만 읽는다.
revoke insert,update on public.desk_events from authenticated;
create or replace function public.desk_check_break_and_reactivation() returns trigger language plpgsql set search_path='' as $$
declare s public.desk_services; changed boolean; begin
 if new.service_id is null then return new; end if;
 if tg_op='INSERT' then changed=true;
 else changed=new.service_id is distinct from old.service_id or new.date is distinct from old.date or new.time is distinct from old.time or new.shop_id is distinct from old.shop_id or (new.status in ('requested','confirmed') and old.status not in ('requested','confirmed'));
 end if;
 if changed then
  select * into s from public.desk_services where id=new.service_id and shop_id=new.shop_id for share;
  if not found or not s.active or not s.booking_enabled then raise exception '예약 가능한 서비스가 아닙니다'; end if;
  if new.start_at<=now() then raise exception '지난 시간에는 예약할 수 없습니다'; end if;
  if not(extract(dow from new.date)::integer=any(s.weekdays)) or new.time::time<s.start_time or new.time::time+make_interval(mins=>new.duration_minutes)>s.end_time or mod(extract(epoch from(new.time::time-s.start_time))/60,s.slot_interval_minutes)<>0 then raise exception '서비스의 예약 가능 시간이 아닙니다'; end if;
  if s.break_start is not null and new.time::time<s.break_end and new.time::time+make_interval(mins=>new.duration_minutes)>s.break_start then raise exception '점심·휴식 시간에는 예약할 수 없습니다'; end if;
 end if;
 return new;
end $$;
-- 기존 슬롯 트리거가 먼저 예약 스냅샷을 설정한다.
drop trigger if exists desk_z_break_validation on public.desk_bookings;
create trigger desk_z_break_validation before insert or update on public.desk_bookings for each row execute function public.desk_check_break_and_reactivation();
revoke all on function public.desk_check_break_and_reactivation() from public;
create or replace function public.desk_booking_stats(target uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; today date=(now() at time zone 'Asia/Seoul')::date; begin
 select jsonb_build_object('customers',(select count(*) from public.desk_customers where shop_id=target),'bookings_total',count(*),'by_status',jsonb_build_object('requested',count(*) filter(where status='requested'),'confirmed',count(*) filter(where status='confirmed'),'done',count(*) filter(where status='done'),'cancelled',count(*) filter(where status='cancelled'),'noshow',count(*) filter(where status='noshow')),'today',count(*) filter(where date=today),'upcoming_requested_or_confirmed',count(*) filter(where date>=today and status in ('requested','confirmed')),'booked_last_7days',count(*) filter(where created_at>=now()-interval '7 days')) into result from public.desk_bookings where shop_id=target;
 return result;
end $$;
revoke all on function public.desk_booking_stats(uuid) from public,anon;
grant execute on function public.desk_booking_stats(uuid) to authenticated,service_role;
commit;
