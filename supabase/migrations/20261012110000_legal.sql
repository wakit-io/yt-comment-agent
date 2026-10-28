-- 법적 고지(개인정보처리방침·이용약관) 설정 + 의뢰 동의 기록.
-- 처리방침/약관 본문은 site 데이터로 "생성"하고, 운영자 입력값은 여기에 저장.
alter table fl_site add column if not exists legal jsonb not null default '{}'::jsonb;
-- legal: { officer, retention, effective, uses_ai, policy_custom, terms_enabled, terms_custom, consent_version }

-- 의뢰 접수 시 동의 기록(일시·문구 버전) 보관 — 입증용.
alter table fl_inquiries add column if not exists consent_at timestamptz;
alter table fl_inquiries add column if not exists consent_version text default '';
