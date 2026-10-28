-- MCP OAuth 상태 저장소(서버리스 함수 공유 영속). kind: client | code | refresh
create table if not exists fl_mcp_oauth (
  kind text not null,
  k    text not null,
  v    jsonb not null,
  exp  bigint,
  primary key (kind, k)
);
alter table fl_mcp_oauth enable row level security;
-- RLS 정책 없음 = 기본 거부(서버 service_role만 접근).
