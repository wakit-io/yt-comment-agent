-- ═══ Supabase 10/30 대응: Data API GRANT 패스 (service_role 전용) ═══
-- 이 제품은 서버/MCP가 service_role 키로만 테이블 접근(RLS 우회 + 앱레벨 owner 필터).
-- anon/authenticated는 테이블 직접 미사용(로그인은 auth 스키마=GoTrue).
-- 2026-10-30부터 Supabase가 신규 테이블 Data API 권한 자동부여 중단 → 명시 GRANT 없으면 42501.
-- service_role 전용 부여 = 외부 노출 없음(서버 전용 키). 멱등(재실행 안전).
grant usage  on schema public to service_role;
grant all on all tables     in schema public to service_role;
grant all on all sequences  in schema public to service_role;
grant all on all functions  in schema public to service_role;
-- 향후 추가 테이블/시퀀스/함수도 자동 커버(다음 마이그레이션 안전)
alter default privileges in schema public grant all     on tables    to service_role;
alter default privileges in schema public grant all     on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;
