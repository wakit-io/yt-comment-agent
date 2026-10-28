-- 관리자 메뉴(모듈) 표시 토글.
-- 선택 모듈(todos/portfolio/reviews 등)은 기본 숨김 → 설정에서 켜면 사이드바에 표시.
-- 빈 {} = 선택 모듈 전부 숨김. { "todos": true } 처럼 키=true 면 표시.
alter table fl_site add column if not exists modules jsonb not null default '{}'::jsonb;
