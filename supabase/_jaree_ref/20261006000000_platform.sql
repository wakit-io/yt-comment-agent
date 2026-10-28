-- WAKIT Desk — 1인 매장 예약·고객관리 (Supabase/Postgres). 앞단+관리자+AI(MCP) 공유 데이터.
create extension if not exists pgcrypto;
-- 기존 데이터는 삭제하지 않습니다.

create table if not exists desk_config(
  k text primary key,
  v text
);
create table if not exists desk_customers(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text default '',
  email text default '',
  memo text default '',
  tags text default '',
  created_at timestamptz default now()
);
create table if not exists desk_bookings(
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references desk_customers(id) on delete set null,
  customer_name text not null,
  phone text default '',
  service text default '',
  date date,
  time text default '',
  status text not null default 'requested',  -- requested | confirmed | done | cancelled | noshow
  message text default '',
  source text default 'web',                 -- web | admin | ai
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create table if not exists desk_events(
  id uuid primary key default gen_random_uuid(),
  entity text,            -- booking | customer
  entity_id uuid,
  action text,            -- created | status | note | update
  detail text,
  actor text default 'web',   -- web | admin | claude | chatgpt
  at timestamptz default now()
);
create index if not exists idx_desk_bookings_date on desk_bookings(date);
create index if not exists idx_desk_bookings_status on desk_bookings(status);
create index if not exists idx_desk_events_at on desk_events(at desc);

-- 단일 매장 기본 설정(데모: 라움 스튜디오)
insert into desk_config(k,v) values
 ('biz_name','라움 스튜디오'),
 ('biz_tagline','예약제 1:1 프리미엄 스튜디오'),
 ('services','1:1 개인 레슨|그룹 클래스|촬영 대관'),
 ('hours','평일 10:00–21:00 · 주말 10:00–18:00'),
 ('phone','02-123-4567'),
 ('address','서울시 라움구 스튜디오로 10, 3층')
on conflict (k) do nothing;

-- 기존 단일 상점 스키마에 적용. 기존 데이터는 legacy-studio 상점으로 보존.
begin;
create table if not exists public.desk_shops (
 id uuid primary key default gen_random_uuid(),
 slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,39}$'),
 name text not null,
 published boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.desk_shop_members (
 shop_id uuid not null references public.desk_shops(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check (role in ('owner','staff')),
 primary key(shop_id,user_id)
);
insert into public.desk_shops(slug,name)
values ('legacy-studio',coalesce((select v from public.desk_config where k='biz_name' limit 1),'기존 상점'))
on conflict(slug) do nothing;

alter table public.desk_config add column if not exists shop_id uuid references public.desk_shops(id);
alter table public.desk_customers add column if not exists shop_id uuid references public.desk_shops(id);
alter table public.desk_bookings add column if not exists shop_id uuid references public.desk_shops(id);
alter table public.desk_events add column if not exists shop_id uuid references public.desk_shops(id);
update public.desk_config set shop_id=(select id from public.desk_shops where slug='legacy-studio') where shop_id is null;
update public.desk_customers set shop_id=(select id from public.desk_shops where slug='legacy-studio') where shop_id is null;
update public.desk_bookings set shop_id=(select id from public.desk_shops where slug='legacy-studio') where shop_id is null;
update public.desk_events set shop_id=(select id from public.desk_shops where slug='legacy-studio') where shop_id is null;
alter table public.desk_config alter column shop_id set not null;
alter table public.desk_customers alter column shop_id set not null;
alter table public.desk_bookings alter column shop_id set not null;
alter table public.desk_events alter column shop_id set not null;
alter table public.desk_config drop constraint if exists desk_config_pkey;
alter table public.desk_config add primary key(shop_id,k);
create unique index if not exists desk_customers_shop_id_id on public.desk_customers(shop_id,id);
alter table public.desk_bookings drop constraint if exists desk_bookings_customer_id_fkey;
alter table public.desk_bookings drop constraint if exists desk_bookings_customer_shop_fkey;
alter table public.desk_bookings add constraint desk_bookings_customer_shop_fkey foreign key(shop_id,customer_id) references public.desk_customers(shop_id,id);
create index if not exists desk_customers_shop_phone on public.desk_customers(shop_id,phone);
create index if not exists desk_bookings_shop_date on public.desk_bookings(shop_id,date);
create index if not exists desk_events_shop_at on public.desk_events(shop_id,at desc);

create or replace function public.desk_has_access(target uuid, owner_only boolean default false)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.desk_shop_members where shop_id=target and user_id=auth.uid() and (not owner_only or role='owner')) $$;
revoke all on function public.desk_has_access(uuid,boolean) from public;
grant execute on function public.desk_has_access(uuid,boolean) to authenticated;

alter table public.desk_shops enable row level security;
alter table public.desk_shop_members enable row level security;
alter table public.desk_config enable row level security;
alter table public.desk_customers enable row level security;
alter table public.desk_bookings enable row level security;
alter table public.desk_events enable row level security;
-- 서버의 공개 경로만 서비스 롤로 접근. 브라우저에는 서비스 롤 키를 전달하지 않음.
revoke all on public.desk_shops,public.desk_shop_members,public.desk_config,public.desk_customers,public.desk_bookings,public.desk_events from anon;
grant select,update on public.desk_shops to authenticated;
grant select on public.desk_shop_members to authenticated;
grant select,insert,update on public.desk_config,public.desk_customers,public.desk_bookings,public.desk_events to authenticated;

drop policy if exists shops_read on public.desk_shops;
create policy shops_read on public.desk_shops for select to authenticated using(public.desk_has_access(id));
drop policy if exists shops_update on public.desk_shops;
create policy shops_update on public.desk_shops for update to authenticated using(public.desk_has_access(id,true)) with check(public.desk_has_access(id,true));
drop policy if exists members_read on public.desk_shop_members;
create policy members_read on public.desk_shop_members for select to authenticated using(user_id=auth.uid());

do $$ declare t text; begin
 foreach t in array array['desk_config','desk_customers','desk_bookings','desk_events'] loop
 execute format('drop policy if exists tenant_read on public.%I',t);
 execute format('drop policy if exists tenant_insert on public.%I',t);
 execute format('drop policy if exists tenant_update on public.%I',t);
 execute format('create policy tenant_read on public.%I for select to authenticated using(public.desk_has_access(shop_id))',t);
 execute format('create policy tenant_insert on public.%I for insert to authenticated with check(public.desk_has_access(shop_id,%L))',t,t='desk_config');
 execute format('create policy tenant_update on public.%I for update to authenticated using(public.desk_has_access(shop_id,%L)) with check(public.desk_has_access(shop_id,%L))',t,t='desk_config',t='desk_config');
 end loop;
end $$;

create or replace function public.desk_create_shop(shop_slug text,shop_name text)
returns public.desk_shops language plpgsql security definer set search_path=''
as $$ declare s public.desk_shops; begin
 if auth.uid() is null then raise exception '로그인 필요'; end if;
 if shop_slug !~ '^[a-z0-9][a-z0-9-]{2,39}$' or length(trim(shop_name)) not between 1 and 100 then raise exception '잘못된 상점 정보'; end if;
 insert into public.desk_shops(slug,name) values(shop_slug,trim(shop_name)) returning * into s;
 insert into public.desk_shop_members(shop_id,user_id,role) values(s.id,auth.uid(),'owner');
 insert into public.desk_config(shop_id,k,v) values
 (s.id,'biz_name',trim(shop_name)),(s.id,'biz_tagline','당신을 위한 특별한 공간'),
 (s.id,'description','우리 상점을 소개해주세요.'),(s.id,'services','상담 예약'),
 (s.id,'accent','#4f46e5'),(s.id,'hours','예약제로 운영합니다');
 return s;
end $$;
revoke all on function public.desk_create_shop(text,text) from public;
grant execute on function public.desk_create_shop(text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('desk-assets','desk-assets',true,2097152,array['image/png','image/jpeg','image/webp'])
on conflict(id) do nothing;
drop policy if exists desk_assets_insert on storage.objects;
create policy desk_assets_insert on storage.objects for insert to authenticated
with check(bucket_id='desk-assets' and public.desk_has_access(((storage.foldername(name))[1])::uuid,true));
commit;
