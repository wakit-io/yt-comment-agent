-- 웹푸시 VAPID 키를 DB에 자동 저장(배포마다 env 설정 없이 자동 생성·영속).
-- env(PUBLIC_VAPID_KEY/VAPID_PRIVATE_KEY)가 있으면 그걸 우선 사용, 없으면 앱이 생성해 여기 저장.
alter table fl_site add column if not exists push_config jsonb default '{}'::jsonb;
