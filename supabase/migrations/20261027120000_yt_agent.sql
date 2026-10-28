-- YT 댓글 어시스턴트 스키마 (대시보드 + 앞단 랜딩 공용). 접두 yt_.
-- 설계: 단일 운영자(owner) 모델. 서버 라우트가 service_role 로 접근, 게이팅은 authenticate.

-- 본인 YouTube OAuth 토큰(게시용). 운영자당 1행.
create table if not exists public.yt_oauth (
  owner_id      uuid primary key,
  channel_id    text,
  channel_title text,
  access_token  text,
  refresh_token text,
  expiry        timestamptz,
  scope         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- 불러온 영상 캐시(검색 결과 + 선택 시 맥락).
create table if not exists public.yt_video (
  id            text primary key,          -- youtube videoId
  title         text,
  channel_id    text,
  channel_title text,
  published_at  timestamptz,
  thumb         text,
  view_count    bigint,
  like_count    bigint,
  comment_count bigint,
  duration      text,
  description   text,
  context       jsonb,                      -- { caption_text?, top_comments[], worry_oneline? }
  fetched_at    timestamptz not null default now()
);

-- AI 댓글 초안.
create table if not exists public.yt_draft (
  id            uuid primary key default gen_random_uuid(),
  video_id      text,
  worry_oneline text,                       -- 영상 속 고민 한 줄
  body          text,                        -- 댓글 초안
  provider      text,
  model         text,
  created_at    timestamptz not null default now()
);

-- 게시 기록(운영규칙 집행 + 시간순 로그 + 랜딩 후기 소스).
create table if not exists public.yt_log (
  id           uuid primary key default gen_random_uuid(),
  video_id     text,
  video_title  text,
  video_link   text,
  profile      text,                         -- 어느 프로필/계정으로
  body         text,                         -- 실제 게시한 댓글
  status       text not null default 'queued', -- queued|posting|posted|failed
  success      boolean,
  error        text,
  comment_id   text,
  comment_link text,
  featured     boolean not null default false, -- 랜딩에 후기로 노출
  created_at   timestamptz not null default now()
);
create index if not exists yt_log_created_idx on public.yt_log (created_at desc);
create index if not exists yt_log_video_idx   on public.yt_log (video_id);

-- 운영 설정(단일행). 운영규칙·브랜드·AI·랜딩 메타.
create table if not exists public.yt_setting (
  id                 int primary key default 1,
  min_chars          int  not null default 40,
  max_chars          int  not null default 120,
  brand              text not null default '운명원',
  daily_max_comments int  not null default 10,
  provider           text not null default 'google',
  model              text not null default '',
  profiles           jsonb not null default '["유튜브1"]'::jsonb,
  landing            jsonb not null default '{}'::jsonb,  -- 채널 랜딩(소개/CTA/채널링크)
  updated_at         timestamptz not null default now()
);
insert into public.yt_setting (id) values (1) on conflict (id) do nothing;

-- ★서비스롤 명시 GRANT (2026-10-30 이후 자동부여 중단 대비 — prod 안전).
grant all on public.yt_oauth, public.yt_video, public.yt_draft, public.yt_log, public.yt_setting to service_role;
