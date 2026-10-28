-- MCP OAuth 상태 저장소(멀티테넌트). client/code/refresh 를 서버리스 함수에서 공유 영속.
-- service_role 전용(RLS로 anon/authenticated 차단, service_role은 RLS 우회).
begin;
create table if not exists public.desk_mcp_oauth(
 kind text not null,
 k text not null,
 v jsonb not null,
 exp bigint,
 created_at timestamptz not null default now(),
 primary key(kind,k)
);
alter table public.desk_mcp_oauth enable row level security;
revoke all on public.desk_mcp_oauth from anon,authenticated;
grant select,insert,update,delete on public.desk_mcp_oauth to service_role;
commit;
