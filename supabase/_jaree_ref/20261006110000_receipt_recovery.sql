begin;
create or replace function public.desk_rotate_booking_key(target uuid,target_shop uuid,token_hash text,actor_id uuid) returns void language plpgsql security invoker set search_path='' as $$
begin
 perform 1 from public.desk_bookings where id=target and shop_id=target_shop for update;
 if not found then raise exception '예약을 찾을 수 없습니다'; end if;
 insert into public.desk_booking_access(booking_id,guest_token_hash) values(target,token_hash) on conflict(booking_id) do update set guest_token_hash=excluded.guest_token_hash;
 insert into public.desk_events(shop_id,entity,entity_id,action,detail,actor,actor_user_id) values(target_shop,'booking',target,'receipt-reissued','예약 확인키를 재발급했습니다. 이전 확인키는 폐기되었습니다.','admin',actor_id);
end $$;
revoke all on function public.desk_rotate_booking_key(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.desk_rotate_booking_key(uuid,uuid,text,uuid) to service_role;
commit;
