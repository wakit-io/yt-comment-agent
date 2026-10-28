-- 고객 후기 — 공개 작성(별점+내용) → 관리자 승인(status) → 공개. 관리자 답변(reply).
create table if not exists fl_reviews (
  id              uuid primary key default gen_random_uuid(),
  author_name     text not null,
  rating          int  not null default 5 check (rating between 1 and 5),
  service         text,                                   -- 어떤 작업/서비스였는지(선택)
  content         text not null,
  status          text not null default 'pending',        -- pending | published | hidden
  reply           text,                                   -- 관리자 답변
  reply_at        timestamptz,
  consent_at      timestamptz,                            -- 공개·수집 동의 일시
  consent_version text,
  submission_key  text,                                   -- 중복 제출 방지
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists fl_reviews_status on fl_reviews(status, created_at desc);
create unique index if not exists fl_reviews_subkey on fl_reviews(submission_key) where submission_key is not null;
drop trigger if exists fl_reviews_touch on fl_reviews;
create trigger fl_reviews_touch before update on fl_reviews for each row execute function fl_touch();
alter table fl_reviews enable row level security;
-- RLS 정책 없음 = 기본 거부(서버 service_role만 접근). 공개 조회/작성은 서버 API 경유.
