-- 프리랜서 잔재 제거 (CMS로 전환). 되돌릴 수 없음.
-- 1) calendar/todos 의 project_id(→fl_projects FK) 컬럼 제거
alter table if exists fl_calendar_events drop column if exists project_id;
alter table if exists fl_todos drop column if exists project_id;

-- 2) 프리랜서 전용 테이블 제거 (견적·프로젝트·고객·납품·수정·링크)
drop table if exists fl_client_links cascade;
drop table if exists fl_quote_items cascade;
drop table if exists fl_quotes cascade;
drop table if exists fl_revisions cascade;
drop table if exists fl_deliveries cascade;
drop table if exists fl_projects cascade;
drop table if exists fl_clients cascade;
