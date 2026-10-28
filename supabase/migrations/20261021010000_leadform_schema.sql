-- ─────────────────────────────────────────────────────────────
-- 유연 접수폼 시스템 (sparse wide-table / 엑셀식 범용 컬럼)
--   lf_forms        : 폼 정의
--   lf_form_fields  : 필드 메타(어느 슬롯 f01~f30 = 무슨 라벨/타입)  ← 에이전트가 MCP로 채움
--   lf_submissions  : 접수 데이터(id 고유인덱스 + f01~f30 범용 TEXT 컬럼)
-- 폼 만들기 = 메타 insert만(ALTER 없음). 컬럼이 진짜라 엑셀 export/필터가 쉬움.
-- ─────────────────────────────────────────────────────────────

create table if not exists lf_forms (
  id          uuid primary key default gen_random_uuid(),
  owner       uuid not null default auth.uid(),
  title       text not null default '새 접수폼',
  slug        text not null,
  description text not null default '',
  active      boolean not null default true,
  settings    jsonb not null default '{}'::jsonb,   -- submit_label, success_message, theme 등
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (owner, slug)
);

create table if not exists lf_form_fields (
  id          uuid primary key default gen_random_uuid(),
  form_id     uuid not null references lf_forms(id) on delete cascade,
  slot        text not null,                         -- 'f01' ~ 'f30' (submissions 컬럼 매핑)
  label       text not null,                         -- 표시 라벨 ("이름", "연락처"…)
  type        text not null default 'text',          -- text/textarea/tel/email/number/date/select/radio/checkbox/file
  required    boolean not null default false,
  placeholder text not null default '',
  options     jsonb not null default '[]'::jsonb,    -- select/radio/checkbox 선택지
  sort        integer not null default 0,            -- 노출 순서
  created_at  timestamptz not null default now(),
  unique (form_id, slot),
  constraint lf_field_slot_chk check (slot ~ '^f(0[1-9]|[12][0-9]|30)$')
);

create table if not exists lf_submissions (
  id        uuid primary key default gen_random_uuid(),   -- 고유 인덱스
  form_id   uuid not null references lf_forms(id) on delete cascade,
  status    text not null default 'new',                  -- new/reviewing/done/hold/closed
  note      text not null default '',                     -- 관리자 메모
  source    text not null default '',                     -- 유입 경로
  -- 범용 값 컬럼(엑셀식). 전부 TEXT — 타입/라벨은 lf_form_fields가 정의.
  f01 text, f02 text, f03 text, f04 text, f05 text, f06 text, f07 text, f08 text, f09 text, f10 text,
  f11 text, f12 text, f13 text, f14 text, f15 text, f16 text, f17 text, f18 text, f19 text, f20 text,
  f21 text, f22 text, f23 text, f24 text, f25 text, f26 text, f27 text, f28 text, f29 text, f30 text,
  created_at timestamptz not null default now()
);

create index if not exists lf_forms_owner_idx      on lf_forms(owner);
create index if not exists lf_form_fields_form_idx on lf_form_fields(form_id, sort);
create index if not exists lf_submissions_form_idx on lf_submissions(form_id, created_at desc);

-- RLS: 기본 거부 = 서버(service_role)만 접근. 소유자 체크는 앱(authUser)에서.
--   공개 폼 제출도 서버 API(/forms/:slug/submit)가 service_role로 검증 후 insert → 공개 정책 불필요.
alter table lf_forms        enable row level security;
alter table lf_form_fields  enable row level security;
alter table lf_submissions  enable row level security;

-- Supabase 2026-10-30 대응: 신규 테이블 Data API 권한 자동부여 중단 → service_role 명시 GRANT.
grant all on lf_forms, lf_form_fields, lf_submissions to service_role;
