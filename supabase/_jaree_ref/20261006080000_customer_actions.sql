begin;
create or replace function public.desk_customer_change_booking(target uuid,operation text,new_date date default null,new_time text default null,actor_id uuid default null) returns void language plpgsql security invoker set search_path='' as $$
declare b public.desk_bookings; begin
 select * into b from public.desk_bookings where id=target for update;
 if not found or b.status not in ('requested','confirmed') or b.start_at is null or b.start_at<=now() then raise exception '이 예약은 취소·변경할 수 없습니다. 상점에 문의해주세요'; end if;
 if operation='cancel' then update public.desk_bookings set status='cancelled',updated_at=now() where id=target;
 elsif operation='reschedule' then
  if new_date is null or new_time is null then raise exception '변경할 날짜와 시간을 선택해주세요'; end if;
  update public.desk_bookings set date=new_date,time=new_time,status='requested',updated_at=now() where id=target;
 else raise exception '잘못된 예약 변경 요청'; end if;
 insert into public.desk_events(shop_id,entity,entity_id,action,detail,actor,actor_user_id) values(b.shop_id,'booking',b.id,operation,case when operation='cancel' then '고객이 예약을 취소했습니다' else '고객 일정 변경: '||new_date::text||' '||new_time||' · 운영자 재확인 필요' end,'customer',actor_id);
end $$;
revoke all on function public.desk_customer_change_booking(uuid,text,date,text,uuid) from public,anon,authenticated;
grant execute on function public.desk_customer_change_booking(uuid,text,date,text,uuid) to service_role;
commit;
