-- 서비스 카탈로그와 서비스별 예약 시간. 기존 예약은 그대로 보존한다.
begin;
create extension if not exists btree_gist;
create table if not exists public.desk_services (
 id uuid primary key default gen_random_uuid(),
 shop_id uuid not null references public.desk_shops(id),
 name text not null check(length(trim(name)) between 1 and 100),
 description text not null default '',
 duration_minutes integer not null default 60 check(duration_minutes between 5 and 720),
 slot_interval_minutes integer not null default 30 check(slot_interval_minutes between 5 and 720),
 weekdays integer[] not null default array[1,2,3,4,5] check(cardinality(weekdays) between 1 and 7 and weekdays <@ array[0,1,2,3,4,5,6]),
 start_time time not null default '10:00',
 end_time time not null default '18:00',
 active boolean not null default true,
 booking_enabled boolean not null default false,
 created_at timestamptz not null default now(),
 unique(shop_id,id),unique(shop_id,name),
 check(start_time < end_time and extract(epoch from(end_time-start_time))/60 >= duration_minutes),
 check(extract(second from start_time)=0 and extract(second from end_time)=0)
);
insert into public.desk_services(shop_id,name)
select distinct c.shop_id,left(trim(s),100) from public.desk_config c,
lateral unnest(string_to_array(c.v,'|')) s where c.k='services' and trim(s)<>''
on conflict(shop_id,name) do nothing;
alter table public.desk_services enable row level security;
revoke all on public.desk_services from anon;
grant select,insert,update on public.desk_services to authenticated;
drop policy if exists services_read on public.desk_services;
create policy services_read on public.desk_services for select to authenticated using(public.desk_has_access(shop_id));
drop policy if exists services_insert on public.desk_services;
create policy services_insert on public.desk_services for insert to authenticated with check(public.desk_has_access(shop_id,true));
drop policy if exists services_update on public.desk_services;
create policy services_update on public.desk_services for update to authenticated using(public.desk_has_access(shop_id,true)) with check(public.desk_has_access(shop_id,true));

alter table public.desk_bookings add column if not exists service_id uuid;
alter table public.desk_bookings add column if not exists duration_minutes integer;
alter table public.desk_bookings add column if not exists start_at timestamptz;
alter table public.desk_bookings add column if not exists end_at timestamptz;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='desk_bookings_service_shop_fkey' and conrelid='public.desk_bookings'::regclass) then
 alter table public.desk_bookings add constraint desk_bookings_service_shop_fkey foreign key(shop_id,service_id) references public.desk_services(shop_id,id);
 end if;
 if not exists(select 1 from pg_constraint where conname='desk_bookings_no_overlap' and conrelid='public.desk_bookings'::regclass) then
 alter table public.desk_bookings add constraint desk_bookings_no_overlap exclude using gist
 (service_id with =,tstzrange(start_at,end_at,'[)') with &&)
 where(service_id is not null and status in ('requested','confirmed'));
 end if;
end $$;

create or replace function public.desk_validate_slot() returns trigger language plpgsql set search_path='' as $$
declare s public.desk_services; t time; minute_offset numeric; changed boolean;
begin
 if new.status not in ('requested','confirmed','done','cancelled','noshow') then raise exception '잘못된 예약 상태'; end if;
 if tg_op='INSERT' and new.service_id is null then raise exception '서비스를 선택해주세요'; end if;
 -- 이전 자유 형식 예약은 소급해서 시간 예약으로 변환하지 않는다.
 if new.service_id is null then
  if tg_op='UPDATE' and old.service_id is not null then raise exception '예약 서비스를 제거할 수 없습니다'; end if;
  return new;
 end if;
 if tg_op='INSERT' then changed=true;
 else changed=new.service_id is distinct from old.service_id or new.date is distinct from old.date or new.time is distinct from old.time or new.shop_id is distinct from old.shop_id;
 end if;
 if changed then
  select * into s from public.desk_services where shop_id=new.shop_id and id=new.service_id for share;
  if not found or not s.active or not s.booking_enabled then raise exception '예약 가능한 서비스가 아닙니다'; end if;
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
  -- 서비스 설정이 바뀌어도 이미 접수한 예약의 소요 시간·이름은 보존한다.
  if new.start_at is distinct from old.start_at or new.end_at is distinct from old.end_at or new.duration_minutes is distinct from old.duration_minutes or new.service is distinct from old.service then raise exception '예약 일정을 통해 서비스 정보를 변경해주세요'; end if;
 end if;
 return new;
end $$;
drop trigger if exists desk_slot_validation on public.desk_bookings;
create trigger desk_slot_validation before insert or update on public.desk_bookings for each row execute function public.desk_validate_slot();
revoke all on function public.desk_validate_slot() from public;

-- 신규 상점은 운영자가 서비스 관리에서 서비스를 직접 생성한다.
create or replace function public.desk_create_shop(shop_slug text,shop_name text)
returns public.desk_shops language plpgsql security definer set search_path=''
as $$ declare s public.desk_shops; begin
 if auth.uid() is null then raise exception '로그인 필요'; end if;
 if shop_slug !~ '^[a-z0-9][a-z0-9-]{2,39}$' or length(trim(shop_name)) not between 1 and 100 then raise exception '잘못된 상점 정보'; end if;
 insert into public.desk_shops(slug,name) values(shop_slug,trim(shop_name)) returning * into s;
 insert into public.desk_shop_members(shop_id,user_id,role) values(s.id,auth.uid(),'owner');
 insert into public.desk_config(shop_id,k,v) values
 (s.id,'biz_name',trim(shop_name)),(s.id,'biz_tagline','당신을 위한 특별한 공간'),
 (s.id,'description','우리 상점을 소개해주세요.'),(s.id,'accent','#4f46e5'),(s.id,'hours','예약제로 운영합니다');
 return s;
end $$;
commit;
