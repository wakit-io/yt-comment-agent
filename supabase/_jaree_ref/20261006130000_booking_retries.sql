begin;
create table if not exists public.desk_booking_requests(
 shop_id uuid not null references public.desk_shops(id) on delete cascade,
 request_id uuid not null,
 payload_hash text not null check(payload_hash ~ '^[0-9a-f]{64}$'),
 actor_user_id uuid references auth.users(id) on delete set null,
 booking_id uuid not null references public.desk_bookings(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(shop_id,request_id)
);
alter table public.desk_booking_requests enable row level security;
revoke all on public.desk_booking_requests from anon,authenticated;
grant select,insert,update,delete on public.desk_booking_requests to service_role;
create or replace function public.desk_insert_retryable_booking(booking_data jsonb,customer_user uuid,token_hash text,request_key uuid,fingerprint text,request_actor uuid)
returns public.desk_bookings language plpgsql security invoker set search_path='' as $$
declare b public.desk_bookings; previous public.desk_booking_requests; shop uuid=(booking_data->>'shop_id')::uuid; customer uuid; phone_number text=coalesce(booking_data->>'phone','');
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(shop::text||':'||request_key::text,0));
 select * into previous from public.desk_booking_requests where shop_id=shop and request_id=request_key;
 if found then
  if previous.payload_hash<>fingerprint or previous.actor_user_id is distinct from request_actor then raise exception '같은 요청번호를 다른 예약에 사용할 수 없습니다'; end if;
  if token_hash is not null and not exists(select 1 from public.desk_booking_access where booking_id=previous.booking_id and guest_token_hash=token_hash) then raise exception '확인키가 변경되었습니다. 예약 내역을 조회하거나 상점에 문의해주세요'; end if;
  select * into b from public.desk_bookings where id=previous.booking_id and shop_id=shop;
  return b;
 end if;
 if phone_number<>'' then
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(shop::text||':phone:'||phone_number,0));
  select id into customer from public.desk_customers where shop_id=shop and phone=phone_number order by created_at,id limit 1;
 end if;
 if customer is null then
  insert into public.desk_customers(shop_id,name,phone) values(shop,booking_data->>'customer_name',phone_number) returning id into customer;
  insert into public.desk_events(shop_id,entity,entity_id,action,detail,actor,actor_user_id)values(shop,'customer',customer,'created','신규 고객 '||(booking_data->>'customer_name'),booking_data->>'source',request_actor);
 end if;
 insert into public.desk_bookings(shop_id,customer_id,customer_name,phone,service,service_id,date,time,message,source,status)
 values(shop,customer,booking_data->>'customer_name',phone_number,booking_data->>'service',(booking_data->>'service_id')::uuid,(booking_data->>'date')::date,booking_data->>'time',coalesce(booking_data->>'message',''),booking_data->>'source','requested') returning * into b;
 if token_hash is not null then insert into public.desk_booking_access(booking_id,user_id,guest_token_hash) values(b.id,customer_user,token_hash); end if;
 insert into public.desk_booking_requests(shop_id,request_id,payload_hash,actor_user_id,booking_id)values(shop,request_key,fingerprint,request_actor,b.id);
 insert into public.desk_events(shop_id,entity,entity_id,action,detail,actor,actor_user_id)values(shop,'booking',b.id,'created',(booking_data->>'customer_name')||' · '||(booking_data->>'service')||' · '||(booking_data->>'date')||' '||(booking_data->>'time'),booking_data->>'source',request_actor);
 return b;
end $$;
revoke all on function public.desk_insert_retryable_booking(jsonb,uuid,text,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.desk_insert_retryable_booking(jsonb,uuid,text,uuid,text,uuid) to service_role;
commit;
