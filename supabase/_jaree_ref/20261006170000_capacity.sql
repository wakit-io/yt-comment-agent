-- 정원(인원수) 기능. 서비스별 capacity + 방식(single: 1건=1자리 / party: 예약마다 인원수).
-- 기존 '정원 1' 하드코딩(배타 제약)을 서비스 행 잠금 기반 카운트 검사로 교체한다.
begin;
alter table public.desk_services add column if not exists capacity integer not null default 1 check(capacity between 1 and 1000);
alter table public.desk_services add column if not exists capacity_mode text not null default 'single' check(capacity_mode in ('single','party'));
alter table public.desk_bookings add column if not exists party_size integer not null default 1 check(party_size between 1 and 1000);

-- 정원>1 허용: 한 시간대 1건만 받던 배타 제약 제거(아래 트리거가 합계로 제어)
alter table public.desk_bookings drop constraint if exists desk_bookings_no_overlap;

-- 예약 검증 + 정원(인원) 검사 통합. 서비스 행을 for update로 잠가 동시 예약 레이스를 직렬화한다.
create or replace function public.desk_validate_slot() returns trigger language plpgsql set search_path='' as $$
declare s public.desk_services; t time; minute_offset numeric; changed boolean; used integer;
begin
 if new.status not in ('requested','confirmed','done','cancelled','noshow') then raise exception '잘못된 예약 상태'; end if;
 if tg_op='INSERT' and new.service_id is null then raise exception '서비스를 선택해주세요'; end if;
 if new.service_id is null then
  if tg_op='UPDATE' and old.service_id is not null then raise exception '예약 서비스를 제거할 수 없습니다'; end if;
  return new;
 end if;
 select * into s from public.desk_services where shop_id=new.shop_id and id=new.service_id for update;
 if not found then raise exception '예약 가능한 서비스가 아닙니다'; end if;
 if tg_op='INSERT' then changed=true;
 else changed=new.service_id is distinct from old.service_id or new.date is distinct from old.date or new.time is distinct from old.time or new.shop_id is distinct from old.shop_id;
 end if;
 if changed then
  if not s.active or not s.booking_enabled then raise exception '예약 가능한 서비스가 아닙니다'; end if;
  if new.date is null or new.time is null or new.time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception '예약 날짜와 시간을 선택해주세요'; end if;
  t=new.time::time;
  minute_offset=extract(epoch from(t-s.start_time))/60;
  if not(extract(dow from new.date)::integer=any(s.weekdays)) or minute_offset<0 or minute_offset+s.duration_minutes>extract(epoch from(s.end_time-s.start_time))/60 or mod(minute_offset,s.slot_interval_minutes)<>0 then raise exception '서비스의 예약 가능 시간이 아닙니다'; end if;
  new.start_at=(new.date+t) at time zone 'Asia/Seoul';
  new.end_at=new.start_at+make_interval(mins=>s.duration_minutes);
  if new.start_at<=now() then raise exception '지난 시간에는 예약할 수 없습니다'; end if;
  new.duration_minutes=s.duration_minutes;
  new.service=s.name;
 else
  if new.start_at is distinct from old.start_at or new.end_at is distinct from old.end_at or new.duration_minutes is distinct from old.duration_minutes or new.service is distinct from old.service then raise exception '예약 일정을 통해 서비스 정보를 변경해주세요'; end if;
 end if;
 -- 정원(인원) 검사: 활성(접수/확정) 예약에만 적용
 if new.status in ('requested','confirmed') and new.start_at is not null then
  if new.party_size is null or new.party_size<1 then new.party_size=1; end if;
  if s.capacity_mode='single' then new.party_size=1; end if;
  if new.party_size>s.capacity then raise exception '예약 인원이 정원(%명)을 초과했습니다', s.capacity; end if;
  select coalesce(sum(b.party_size),0) into used from public.desk_bookings b
   where b.service_id=new.service_id and b.status in ('requested','confirmed') and b.id<>new.id
     and tstzrange(b.start_at,b.end_at,'[)') && tstzrange(new.start_at,new.end_at,'[)');
  if used+new.party_size>s.capacity then raise exception '정원이 찼습니다. 다른 시간을 선택해주세요' using errcode='23P01'; end if;
 end if;
 return new;
end $$;
drop trigger if exists desk_slot_validation on public.desk_bookings;
create trigger desk_slot_validation before insert or update on public.desk_bookings for each row execute function public.desk_validate_slot();
revoke all on function public.desk_validate_slot() from public;

-- 예약 insert RPC에 party_size 반영
create or replace function public.desk_insert_customer_booking(booking_data jsonb, customer_user uuid, token_hash text)
returns public.desk_bookings language plpgsql set search_path='' as $$
declare b public.desk_bookings;
begin
 insert into public.desk_bookings(shop_id,customer_id,customer_name,phone,service,service_id,date,time,message,source,status,party_size)
 values((booking_data->>'shop_id')::uuid,(booking_data->>'customer_id')::uuid,booking_data->>'customer_name',booking_data->>'phone',booking_data->>'service',(booking_data->>'service_id')::uuid,(booking_data->>'date')::date,booking_data->>'time',booking_data->>'message','web','requested',coalesce((booking_data->>'party_size')::int,1)) returning * into b;
 insert into public.desk_booking_access(booking_id,user_id,guest_token_hash) values(b.id,customer_user,token_hash);
 return b;
end $$;
revoke all on function public.desk_insert_customer_booking(jsonb,uuid,text) from public,anon,authenticated;
grant execute on function public.desk_insert_customer_booking(jsonb,uuid,text) to service_role;

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
 insert into public.desk_bookings(shop_id,customer_id,customer_name,phone,service,service_id,date,time,message,source,status,party_size)
 values(shop,customer,booking_data->>'customer_name',phone_number,booking_data->>'service',(booking_data->>'service_id')::uuid,(booking_data->>'date')::date,booking_data->>'time',coalesce(booking_data->>'message',''),booking_data->>'source','requested',coalesce((booking_data->>'party_size')::int,1)) returning * into b;
 if token_hash is not null then insert into public.desk_booking_access(booking_id,user_id,guest_token_hash) values(b.id,customer_user,token_hash); end if;
 insert into public.desk_booking_requests(shop_id,request_id,payload_hash,actor_user_id,booking_id)values(shop,request_key,fingerprint,request_actor,b.id);
 insert into public.desk_events(shop_id,entity,entity_id,action,detail,actor,actor_user_id)values(shop,'booking',b.id,'created',(booking_data->>'customer_name')||' · '||(booking_data->>'service')||' · '||(booking_data->>'date')||' '||(booking_data->>'time'),booking_data->>'source',request_actor);
 return b;
end $$;
revoke all on function public.desk_insert_retryable_booking(jsonb,uuid,text,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.desk_insert_retryable_booking(jsonb,uuid,text,uuid,text,uuid) to service_role;
commit;
