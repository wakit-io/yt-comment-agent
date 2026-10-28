-- 프리랜서 프로젝트 관리 도구 — 핵심 스키마(MVP). 단일 설치본·관리자 1명.
-- 접근 분리는 서버(service_role)+앱 레벨 검증으로 enforce. RLS는 anon 직접접근 차단(기본 deny).

create extension if not exists "pgcrypto";

-- 공통: updated_at 자동 갱신
create or replace function fl_touch() returns trigger as $$
begin new.updated_at = now(); return new; end; $$ language plpgsql;

-- 사이트 설정(싱글톤 1행)
create table if not exists fl_site (
  id int primary key default 1,
  brand text default '',
  intro jsonb default '{}'::jsonb,         -- name, job, bio, avatar_url, services[], social{}
  contacts jsonb default '{}'::jsonb,       -- email, phone, kakao...
  seo jsonb default '{}'::jsonb,            -- title, description, logo_url
  active_skin_id uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  constraint fl_site_singleton check (id = 1)
);
insert into fl_site (id) values (1) on conflict do nothing;

-- 스킨(HTML/CSS 템플릿)
create table if not exists fl_skins (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  version text default '1.0',
  html text default '',
  css text default '',
  contract_version text default '1',
  state text default 'draft',               -- draft | active | archived
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 포트폴리오
create table if not exists fl_portfolios (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text unique not null,
  started_on date,
  completed_on date,
  content text default '',
  tags text[] default '{}',
  result_url text,
  published boolean default true,
  sort_order int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create table if not exists fl_portfolio_assets (
  id uuid primary key default gen_random_uuid(),
  portfolio_id uuid references fl_portfolios(id) on delete cascade,
  storage_path text not null,
  alt text default '',
  sort_order int default 0,
  created_at timestamptz default now()
);

-- 의뢰(공개폼/수동)
create table if not exists fl_inquiries (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text default '',
  email text default '',
  content text not null,
  budget text default '',                   -- 금액/범위/미정
  source text default 'form',               -- form | manual | phone | email
  state text default 'new',                 -- new | reviewing | converted | hold | closed
  submission_key text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 고객
create table if not exists fl_clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text default '',
  email text default '',
  notes text default '',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 프로젝트
create table if not exists fl_projects (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references fl_clients(id) on delete set null,
  inquiry_id uuid references fl_inquiries(id) on delete set null,
  title text not null,
  description text default '',
  state text default 'quoting',             -- quoting | await_approval | in_progress | review | delivered | archived | cancelled
  start_on date,
  due_on date,
  approved_quote_id uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 견적(일반/추가) + 항목
create table if not exists fl_quotes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references fl_projects(id) on delete cascade,
  revision_id uuid,
  parent_quote_id uuid references fl_quotes(id) on delete set null,
  type text default 'general',              -- general | additional
  version int default 1,
  state text default 'draft',               -- draft | sent | approved | rejected | expired | superseded
  number text,                              -- 견적번호
  issued_on date,
  valid_until date,
  currency text default 'KRW',
  tax_mode text default 'exclusive',        -- exclusive | none
  tax_rate numeric default 0.10,
  subtotal bigint default 0,                -- KRW 정수(원)
  tax bigint default 0,
  total bigint default 0,
  scope text default '',
  exclusions text default '',
  terms text default '',
  snapshot jsonb,                           -- 발행 시점 고객/발행자/항목/합계 스냅샷
  approved_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create table if not exists fl_quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid references fl_quotes(id) on delete cascade,
  name text not null,
  description text default '',
  quantity numeric default 1,
  unit_price bigint default 0,              -- KRW 정수
  amount bigint default 0,
  sort_order int default 0
);

-- 수정 요청
create table if not exists fl_revisions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references fl_projects(id) on delete cascade,
  title text not null,
  target text default '',
  current_content text default '',
  requested_change text default '',
  state text default 'received',            -- received | reviewing | working | done | hold
  internal_note text default '',
  public_reply text default '',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 납품
create table if not exists fl_deliveries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references fl_projects(id) on delete cascade,
  title text not null,
  version int default 1,
  content text default '',
  links jsonb default '[]'::jsonb,
  state text default 'draft',               -- draft | ready | sent
  email_state text default 'none',          -- none | sent | failed
  delivered_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 고객 전용 링크(토큰 해시)
create table if not exists fl_client_links (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references fl_projects(id) on delete cascade,
  token_hash text unique not null,
  label text default '',
  capabilities jsonb default '["quote","revision","delivery"]'::jsonb,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz default now()
);

-- updated_at 트리거
do $$ declare t text;
begin
  foreach t in array array['fl_site','fl_skins','fl_portfolios','fl_inquiries','fl_clients','fl_projects','fl_quotes','fl_revisions','fl_deliveries']
  loop
    execute format('drop trigger if exists %I_touch on %I', t, t);
    execute format('create trigger %I_touch before update on %I for each row execute function fl_touch()', t, t);
  end loop;
end $$;

-- RLS: 모든 테이블 켜고 정책 없음 → anon/authenticated 직접 접근 차단. 서버는 service_role로 접근(RLS 우회) + 앱레벨 검증.
do $$ declare t text;
begin
  foreach t in array array['fl_site','fl_skins','fl_portfolios','fl_portfolio_assets','fl_inquiries','fl_clients','fl_projects','fl_quotes','fl_quote_items','fl_revisions','fl_deliveries','fl_client_links']
  loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- 인덱스
create index if not exists idx_fl_portfolios_pub on fl_portfolios(published, sort_order);
create index if not exists idx_fl_projects_state on fl_projects(state);
create index if not exists idx_fl_quotes_project on fl_quotes(project_id);
create index if not exists idx_fl_quote_items_quote on fl_quote_items(quote_id);
create index if not exists idx_fl_revisions_project on fl_revisions(project_id);
create index if not exists idx_fl_deliveries_project on fl_deliveries(project_id);
