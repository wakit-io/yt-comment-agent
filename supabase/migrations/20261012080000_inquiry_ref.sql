-- 의뢰 참고 작업/사이트 — 포트폴리오에서 "이 작업처럼 문의"로 넘어온 참조 링크.
alter table fl_inquiries add column if not exists ref_url text;
alter table fl_inquiries add column if not exists ref_label text;
