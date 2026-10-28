-- 일정(캘린더) — 프리랜서 직접 등록 이벤트. 프로젝트 시작/마감은 조회 시 병합(중복생성 없음).
create table if not exists fl_calendar_events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  start_at timestamptz not null,
  end_at timestamptz,
  all_day boolean default true,
  project_id uuid references fl_projects(id) on delete set null,
  note text default '',
  color text default '',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
drop trigger if exists fl_calendar_events_touch on fl_calendar_events;
create trigger fl_calendar_events_touch before update on fl_calendar_events for each row execute function fl_touch();
alter table fl_calendar_events enable row level security;
create index if not exists idx_fl_cal_start on fl_calendar_events(start_at);
