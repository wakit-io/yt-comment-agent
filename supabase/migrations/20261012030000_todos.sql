-- 할일(To-do) — 날짜/시간 있는 작업 목록. 완료 체크.
create table if not exists fl_todos (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  due_on     date not null default (now() at time zone 'Asia/Seoul')::date,
  due_time   time,                 -- null = 시간 미지정(종일 할일)
  note       text,
  project_id uuid references fl_projects(id) on delete set null,
  done       boolean not null default false,
  done_at    timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists fl_todos_due on fl_todos(due_on);
create index if not exists fl_todos_done on fl_todos(done);
drop trigger if exists fl_todos_touch on fl_todos;
create trigger fl_todos_touch before update on fl_todos for each row execute function fl_touch();
alter table fl_todos enable row level security;
-- RLS 정책 없음 = 기본 거부(서버 service_role만 접근).

-- 캘린더 일정도 할일에서 완료 체크 가능하도록 done_at 추가(날짜 도래 시 할일로 끌어옴).
alter table fl_calendar_events add column if not exists done_at timestamptz;
