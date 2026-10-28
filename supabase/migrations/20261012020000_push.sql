-- 웹 푸시 구독 — 프리랜서(관리자) 기기별 구독. 발송은 서버(service_role)가 담당.
create table if not exists fl_push_subscriptions (
  endpoint   text primary key,
  p256dh     text not null,
  auth       text not null,
  user_id    uuid,
  ua         text,
  created_at timestamptz not null default now()
);
create index if not exists fl_push_subscriptions_user on fl_push_subscriptions(user_id);
alter table fl_push_subscriptions enable row level security;
-- RLS: anon/authenticated 직접접근 차단(서버 service_role만 읽기/쓰기). 정책 없음 = 기본 거부.
