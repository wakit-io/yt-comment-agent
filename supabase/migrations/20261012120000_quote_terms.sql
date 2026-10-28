-- 견적 전용 조건칸: 수정 횟수·취소 조건·저작권(2차 이용).
alter table fl_quotes add column if not exists revisions text default '';
alter table fl_quotes add column if not exists cancel_terms text default '';
alter table fl_quotes add column if not exists copyright text default '';
