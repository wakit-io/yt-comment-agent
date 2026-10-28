-- 소유자 잠금 — 첫 가입/첫 로그인 사용자를 워크스페이스 주인으로 기록. 이후 그 사람만 관리자.
alter table fl_site add column if not exists owner_user_id uuid;
