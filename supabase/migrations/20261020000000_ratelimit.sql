-- 레이트리밋 토큰버킷 — request-limits.mjs의 desk_take_request RPC 구현.
-- 로그인/OAuth 승인 등 무차별 대입(brute-force) 방어. 반환 true=허용, false=차단.
-- (wakit-assistant에는 있었으나 freelancer에 누락돼 있던 것 → 보강. fail-open이라 없어도 크래시는 없으나 방어가 꺼짐)
create table if not exists rl_bucket (
  key      text primary key,
  hits     integer not null default 0,
  reset_at timestamptz not null default now()
);
alter table rl_bucket enable row level security;  -- 정책 없음 = service_role만.

create or replace function desk_take_request(bucket_key text, max_hits integer, window_seconds integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare cur rl_bucket%rowtype;
begin
  insert into rl_bucket (key, hits, reset_at)
    values (bucket_key, 1, now() + make_interval(secs => window_seconds))
  on conflict (key) do update set
    hits     = case when rl_bucket.reset_at < now() then 1 else rl_bucket.hits + 1 end,
    reset_at = case when rl_bucket.reset_at < now() then now() + make_interval(secs => window_seconds) else rl_bucket.reset_at end
  returning * into cur;
  return cur.hits <= max_hits;
end $$;

create index if not exists rl_bucket_reset_idx on rl_bucket(reset_at);
