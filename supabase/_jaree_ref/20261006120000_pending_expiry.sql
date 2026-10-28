begin;
alter table public.desk_services add column if not exists pending_expiry_minutes integer check(pending_expiry_minutes between 15 and 10080);
alter table public.desk_bookings add column if not exists pending_expires_at timestamptz;
create index if not exists desk_pending_expiry on public.desk_bookings(shop_id,pending_expires_at) where status='requested';
create or replace function public.desk_set_pending_expiry() returns trigger language plpgsql set search_path='' as $$
declare mins integer; changed boolean; begin
 if tg_op='INSERT' then changed=true;
 else
  if old.status='requested' and old.pending_expires_at<=now() and new.status in ('requested','confirmed') then raise exception '접수 대기 시간이 만료되었습니다'; end if;
  changed=new.status is distinct from old.status or new.date is distinct from old.date or new.time is distinct from old.time or new.service_id is distinct from old.service_id;
 end if;
 if new.status<>'requested' then new.pending_expires_at=null;
 elsif changed then
  select pending_expiry_minutes into mins from public.desk_services where id=new.service_id and shop_id=new.shop_id;
  new.pending_expires_at=case when mins is null then null else now()+make_interval(mins=>mins) end;
 elsif new.pending_expires_at is distinct from old.pending_expires_at then raise exception '대기 만료 시각을 직접 변경할 수 없습니다';
 end if;
 return new;
end $$;
drop trigger if exists desk_zzz_pending_expiry on public.desk_bookings;
create trigger desk_zzz_pending_expiry before insert or update on public.desk_bookings for each row execute function public.desk_set_pending_expiry();
revoke all on function public.desk_set_pending_expiry() from public;
create or replace function public.desk_expire_pending(target_shop uuid) returns void language sql security invoker set search_path='' as $$
 with expired as(update public.desk_bookings set status='cancelled',updated_at=now() where shop_id=target_shop and status='requested' and pending_expires_at<=now() returning id,shop_id)
 insert into public.desk_events(shop_id,entity,entity_id,action,detail,actor) select shop_id,'booking',id,'expired','접수 대기 시간이 만료되어 자동 취소되었습니다','system' from expired;
$$;
revoke all on function public.desk_expire_pending(uuid) from public,anon,authenticated;
grant execute on function public.desk_expire_pending(uuid) to service_role;
commit;
