-- 운영자 플래너(락인 기능): 월별 일정(캘린더) · 할일 · 일자별 메모.
-- 전부 상점 소속 회원이 CRUD. 웹 관리자 + MCP 공유.
begin;

-- 일정(캘린더)
create table if not exists public.desk_calendar(
 id uuid primary key default gen_random_uuid(),
 shop_id uuid not null references public.desk_shops(id) on delete cascade,
 title text not null check(length(trim(title)) between 1 and 200),
 date date not null,
 start_time time,
 end_time time,
 location text not null default '' check(length(location)<=200),
 memo text not null default '' check(length(memo)<=2000),
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(start_time is null or end_time is null or start_time<=end_time)
);
create index if not exists desk_calendar_shop_date on public.desk_calendar(shop_id,date);
alter table public.desk_calendar enable row level security;
revoke all on public.desk_calendar from anon;
grant select,insert,update,delete on public.desk_calendar to authenticated;
drop policy if exists desk_calendar_all on public.desk_calendar;
create policy desk_calendar_all on public.desk_calendar for all to authenticated using(public.desk_has_access(shop_id)) with check(public.desk_has_access(shop_id));

-- 할일
create table if not exists public.desk_todos(
 id uuid primary key default gen_random_uuid(),
 shop_id uuid not null references public.desk_shops(id) on delete cascade,
 title text not null check(length(trim(title)) between 1 and 300),
 done boolean not null default false,
 due_date date,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 done_at timestamptz
);
create index if not exists desk_todos_shop on public.desk_todos(shop_id,done,created_at);
alter table public.desk_todos enable row level security;
revoke all on public.desk_todos from anon;
grant select,insert,update,delete on public.desk_todos to authenticated;
drop policy if exists desk_todos_all on public.desk_todos;
create policy desk_todos_all on public.desk_todos for all to authenticated using(public.desk_has_access(shop_id)) with check(public.desk_has_access(shop_id));

-- 일자별 메모
create table if not exists public.desk_notes(
 id uuid primary key default gen_random_uuid(),
 shop_id uuid not null references public.desk_shops(id) on delete cascade,
 date date not null,
 body text not null check(length(trim(body)) between 1 and 4000),
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists desk_notes_shop_date on public.desk_notes(shop_id,date);
alter table public.desk_notes enable row level security;
revoke all on public.desk_notes from anon;
grant select,insert,update,delete on public.desk_notes to authenticated;
drop policy if exists desk_notes_all on public.desk_notes;
create policy desk_notes_all on public.desk_notes for all to authenticated using(public.desk_has_access(shop_id)) with check(public.desk_has_access(shop_id));

commit;
